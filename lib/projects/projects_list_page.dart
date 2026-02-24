import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_secrets.dart';
import '../exchange/exchange_rate_client.dart';
import '../exchange/open_exchange_rates_service.dart';
import '../income_database.dart';
import '../project.dart';
import '../settings/settings_page.dart';
import 'add_project_page.dart';
import 'project_detail_page.dart';

class ProjectsListPage extends StatefulWidget {
  const ProjectsListPage({super.key});

  @override
  State<ProjectsListPage> createState() => _ProjectsListPageState();
}

class _ProjectsListPageState extends State<ProjectsListPage> {
  bool _isLoading = true;
  List<Project> _projects = const [];
  double? _totalUsd;
  double? _totalXaf;
  bool _isLoadingTotals = false;
  String? _totalsError;
  Map<int, double> _projectXafAmounts = const {};

  ExchangeRateClient? _exchangeClient;

  @override
  void initState() {
    super.initState();
    _initExchangeClient();
    _load();
  }

  void _initExchangeClient() {
    final appId = AppSecrets.openExchangeRatesAppId.trim();
    if (appId.isEmpty) return;
    _exchangeClient = ExchangeRateClient(
      service: OpenExchangeRatesService(appId: appId),
    );
  }

  Future<void> _load() async {
    final projects = await IncomeDatabase.instance.getProjects();
    setState(() {
      _projects = projects;
      _isLoading = false;
      _totalUsd = null;
      _totalXaf = null;
      _totalsError = null;
      _projectXafAmounts = const {};
    });
    if (projects.isNotEmpty) {
      await _computeAggregates(projects);
    }
  }

  Future<void> _computeAggregates(List<Project> projects) async {
    setState(() {
      _isLoadingTotals = true;
      _totalsError = null;
    });

    final db = IncomeDatabase.instance;
    final fxAdj = await db.getFxAdjustmentPercent();
    double applyAdj(double rate) => rate * (1 + fxAdj / 100.0);

    double sumUsd = 0.0;
    double sumXaf = 0.0;
    final projectXafAmounts = <int, double>{};
    String? error;

    if (_exchangeClient != null) {
      try {
        for (final p in projects) {
          final id = p.id;
          if (id == null) continue;

          final base = p.baseCurrency.toUpperCase();
          final income = p.totalIncome;

          double usdRate;
          if (base == 'USD') {
            usdRate = 1.0;
          } else {
            final cached = await db.getCachedFxRate(from: base, to: 'USD');
            final now = DateTime.now().toUtc();
            if (cached != null && now.difference(cached.asOf).inMinutes < 60) {
              usdRate = cached.rate;
            } else {
              final quote = await _exchangeClient!.getRate(from: base, to: 'USD');
              await db.setCachedFxRate(from: base, to: 'USD', rate: quote.rate, asOf: quote.asOf);
              usdRate = quote.rate;
            }
          }

          double xafRate;
          if (base == 'XAF') {
            xafRate = 1.0;
          } else {
            final cached = await db.getCachedFxRate(from: base, to: 'XAF');
            final now = DateTime.now().toUtc();
            if (cached != null && now.difference(cached.asOf).inMinutes < 60) {
              xafRate = applyAdj(cached.rate);
            } else {
              final quote = await _exchangeClient!.getRate(from: base, to: 'XAF');
              await db.setCachedFxRate(from: base, to: 'XAF', rate: quote.rate, asOf: quote.asOf);
              xafRate = applyAdj(quote.rate);
            }
          }

          final xafAmount = income * xafRate;
          sumUsd += income * usdRate;
          sumXaf += xafAmount;
          projectXafAmounts[id] = xafAmount;
        }
      } on Object catch (e) {
        error = e.toString();
      }
    } else {
      error = 'FX disabled';
    }

    if (!mounted) return;
    setState(() {
      _totalUsd = error == null ? sumUsd : null;
      _totalXaf = error == null ? sumXaf : null;
      _projectXafAmounts = projectXafAmounts;
      _totalsError = error;
      _isLoadingTotals = false;
    });
  }

  List<Project> get _sortedProjects {
    final list = List<Project>.from(_projects);
    list.sort((a, b) {
      final xafA = (a.id != null ? _projectXafAmounts[a.id] : null) ?? 0.0;
      final xafB = (b.id != null ? _projectXafAmounts[b.id] : null) ?? 0.0;
      return xafB.compareTo(xafA);
    });
    return list;
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

  Future<void> _addProject() async {
    final created = await Navigator.of(context).push<Project>(
      MaterialPageRoute(builder: (_) => const AddProjectPage()),
    );
    if (created == null) return;
    await _load();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProjectDetailPage(projectId: created.id!),
      ),
    );
    await _load();
  }

  Future<void> _openProject(Project project) async {
    if (project.id == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProjectDetailPage(projectId: project.id!),
      ),
    );
    await _load();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  Widget _buildTotalsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Total income',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            if (_isLoadingTotals)
              const Text('Loading…')
            else if (_totalsError != null)
              Text(
                _totalsError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              )
            else ...[
              Text(
                'USD: ${_formatMoney(_totalUsd ?? 0, 'USD')}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'XAF: ${_formatMoney(_totalXaf ?? 0, 'XAF')}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? const Center(child: Text('No projects yet'))
              : Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        itemCount: _sortedProjects.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final p = _sortedProjects[index];
                          final xafAmount = p.id != null
                              ? _projectXafAmounts[p.id]
                              : null;
                          final subtitle = xafAmount != null
                              ? '${_formatMoney(p.totalIncome, p.baseCurrency)} • ${_formatMoney(xafAmount, 'XAF')}'
                              : _formatMoney(p.totalIncome, p.baseCurrency);
                          return ListTile(
                            title: Text(p.name),
                            subtitle: Text(subtitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openProject(p),
                          );
                        },
                      ),
                    ),
                    _buildTotalsSection(),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProject,
        child: const Icon(Icons.add),
      ),
    );
  }
}

