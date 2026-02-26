import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_secrets.dart';
import '../exchange/exchange_rate_client.dart';
import '../exchange/open_exchange_rates_service.dart';
import '../income_database.dart';
import '../project.dart';
import '../time_entries/add_time_entry_sheet.dart';
import '../time_entries/hour_logs_page.dart';
import '../widgets/currency_badge.dart';
import '../widgets/currency_selector.dart';
import '../widgets/skeleton_box.dart';

class ProjectDetailPage extends StatefulWidget {
  const ProjectDetailPage({super.key, required this.projectId});

  final int projectId;

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  bool _isLoading = true;
  Project? _project;

  late final TextEditingController _nameController;
  late final TextEditingController _rateController;
  String _currency = 'USD';

  final _hoursController = TextEditingController();
  final _minutesController = TextEditingController();
  final _secondsController = TextEditingController();
  final _fxAdjustmentController = TextEditingController();
  final _bonusController = TextEditingController();

  double? _totalIncomeBase;
  bool _isLoadingRate = false;
  String? _fxError;
  double? _baseToXafRate;

  ExchangeRateClient? _exchangeClient;

  Timer? _autoSaveTimer;
  bool _showSavedIndicator = false;

  // Inline validation errors
  String? _nameError;
  String? _rateError;

  // Snapshot of last persisted values — used to detect real changes
  _FieldSnapshot? _lastSaved;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _rateController = TextEditingController();
    _initExchangeClient();
    _load();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _nameController.dispose();
    _rateController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    _fxAdjustmentController.dispose();
    _bonusController.dispose();
    super.dispose();
  }

  void _initExchangeClient() {
    final appId = AppSecrets.openExchangeRatesAppId.trim();
    if (appId.isEmpty) {
      _exchangeClient = null;
      _fxError =
          'FX disabled: missing Open Exchange Rates app id in AppSecrets.';
      return;
    }
    _exchangeClient = ExchangeRateClient(
      service: OpenExchangeRatesService(appId: appId),
    );
  }

  Future<void> _load() async {
    final project = await IncomeDatabase.instance.getProjectById(
      widget.projectId,
    );

    if (!mounted) return;
    setState(() {
      _project = project;
      _isLoading = false;
    });

    if (project == null) return;

    _nameController.text = project.name;
    _rateController.text = project.hourlyRate.toString();
    _currency = project.baseCurrency.toUpperCase();
    _fxAdjustmentController.text = project.fxAdjustmentPercent.toString();
    _bonusController.text = project.bonus.toString();

    final totalSeconds = (project.totalHours * 3600).round();
    final h = totalSeconds ~/ 3600;
    final rem = totalSeconds % 3600;
    final m = rem ~/ 60;
    final s = rem % 60;
    _hoursController.text = h.toString();
    _minutesController.text = m.toString();
    _secondsController.text = s.toString();

    // Capture baseline so we can detect real changes later
    _lastSaved = _currentSnapshot();

    _recomputeTotals();
    await _updateConversion();
  }

  /// Returns a snapshot of the current field values.
  _FieldSnapshot _currentSnapshot() => _FieldSnapshot(
        name: _nameController.text,
        rate: _rateController.text,
        currency: _currency,
        fxAdj: _fxAdjustmentController.text,
        bonus: _bonusController.text,
      );

  /// Called from each TextField's onChanged and the currency selector.
  void _onFieldChanged() {
    final snap = _currentSnapshot();
    if (snap == _lastSaved) return; // nothing actually changed

    _validate();
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 600), _autoSave);
  }

  void _validate() {
    final name = _nameController.text.trim();
    final rawRate = _rateController.text.trim().replaceAll(',', '');
    final rate = double.tryParse(rawRate);
    setState(() {
      _nameError = name.isEmpty ? 'Project name is required' : null;
      _rateError = (rate == null || rate <= 0) ? 'Enter a valid hourly rate' : null;
    });
  }

  Future<void> _autoSave() async {
    if (_nameError != null || _rateError != null) return;
    final snapBeforeSave = _currentSnapshot();
    final ok = await _trySave();
    if (ok && mounted) {
      _lastSaved = snapBeforeSave;
      setState(() => _showSavedIndicator = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showSavedIndicator = false);
      });
    }
  }

  double _applyFxAdjustment(double rate) {
    final adj = _project?.fxAdjustmentPercent ?? 0.0;
    return rate * (1 + adj / 100.0);
  }

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

  String _formatRate(double rate, String toCurrency) {
    final fmt = NumberFormat.decimalPattern('en_US');
    return '1 ${_currency.toUpperCase()} = ${fmt.format(rate)} ${toCurrency.toUpperCase()}';
  }

  void _recomputeTotals() {
    final project = _project;
    if (project == null) return;
    setState(() {
      _totalIncomeBase = project.totalIncome;
    });
  }

  Future<bool> _trySave() async {
    final project = _project;
    if (project == null) return false;

    final name = _nameController.text.trim();
    if (name.isEmpty) return false;

    final rawRate = _rateController.text.trim().replaceAll(',', '');
    final rate = double.tryParse(rawRate);
    if (rate == null || rate <= 0) return false;

    final rawAdj = _fxAdjustmentController.text.trim().replaceAll(',', '');
    final fxAdj = double.tryParse(rawAdj) ?? 0.0;

    final rawBonus = _bonusController.text.trim().replaceAll(',', '');
    final bonus = double.tryParse(rawBonus) ?? 0.0;

    final updated = project.copyWith(
      name: name,
      hourlyRate: rate,
      baseCurrency: _currency,
      fxAdjustmentPercent: fxAdj,
      bonus: bonus,
      updatedAt: DateTime.now().toUtc(),
    );

    await IncomeDatabase.instance.updateProject(updated);
    if (!mounted) return false;

    setState(() {
      _project = updated;
      _totalIncomeBase = updated.totalIncome;
      _baseToXafRate = null;
    });

    await _updateConversion();
    return true;
  }

  Future<void> _addTimeEntry() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddTimeEntrySheet(projectId: widget.projectId),
    );
    if (result == true) await _refreshAfterEntryChange();
  }

  Future<void> _openHourLogs() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HourLogsPage(projectId: widget.projectId),
      ),
    );
    await _refreshAfterEntryChange();
  }

  Future<void> _refreshAfterEntryChange() async {
    final db = IncomeDatabase.instance;
    final totalHours = await db.getTotalHoursForProject(widget.projectId);
    final project = await db.getProjectById(widget.projectId);
    if (!mounted || project == null) return;

    final totalSeconds = (totalHours * 3600).round();
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    _hoursController.text = h.toString();
    _minutesController.text = m.toString();
    _secondsController.text = s.toString();

    setState(() {
      _project = project;
      _totalIncomeBase = project.totalIncome;
      _baseToXafRate = null;
    });
    await _updateConversion();
  }

  Future<void> _deleteProject() async {
    final project = _project;
    if (project == null || project.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete project'),
        content: Text('Delete "${project.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await IncomeDatabase.instance.deleteProject(project.id!);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _updateConversion() async {
    if (_exchangeClient == null) return;
    final project = _project;
    if (project == null) return;

    setState(() {
      _isLoadingRate = true;
      _fxError = null;
    });

    final from = project.baseCurrency.toUpperCase();
    const to = 'XAF';

    try {
      final db = IncomeDatabase.instance;
      final cached = await db.getCachedFxRate(from: from, to: to);
      final now = DateTime.now().toUtc();

      if (cached != null && now.difference(cached.asOf).inMinutes < 60) {
        if (!mounted) return;
        setState(() {
          _baseToXafRate = _applyFxAdjustment(cached.rate);
          _isLoadingRate = false;
        });
        return;
      }

      final quote = await _exchangeClient!.getRate(from: from, to: to);
      await db.setCachedFxRate(
          from: from, to: to, rate: quote.rate, asOf: quote.asOf);

      if (!mounted) return;
      setState(() {
        _baseToXafRate = _applyFxAdjustment(quote.rate);
        _isLoadingRate = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _fxError = 'Could not load FX rate: $e';
        _isLoadingRate = false;
      });
    }
  }

  // ── Build helpers ──

  Widget _buildResultsSection(Project project) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF2A2A2A) : Colors.black;
    const cardFg = Colors.white;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Expected Income · ${DateFormat.yMMMM().format(DateTime.now())}',
                style: TextStyle(
                  color: cardFg.withOpacity(0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (_showSavedIndicator)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle,
                        size: 12,
                        color: cardFg.withOpacity(0.7)),
                    const SizedBox(width: 4),
                    Text(
                      'Saved',
                      style: TextStyle(
                        color: cardFg.withOpacity(0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  _totalIncomeBase != null
                      ? _formatMoney(
                          _totalIncomeBase!, project.baseCurrency)
                      : '—',
                  style: TextStyle(
                    color: cardFg,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              CurrencyBadge(project.baseCurrency),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 1,
            color: cardFg.withOpacity(0.15),
          ),
          const SizedBox(height: 8),
          if (_fxError != null)
            Text(
              _fxError!,
              style: TextStyle(
                color: cardFg.withOpacity(0.5),
                fontSize: 11,
              ),
            )
          else if (_isLoadingRate)
            const SkeletonBox(width: 140, height: 16)
          else if (_baseToXafRate != null && _totalIncomeBase != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    _formatMoney(
                        _totalIncomeBase! * _baseToXafRate!, 'XAF'),
                    style: TextStyle(
                      color: cardFg.withOpacity(0.8),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const CurrencyBadge('XAF'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _formatRate(_baseToXafRate!, 'XAF'),
              style: TextStyle(
                color: cardFg.withOpacity(0.4),
                fontSize: 10,
              ),
            ),
          ] else
            Text(
              '—',
              style: TextStyle(
                color: cardFg.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          project?.name ?? 'Project',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            enabled: project != null,
            onSelected: (value) {
              if (value == 'delete') _deleteProject();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Delete project',
                        style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: project != null
          ? FloatingActionButton(
              onPressed: _addTimeEntry,
              child: const Icon(Icons.timer_outlined),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : project == null
              ? const Center(child: Text('Project not found'))
              : SafeArea(
                  child: Column(
                    children: [
                      // Fixed income card at top
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: _buildResultsSection(project),
                      ),

                      // Scrollable form in the middle
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Project info section
                              _buildSectionCard(
                                title: 'PROJECT INFO',
                                children: [
                                  TextField(
                                    controller: _nameController,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: InputDecoration(
                                        labelText: 'Project name',
                                        errorText: _nameError),
                                    onChanged: (_) => _onFieldChanged(),
                                  ),
                                  const SizedBox(height: 12),
                                  CurrencySelector(
                                    value: _currency.trim().isEmpty
                                        ? 'USD'
                                        : _currency,
                                    onChanged: (value) {
                                      setState(() {
                                        _currency = value.trim().isEmpty
                                            ? 'USD'
                                            : value;
                                        _baseToXafRate = null;
                                      });
                                      _onFieldChanged();
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _rateController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: InputDecoration(
                                        labelText: 'Hourly rate',
                                        errorText: _rateError),
                                    onChanged: (_) => _onFieldChanged(),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Bank FX adjustment',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _fxAdjustmentController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'e.g. -10 or 10',
                                      suffixText: '%',
                                    ),
                                    onChanged: (_) => _onFieldChanged(),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Time section — tappable to open Hour Logs
                              GestureDetector(
                                onTap: _openHourLogs,
                                child: _buildSectionCard(
                                  title: 'TIME',
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _hoursController,
                                            readOnly: true,
                                            decoration: const InputDecoration(
                                                labelText: 'Hours'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextField(
                                            controller: _minutesController,
                                            readOnly: true,
                                            decoration: const InputDecoration(
                                                labelText: 'Min'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextField(
                                            controller: _secondsController,
                                            readOnly: true,
                                            decoration: const InputDecoration(
                                                labelText: 'Sec'),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'View all time entries',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.chevron_right,
                                          size: 16,
                                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Bonus section
                              _buildSectionCard(
                                title: 'BONUS',
                                children: [
                                  TextField(
                                    controller: _bonusController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                        labelText: 'Flat bonus payment'),
                                    onChanged: (_) => _onFieldChanged(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

/// Lightweight snapshot of editable field values for change detection.
class _FieldSnapshot {
  const _FieldSnapshot({
    required this.name,
    required this.rate,
    required this.currency,
    required this.fxAdj,
    required this.bonus,
  });

  final String name;
  final String rate;
  final String currency;
  final String fxAdj;
  final String bonus;

  @override
  bool operator ==(Object other) =>
      other is _FieldSnapshot &&
      name == other.name &&
      rate == other.rate &&
      currency == other.currency &&
      fxAdj == other.fxAdj &&
      bonus == other.bonus;

  @override
  int get hashCode =>
      Object.hash(name, rate, currency, fxAdj, bonus);
}
