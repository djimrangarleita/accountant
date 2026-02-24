import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_secrets.dart';
import '../exchange/exchange_rate_client.dart';
import '../exchange/open_exchange_rates_service.dart';
import '../income_database.dart';
import '../project.dart';
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

    _recomputeTotals();
    _addFieldListeners();
    await _updateConversion();
  }

  void _addFieldListeners() {
    for (final c in [
      _nameController,
      _rateController,
      _hoursController,
      _minutesController,
      _secondsController,
      _fxAdjustmentController,
      _bonusController,
    ]) {
      c.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 500), () {
      _autoSave();
    });
  }

  Future<void> _autoSave() async {
    final ok = await _trySave(showSnackOnError: false);
    if (ok && mounted) {
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

  /// Returns true if save succeeded.
  Future<bool> _trySave({bool showSnackOnError = true}) async {
    final project = _project;
    if (project == null) return false;

    final name = _nameController.text.trim();
    if (name.isEmpty) return false;

    final rawRate = _rateController.text.trim().replaceAll(',', '');
    final rate = double.tryParse(rawRate);
    if (rate == null || rate <= 0) return false;

    final rawHours = _hoursController.text.trim().replaceAll(',', '');
    final rawMinutes = _minutesController.text.trim().replaceAll(',', '');
    final rawSeconds = _secondsController.text.trim().replaceAll(',', '');

    final hours = rawHours.isEmpty ? 0.0 : double.tryParse(rawHours);
    if (hours == null || hours < 0) return false;
    final minutes = rawMinutes.isEmpty ? 0 : int.tryParse(rawMinutes);
    final seconds = rawSeconds.isEmpty ? 0 : int.tryParse(rawSeconds);

    if (minutes == null || minutes < 0 || minutes >= 60) return false;
    if (seconds == null || seconds < 0 || seconds >= 60) return false;

    final totalHours = hours + minutes / 60.0 + seconds / 3600.0;

    final rawAdj = _fxAdjustmentController.text.trim().replaceAll(',', '');
    final fxAdj = double.tryParse(rawAdj) ?? 0.0;

    final rawBonus = _bonusController.text.trim().replaceAll(',', '');
    final bonus = double.tryParse(rawBonus) ?? 0.0;

    final updated = project.copyWith(
      name: name,
      hourlyRate: rate,
      baseCurrency: _currency,
      totalHours: totalHours,
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

  Future<void> _calculateAndSave() async {
    final project = _project;
    if (project == null) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project name is required')),
      );
      return;
    }

    final rawRate = _rateController.text.trim().replaceAll(',', '');
    final rate = double.tryParse(rawRate);
    if (rate == null || rate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid hourly rate')),
      );
      return;
    }

    final ok = await _trySave(showSnackOnError: true);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Saved'),
            ],
          ),
          duration: Duration(seconds: 1),
        ),
      );
    }
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black,
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
                  color: Colors.white.withOpacity(0.7),
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
                        color: Colors.white.withOpacity(0.7)),
                    const SizedBox(width: 4),
                    Text(
                      'Saved',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
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
                  style: const TextStyle(
                    color: Colors.white,
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
            color: Colors.white.withOpacity(0.15),
          ),
          const SizedBox(height: 8),
          if (_fxError != null)
            Text(
              _fxError!,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
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
                      color: Colors.white.withOpacity(0.8),
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
                color: Colors.white.withOpacity(0.4),
                fontSize: 10,
              ),
            ),
          ] else
            Text(
              '—',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
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
                color: Colors.grey.shade600,
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
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
                                    decoration: const InputDecoration(
                                        labelText: 'Project name'),
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
                                  Text(
                                    'Bank FX adjustment',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700,
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
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Time section
                              _buildSectionCard(
                                title: 'TIME',
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _hoursController,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(
                                              decimal: true),
                                          decoration: const InputDecoration(
                                              labelText: 'Hours'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _minutesController,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(),
                                          decoration: const InputDecoration(
                                              labelText: 'Min'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _secondsController,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(),
                                          decoration: const InputDecoration(
                                              labelText: 'Sec'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Rate section
                              _buildSectionCard(
                                title: 'RATE',
                                children: [
                                  TextField(
                                    controller: _rateController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                        labelText: 'Hourly rate'),
                                  ),
                                ],
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
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Fixed button at bottom
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _calculateAndSave,
                            child: const Text('Calculate & save'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
