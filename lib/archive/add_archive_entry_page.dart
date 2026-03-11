import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../income_database.dart';
import '../monthly_snapshot.dart';
import '../project.dart';
import '../widgets/currency_selector.dart';

class AddArchiveEntryPage extends StatefulWidget {
  const AddArchiveEntryPage({
    super.key,
    this.prefilledMonth,
    this.existingSnapshot,
  });

  final String? prefilledMonth;
  final MonthlySnapshot? existingSnapshot;

  bool get isEditing => existingSnapshot != null;

  @override
  State<AddArchiveEntryPage> createState() => _AddArchiveEntryPageState();
}

class _AddArchiveEntryPageState extends State<AddArchiveEntryPage> {
  bool _isLoadingProjects = true;
  List<Project> _projects = const [];

  String? _selectedMonth;
  bool _fromExistingProject = true;
  Project? _selectedProject;

  final _nameController = TextEditingController();
  final _rateController = TextEditingController();
  String _currency = 'USD';

  final _hoursController = TextEditingController();
  final _bonusController = TextEditingController(text: '0');
  final _usdRateController = TextEditingController();
  final _secondRateController = TextEditingController();
  String _secondCurrency = 'XAF';

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final snap = widget.existingSnapshot;
    if (snap != null) {
      _selectedMonth = snap.month;
      _fromExistingProject = snap.projectId != 0;
      _nameController.text = snap.name;
      _rateController.text = snap.hourlyRate.toString();
      _currency = snap.baseCurrency;
      _hoursController.text = snap.totalHours.toString();
      _bonusController.text = snap.bonus.toString();
      _secondCurrency = snap.secondCurrency;
      if (snap.baseToXafRate > 0) {
        _secondRateController.text = snap.baseToXafRate.toString();
      }
      if (snap.baseToUsdRate > 0) {
        _usdRateController.text = snap.baseToUsdRate.toString();
      }
    } else {
      _selectedMonth = widget.prefilledMonth ?? _pastMonths.first;
    }
    _loadProjects();
    _loadSecondCurrency();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rateController.dispose();
    _hoursController.dispose();
    _bonusController.dispose();
    _usdRateController.dispose();
    _secondRateController.dispose();
    super.dispose();
  }

  Future<void> _loadSecondCurrency() async {
    final snap = widget.existingSnapshot;
    if (snap != null && snap.isClosed) return;

    final code = await IncomeDatabase.instance.getSecondCurrency();
    if (!mounted) return;

    if (snap != null && code != snap.secondCurrency) {
      _secondRateController.clear();
    }

    setState(() => _secondCurrency = code);
  }

  List<String> get _pastMonths {
    final now = DateTime.now();
    final months = <String>[];
    for (int i = 1; i <= 24; i++) {
      final d = DateTime(now.year, now.month - i, 1);
      months.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
    }
    return months;
  }

  String _monthLabel(String month) {
    final parts = month.split('-');
    if (parts.length != 2) return month;
    final year = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (year == null || m == null || m < 1 || m > 12) return month;
    return DateFormat.yMMMM().format(DateTime(year, m));
  }

  Future<void> _loadProjects() async {
    final projects = await IncomeDatabase.instance.getProjects();
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _isLoadingProjects = false;
      final snap = widget.existingSnapshot;
      if (snap != null && snap.projectId != 0) {
        final match = projects.where((p) => p.id == snap.projectId);
        if (match.isNotEmpty) _selectedProject = match.first;
      }
    });
  }

  void _onProjectSelected(Project? project) {
    setState(() {
      _selectedProject = project;
      if (project != null) {
        _nameController.text = project.name;
        _rateController.text = project.hourlyRate.toString();
        _currency = project.baseCurrency;
      }
    });
  }

  double get _hourlyRate =>
      double.tryParse(_rateController.text.trim().replaceAll(',', '')) ?? 0;

  double get _hours =>
      double.tryParse(_hoursController.text.trim().replaceAll(',', '')) ?? 0;

  double get _bonus =>
      double.tryParse(_bonusController.text.trim().replaceAll(',', '')) ?? 0;

  double get _usdRate =>
      _currency.toUpperCase() == 'USD'
          ? 1.0
          : double.tryParse(
                  _usdRateController.text.trim().replaceAll(',', '')) ??
              0;

  double get _secondRate =>
      _currency.toUpperCase() == _secondCurrency.toUpperCase()
          ? 1.0
          : double.tryParse(
                  _secondRateController.text.trim().replaceAll(',', '')) ??
              0;

  double get _totalIncomeBase => _hourlyRate * _hours + _bonus;

  double get _totalIncomeUsd => _totalIncomeBase * _usdRate;

  double get _totalIncomeSecond => _totalIncomeBase * _secondRate;

  String _formatMoney(double amount, String currency) {
    final code = currency.toUpperCase();
    if (code == 'USD') {
      return NumberFormat.currency(
              locale: 'en_US', symbol: r'$', decimalDigits: 2)
          .format(amount);
    }
    if (code == 'XAF') {
      final fmt = NumberFormat.decimalPattern('fr_FR');
      return '${fmt.format(amount.round())} XAF';
    }
    final fmt = NumberFormat.decimalPattern('en_US');
    return '${fmt.format(double.parse(amount.toStringAsFixed(2)))} $code';
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a project name')),
      );
      return;
    }
    if (_hourlyRate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid hourly rate')),
      );
      return;
    }
    if (_hours <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter hours worked')),
      );
      return;
    }
    if (_selectedMonth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a month')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final existing = widget.existingSnapshot;
      final projectId = existing != null
          ? existing.projectId
          : (_fromExistingProject && _selectedProject != null)
              ? _selectedProject!.id ?? 0
              : 0;

      final snapshot = MonthlySnapshot(
        id: existing?.id,
        projectId: projectId,
        month: _selectedMonth!,
        name: name,
        hourlyRate: _hourlyRate,
        baseCurrency: _currency,
        totalHours: _hours,
        fxAdjustmentPercent: 0.0,
        bonus: _bonus,
        totalIncomeBase: _totalIncomeBase,
        baseToXafRate: _secondRate,
        totalIncomeXaf: _totalIncomeSecond,
        baseToUsdRate: _usdRate,
        totalIncomeUsd: _totalIncomeUsd,
        closedAt: existing?.closedAt ?? DateTime.now().toUtc(),
        isClosed: false,
        secondCurrency: _secondCurrency,
      );

      final db = IncomeDatabase.instance;
      if (existing != null) {
        await db.updateSnapshot(snapshot);
      } else {
        await db.insertSnapshot(snapshot);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Widgets ──

  Widget _buildMonthPicker() {
    final months = _pastMonths;
    return DropdownButtonFormField<String>(
      value: _selectedMonth,
      decoration: const InputDecoration(labelText: 'Month'),
      items: months.map((m) {
        return DropdownMenuItem(value: m, child: Text(_monthLabel(m)));
      }).toList(),
      onChanged: (widget.prefilledMonth != null || widget.isEditing)
          ? null
          : (value) => setState(() => _selectedMonth = value),
    );
  }

  Widget _buildSourceToggle() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _fromExistingProject = true),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _fromExistingProject
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(8),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                'From project',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _fromExistingProject
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _fromExistingProject = false;
              _selectedProject = null;
              _nameController.clear();
              _rateController.clear();
              _currency = 'USD';
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: !_fromExistingProject
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(8),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                'New entry',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: !_fromExistingProject
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProjectSelector() {
    if (_isLoadingProjects) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_projects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No projects available. Use "New entry" instead.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
        ),
      );
    }
    return DropdownButtonFormField<int>(
      value: _selectedProject?.id,
      decoration: const InputDecoration(labelText: 'Select project'),
      items: _projects.map((p) {
        return DropdownMenuItem(
          value: p.id,
          child: Text('${p.name} (${p.baseCurrency})'),
        );
      }).toList(),
      onChanged: (id) {
        final project = _projects.firstWhere((p) => p.id == id);
        _onProjectSelected(project);
      },
    );
  }

  Widget _buildResultsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Computed totals',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _usdRate > 0 ? _formatMoney(_totalIncomeUsd, 'USD') : '—',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _secondRate > 0
                ? _formatMoney(_totalIncomeSecond, _secondCurrency)
                : '—',
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  bool get _isEditing => widget.isEditing;

  bool get _showProjectFields =>
      _isEditing || !_fromExistingProject;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Entry' : 'Add Archive Entry',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMonthPicker(),
            const SizedBox(height: 20),

            if (!_isEditing) ...[
              _buildSourceToggle(),
              const SizedBox(height: 16),
            ],

            if (!_isEditing && _fromExistingProject) ...[
              _buildProjectSelector(),
              const SizedBox(height: 12),
            ],

            if (_showProjectFields) ...[
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Project name'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rateController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Hourly rate'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              CurrencySelector(
                value: _currency,
                onChanged: (value) => setState(() => _currency = value),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _hoursController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Total hours'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bonusController,
              keyboardType:
                  const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Bonus'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_currency.toUpperCase() != 'USD')
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _usdRateController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '1 ${_currency.toUpperCase()} = ? USD',
                    hintText: 'Exchange rate to USD',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            if (_currency.toUpperCase() != _secondCurrency.toUpperCase())
              TextField(
                controller: _secondRateController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '1 ${_currency.toUpperCase()} = ? $_secondCurrency',
                  hintText: 'Exchange rate to $_secondCurrency',
                ),
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 20),
            _buildResultsCard(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : Text(_isEditing ? 'Save changes' : 'Save entry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
