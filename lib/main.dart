import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'income_database.dart';
import 'exchange/exchange_rate_client.dart';
import 'exchange/open_exchange_rates_service.dart';
import 'app_secrets.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Colors.black,
      onPrimary: Colors.white,
      secondary: Colors.grey,
      onSecondary: Colors.white,
      error: Colors.red,
      onError: Colors.white,
      surface: Colors.white,
      onSurface: Colors.black,
    );

    return MaterialApp(
      title: 'Hourly Income',
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.background,
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
          ),
        ),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Hourly income calculator'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _hoursController = TextEditingController();
  final TextEditingController _minutesController = TextEditingController();
  final TextEditingController _secondsController = TextEditingController();

  bool _isLoading = true;
  double? _hourlyRate;
  double? _calculatedTotal;

  ExchangeRateClient? _exchangeClient;
  double? _usdToXafBaseRate;
  String? _fxError;
  bool _isLoadingRate = false;
  double _fxAdjustmentPercent = 0.0;

  String _formatUsd(double amount) {
    final fmt = NumberFormat.currency(
      locale: 'en_US',
      symbol: r'$',
      decimalDigits: 2,
    );
    return fmt.format(amount);
  }

  String _formatXaf(double amount) {
    final fmt = NumberFormat.decimalPattern('fr_FR');
    return '${fmt.format(amount.round())} XAF';
  }

  String _formatRate(double rate) {
    final fmt = NumberFormat.decimalPattern('en_US');
    return fmt.format(rate);
  }

  double? get _effectiveUsdToXafRate =>
      _usdToXafBaseRate == null ? null : _applyFxAdjustment(_usdToXafBaseRate!);

  double _applyFxAdjustment(double baseRate) =>
      baseRate * (1 + _fxAdjustmentPercent / 100.0);

  @override
  void initState() {
    super.initState();
    _initExchangeClient();
    _loadInitialData();
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final db = IncomeDatabase.instance;
    final hourlyRate = await db.getHourlyRate();
    final lastHours = await db.getLastHours();
    final fxAdj = await db.getFxAdjustmentPercent();

    setState(() {
      _hourlyRate = hourlyRate;
      _fxAdjustmentPercent = fxAdj;
      if (lastHours != null) {
        final totalSeconds = (lastHours * 3600).round();
        final hours = totalSeconds ~/ 3600;
        final remainingSeconds = totalSeconds % 3600;
        final minutes = remainingSeconds ~/ 60;
        final seconds = remainingSeconds % 60;

        _hoursController.text = hours.toString();
        _minutesController.text = minutes.toString();
        _secondsController.text = seconds.toString();

        if (hourlyRate != null) {
          _calculatedTotal = hourlyRate * lastHours;
        }
      } else {
        _hoursController.text = '0';
        _minutesController.text = '0';
        _secondsController.text = '0';
      }
      _isLoading = false;
    });

    if (_calculatedTotal != null) {
      await _updateConversion();
    }
  }

  void _initExchangeClient() {
    final appId = AppSecrets.openExchangeRatesAppId.trim();
    if (appId.isEmpty) {
      _fxError =
          'FX disabled: missing Open Exchange Rates app id in AppSecrets.';
      return;
    }

    _exchangeClient = ExchangeRateClient(
      service: OpenExchangeRatesService(appId: appId),
    );
  }

  Future<void> _updateConversion() async {
    if (_exchangeClient == null) return;
    if (_calculatedTotal == null) return;

    setState(() {
      _isLoadingRate = true;
      _fxError = null;
    });

    try {
      final db = IncomeDatabase.instance;
      final cachedRate = await db.getCachedUsdToXafRate();
      final cachedTs = await db.getCachedUsdToXafRateTimestamp();
      final now = DateTime.now().toUtc();

      if (cachedRate != null &&
          cachedTs != null &&
          now.difference(cachedTs).inMinutes < 60) {
        if (!mounted) return;
        setState(() {
          _usdToXafBaseRate = cachedRate;
          _isLoadingRate = false;
        });
        return;
      }

      final quote = await _exchangeClient!.getRate(from: 'USD', to: 'XAF');
      await db.setCachedUsdToXafRate(quote.rate, quote.asOf);

      if (!mounted) return;
      setState(() {
        _usdToXafBaseRate = quote.rate;
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

  Future<void> _calculate() async {
    final rawHours = _hoursController.text.trim().replaceAll(',', '');
    final rawMinutes = _minutesController.text.trim().replaceAll(',', '');
    final rawSeconds = _secondsController.text.trim().replaceAll(',', '');

    if (rawHours.isEmpty && rawMinutes.isEmpty && rawSeconds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one time value')),
      );
      return;
    }

    final hours = rawHours.isEmpty ? 0.0 : double.tryParse(rawHours);
    if (hours == null || hours < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please enter a valid value for hours (can be decimal)'),
        ),
      );
      return;
    }

    final minutes = rawMinutes.isEmpty ? 0 : int.tryParse(rawMinutes);
    final seconds = rawSeconds.isEmpty ? 0 : int.tryParse(rawSeconds);

    if (minutes == null || minutes < 0 || minutes >= 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minutes must be a number between 0 and 59'),
        ),
      );
      return;
    }

    if (seconds == null || seconds < 0 || seconds >= 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seconds must be a number between 0 and 59'),
        ),
      );
      return;
    }

    final totalHours = hours + minutes / 60.0 + seconds / 3600.0;

    if (_hourlyRate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set your hourly rate in settings first'),
        ),
      );
      return;
    }

    await IncomeDatabase.instance.setLastHours(totalHours);

    setState(() {
      _calculatedTotal = totalHours * _hourlyRate!;
    });

    await _updateConversion();
  }

  Future<void> _openSettings() async {
    final newRate = await Navigator.of(context).push<double>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          initialHourlyRate: _hourlyRate,
          initialFxAdjustmentPercent: _fxAdjustmentPercent,
        ),
      ),
    );

    if (newRate != null) {
      setState(() {
        _hourlyRate = newRate;
        final rawHours = _hoursController.text.trim().replaceAll(',', '');
        final rawMinutes = _minutesController.text.trim().replaceAll(',', '');
        final rawSeconds = _secondsController.text.trim().replaceAll(',', '');

        final hours = rawHours.isEmpty ? 0.0 : double.tryParse(rawHours);
        final minutes = rawMinutes.isEmpty ? 0 : int.tryParse(rawMinutes);
        final seconds = rawSeconds.isEmpty ? 0 : int.tryParse(rawSeconds);

        if (hours != null && minutes != null && seconds != null) {
          final totalHours = hours + minutes / 60.0 + seconds / 3600.0;
          _calculatedTotal = totalHours * newRate;
        }
      });

      // Refresh adjustment and conversion using latest settings.
      _fxAdjustmentPercent =
          await IncomeDatabase.instance.getFxAdjustmentPercent();

      await _updateConversion();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hourly rate:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _hourlyRate == null
                          ? 'Not set (open settings to configure)'
                          : '${_formatUsd(_hourlyRate!)} per hour',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
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
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Hours (h or decimal)',
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
                              labelText: 'Minutes (m)',
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
                              labelText: 'Seconds (s)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You can enter time as h, h:m, or h:m:s. '
                      'Decimals are supported in the hours field (e.g. 19.3).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _calculate,
                        child: const Text('Calculate income'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Total income (USD)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _hourlyRate == null || _calculatedTotal == null
                          ? '—'
                          : _formatUsd(_calculatedTotal!),
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
                      const Text('Loading exchange rate (USD → XAF)...')
                  else if (_effectiveUsdToXafRate == null ||
                      _calculatedTotal == null)
                      const Text('—')
                    else ...[
                      Text(
                      _formatXaf(_calculatedTotal! * _effectiveUsdToXafRate!),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                      'Rate used: 1 USD = ${_formatRate(_effectiveUsdToXafRate!)} XAF',
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

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.initialHourlyRate,
    this.initialFxAdjustmentPercent,
  });

  final double? initialHourlyRate;
  final double? initialFxAdjustmentPercent;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _rateController;
  late final TextEditingController _fxAdjustmentController;

  @override
  void initState() {
    super.initState();
    _rateController = TextEditingController(
      text: widget.initialHourlyRate?.toString() ?? '',
    );
    _fxAdjustmentController = TextEditingController(
      text: (widget.initialFxAdjustmentPercent ?? 0).toString(),
    );
  }

  @override
  void dispose() {
    _rateController.dispose();
    _fxAdjustmentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rawRate = _rateController.text.trim().replaceAll(',', '');
    final rate = double.tryParse(rawRate);

    if (rate == null || rate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid hourly rate')),
      );
      return;
    }

    final rawAdj =
        _fxAdjustmentController.text.trim().replaceAll(',', '');
    final adj = double.tryParse(rawAdj);

    if (adj == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid adjustment (can be negative or positive)'),
        ),
      );
      return;
    }

    await IncomeDatabase.instance.setHourlyRate(rate);
    await IncomeDatabase.instance.setFxAdjustmentPercent(adj);

    if (!mounted) return;
    Navigator.of(context).pop<double>(rate);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hourly rate',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount per hour',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Bank FX adjustment (%)',
              style: Theme.of(context).textTheme.titleMedium,
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
                labelText: 'Adjustment in percent (e.g. -10 or 10)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
