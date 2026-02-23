import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_secrets.dart';
import '../exchange/exchange_rate_client.dart';
import '../exchange/open_exchange_rates_service.dart';
import '../income_database.dart';
import '../project.dart';

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

  final TextEditingController _hoursController = TextEditingController();
  final TextEditingController _minutesController = TextEditingController();
  final TextEditingController _secondsController = TextEditingController();

  double? _totalIncomeBase;
  double? _fxAdjustmentPercent;
  bool _isLoadingRate = false;
  String? _fxError;
  double? _baseToXafRate;

  ExchangeRateClient? _exchangeClient;

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
    _nameController.dispose();
    _rateController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  void _initExchangeClient() {
    final appId = AppSecrets.openExchangeRatesAppId.trim();
    if (appId.isEmpty) {
      _exchangeClient = null;
      _fxError = 'FX disabled: missing Open Exchange Rates app id in AppSecrets.';
      return;
    }
    _exchangeClient = ExchangeRateClient(
      service: OpenExchangeRatesService(appId: appId),
    );
  }

  Future<void> _load() async {
    final db = IncomeDatabase.instance;
    final project = await db.getProjectById(widget.projectId);
    final fxAdj = await db.getFxAdjustmentPercent();

    if (!mounted) return;
    setState(() {
      _project = project;
      _fxAdjustmentPercent = fxAdj;
      _isLoading = false;
    });

    if (project == null) return;

    _nameController.text = project.name;
    _rateController.text = project.hourlyRate.toString();
    _currency = project.baseCurrency.toUpperCase();

    final totalSeconds = (project.totalHours * 3600).round();
    final h = totalSeconds ~/ 3600;
    final rem = totalSeconds % 3600;
    final m = rem ~/ 60;
    final s = rem % 60;
    _hoursController.text = h.toString();
    _minutesController.text = m.toString();
    _secondsController.text = s.toString();

    _recomputeTotals();
    await _updateConversion();
  }

  double _applyFxAdjustment(double rate) {
    final adj = _fxAdjustmentPercent ?? 0.0;
    return rate * (1 + adj / 100.0);
  }

  String _formatMoney(double amount, String currency) {
    final code = currency.toUpperCase();
    if (code == 'USD') {
      return NumberFormat.currency(locale: 'en_US', symbol: r'$', decimalDigits: 2)
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

    final rawHours = _hoursController.text.trim().replaceAll(',', '');
    final rawMinutes = _minutesController.text.trim().replaceAll(',', '');
    final rawSeconds = _secondsController.text.trim().replaceAll(',', '');

    final hours = rawHours.isEmpty ? 0.0 : double.tryParse(rawHours);
    if (hours == null || hours < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hours must be a valid number')),
      );
      return;
    }
    final minutes = rawMinutes.isEmpty ? 0 : int.tryParse(rawMinutes);
    final seconds = rawSeconds.isEmpty ? 0 : int.tryParse(rawSeconds);

    if (minutes == null || minutes < 0 || minutes >= 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minutes must be between 0 and 59')),
      );
      return;
    }
    if (seconds == null || seconds < 0 || seconds >= 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seconds must be between 0 and 59')),
      );
      return;
    }

    final totalHours = hours + minutes / 60.0 + seconds / 3600.0;

    final updated = project.copyWith(
      name: name,
      hourlyRate: rate,
      baseCurrency: _currency,
      totalHours: totalHours,
      updatedAt: DateTime.now().toUtc(),
    );

    await IncomeDatabase.instance.updateProject(updated);
    setState(() {
      _project = updated;
      _totalIncomeBase = updated.totalIncome;
      _baseToXafRate = null;
    });

    await _updateConversion();
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
      await db.setCachedFxRate(from: from, to: to, rate: quote.rate, asOf: quote.asOf);

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

  @override
  Widget build(BuildContext context) {
    final project = _project;
    return Scaffold(
      appBar: AppBar(
        title: Text(project?.name ?? 'Project'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : project == null
              ? const Center(child: Text('Project not found'))
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Project name',
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _currency,
                          decoration: const InputDecoration(
                            labelText: 'Base currency',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'USD', child: Text('USD')),
                            DropdownMenuItem(value: 'XAF', child: Text('XAF')),
                            DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                            DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _currency = value;
                              _baseToXafRate = null;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _rateController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Hourly rate',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Total hours',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _hoursController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Hours',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _minutesController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(),
                                decoration: const InputDecoration(
                                  labelText: 'Minutes',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _secondsController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(),
                                decoration: const InputDecoration(
                                  labelText: 'Seconds',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _calculateAndSave,
                            child: const Text('Calculate & save'),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Total income (${project.baseCurrency.toUpperCase()})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _totalIncomeBase == null
                              ? '—'
                              : _formatMoney(
                                  _totalIncomeBase!,
                                  project.baseCurrency,
                                ),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Total income (XAF)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (_fxError != null)
                          Text(
                            _fxError!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.red),
                          )
                        else if (_isLoadingRate)
                          const Text('Loading exchange rate...')
                        else if (_baseToXafRate == null || _totalIncomeBase == null)
                          const Text('—')
                        else ...[
                          Text(
                            _formatMoney(_totalIncomeBase! * _baseToXafRate!, 'XAF'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Rate used: ${_formatRate(_baseToXafRate!, 'XAF')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }
}

