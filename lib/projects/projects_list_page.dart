import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_secrets.dart';
import '../archive/archive_page.dart';
import '../exchange/exchange_rate_client.dart';
import '../exchange/open_exchange_rates_service.dart';
import '../income_database.dart';
import '../monthly_snapshot.dart';
import '../project.dart';
import '../settings/settings_page.dart';
import '../time_entries/add_time_entry_sheet.dart';
import '../widgets/currency_badge.dart';
import '../widgets/currency_selector.dart';
import '../widgets/skeleton_box.dart';
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
  double? _totalSecond;
  bool _isLoadingTotals = false;
  String? _totalsError;
  Map<int, double> _projectSecondAmounts = const {};
  String _secondCurrency = 'XAF';

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

  String get _currentMonth {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    final db = IncomeDatabase.instance;
    final secondCurrency = await db.getSecondCurrency();
    var projects = await db.getProjects();

    await _autoResetIfNewMonth(db, projects, secondCurrency);
    projects = await db.getProjects();

    setState(() {
      _secondCurrency = secondCurrency;
      _projects = projects;
      _isLoading = false;
      _totalUsd = null;
      _totalSecond = null;
      _totalsError = null;
      _projectSecondAmounts = const {};
    });
    if (projects.isNotEmpty) {
      await _computeAggregates(projects);
    }
  }

  Future<void> _autoResetIfNewMonth(
      IncomeDatabase db, List<Project> projects, String secondCurrency) async {
    final lastActive = await db.getLastActiveMonth();

    if (lastActive == null) {
      await db.setLastActiveMonth(_currentMonth);
      return;
    }

    if (lastActive == _currentMonth) return;

    final alreadySnapshotted = await db.isMonthSnapshotted(lastActive);
    if (alreadySnapshotted) {
      await db.setLastActiveMonth(_currentMonth);
      return;
    }

    if (projects.isEmpty) {
      await db.setLastActiveMonth(_currentMonth);
      return;
    }

    final now = DateTime.now().toUtc();
    final snapshots = <MonthlySnapshot>[];
    for (final p in projects) {
      final pid = p.id;
      if (pid == null) continue;
      final incomeBase = p.totalIncome;
      snapshots.add(MonthlySnapshot(
        projectId: pid,
        month: lastActive,
        name: p.name,
        hourlyRate: p.hourlyRate,
        baseCurrency: p.baseCurrency,
        totalHours: p.totalHours,
        fxAdjustmentPercent: p.fxAdjustmentPercent,
        bonus: p.bonus,
        totalIncomeBase: incomeBase,
        baseToXafRate: 0.0,
        totalIncomeXaf: 0.0,
        closedAt: now,
        isClosed: false,
        secondCurrency: secondCurrency,
      ));
    }

    await db.autoSnapshotAndReset(
      month: lastActive,
      snapshots: snapshots,
    );
    await db.setLastActiveMonth(_currentMonth);
  }

  Future<void> _computeAggregates(List<Project> projects) async {
    setState(() {
      _isLoadingTotals = true;
      _totalsError = null;
    });

    final db = IncomeDatabase.instance;

    double sumUsd = 0.0;
    double sumSecond = 0.0;
    final projectSecondAmounts = <int, double>{};
    String? error;
    final second = _secondCurrency;

    if (_exchangeClient != null) {
      try {
        for (final p in projects) {
          final id = p.id;
          if (id == null) continue;

          final base = p.baseCurrency.toUpperCase();
          final income = p.totalIncome;
          final adj = p.fxAdjustmentPercent;
          double applyAdj(double rate) => rate * (1 + adj / 100.0);

          double usdRate;
          if (base == 'USD') {
            usdRate = 1.0;
          } else {
            final cached = await db.getCachedFxRate(from: base, to: 'USD');
            final now = DateTime.now().toUtc();
            if (cached != null && now.difference(cached.asOf).inMinutes < 60) {
              usdRate = cached.rate;
            } else {
              final quote =
                  await _exchangeClient!.getRate(from: base, to: 'USD');
              await db.setCachedFxRate(
                  from: base, to: 'USD', rate: quote.rate, asOf: quote.asOf);
              usdRate = quote.rate;
            }
          }

          double secondRate;
          if (base == second) {
            secondRate = 1.0;
          } else {
            final cached = await db.getCachedFxRate(from: base, to: second);
            final now = DateTime.now().toUtc();
            if (cached != null && now.difference(cached.asOf).inMinutes < 60) {
              secondRate = applyAdj(cached.rate);
            } else {
              final quote =
                  await _exchangeClient!.getRate(from: base, to: second);
              await db.setCachedFxRate(
                  from: base, to: second, rate: quote.rate, asOf: quote.asOf);
              secondRate = applyAdj(quote.rate);
            }
          }

          final secondAmount = income * secondRate;
          sumUsd += income * usdRate;
          sumSecond += secondAmount;
          projectSecondAmounts[id] = secondAmount;
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
      _totalSecond = error == null ? sumSecond : null;
      _projectSecondAmounts = projectSecondAmounts;
      _totalsError = error;
      _isLoadingTotals = false;
    });
  }

  List<Project> get _sortedProjects {
    final list = List<Project>.from(_projects);
    list.sort((a, b) {
      final secA = (a.id != null ? _projectSecondAmounts[a.id] : null) ?? 0.0;
      final secB = (b.id != null ? _projectSecondAmounts[b.id] : null) ?? 0.0;
      return secB.compareTo(secA);
    });
    return list;
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

  String _formatHours(double totalHours) {
    final totalSeconds = (totalHours * 3600).round();
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  // ── Add project via bottom sheet ──

  Future<void> _showAddProjectSheet() async {
    final created = await showModalBottomSheet<Project>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _AddProjectSheet(),
    );
    if (created == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProjectDetailPage(projectId: created.id!),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _showAddTimeEntrySheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddTimeEntrySheet(),
    );
    if (result == true) await _load();
  }

  Future<bool> _confirmDeleteProject(Project project) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project'),
        content: Text('Delete "${project.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
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
    await _load();
  }

  Future<void> _openArchive() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ArchivePage()),
    );
  }

  // ── Widgets ──

  Widget _buildSummaryCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF2A2A2A) : Colors.black;
    const cardFg = Colors.white;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Expected Income · ${DateFormat.yMMMM().format(DateTime.now())}',
                style: TextStyle(
                  color: cardFg.withOpacity(0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
              if (_projects.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cardFg.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_projects.length} project${_projects.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: cardFg.withOpacity(0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingTotals) ...[
            const SkeletonBox(width: 180, height: 28),
            const SizedBox(height: 8),
            const SkeletonBox(width: 140, height: 18),
          ] else if (_totalsError != null)
            Text(
              _totalsError!,
              style: TextStyle(
                color: cardFg.withOpacity(0.6),
                fontSize: 13,
              ),
            )
          else ...[
            Text(
              _totalUsd != null ? _formatMoney(_totalUsd!, 'USD') : '—',
              style: const TextStyle(
                color: cardFg,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _totalSecond != null
                  ? _formatMoney(_totalSecond!, _secondCurrency)
                  : '—',
              style: TextStyle(
                color: cardFg.withOpacity(0.6),
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProjectCard(Project project) {
    final xafAmount =
        project.id != null ? _projectSecondAmounts[project.id] : null;
    final rank = _sortedProjects.indexOf(project) + 1;

    return Dismissible(
      key: ValueKey(project.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDeleteProject(project),
      onDismissed: (_) async {
        if (project.id == null) return;
        await IncomeDatabase.instance.deleteProject(project.id!);
        _load();
      },
      child: GestureDetector(
        onTap: () => _openProject(project),
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        project.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CurrencyBadge(project.baseCurrency),
                    const SizedBox(width: 8),
                    if (rank <= 3 && _sortedProjects.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#$rank',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatMoney(
                                project.totalIncome, project.baseCurrency),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (_isLoadingTotals)
                            const SkeletonBox(width: 100, height: 14)
                          else
                            Text(
                              xafAmount != null
                                  ? _formatMoney(xafAmount, _secondCurrency)
                                  : '—',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatHours(project.totalHours),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_formatMoney(project.hourlyRate, project.baseCurrency)}/h',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.3)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final muted = Theme.of(context).colorScheme.onSurface.withOpacity(0.3);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.work_outline_rounded,
              size: 56,
              color: muted,
            ),
            const SizedBox(height: 16),
            const Text(
              'No projects yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to create your first project\nand start tracking income.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedProjects;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Projects',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            onPressed: _openArchive,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildSummaryCard(),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 4, bottom: 88),
                        itemCount: sorted.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _buildProjectCard(sorted[index]),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'fab_add_project',
            onPressed: _showAddProjectSheet,
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: Theme.of(context).colorScheme.onSurface, width: 1.5),
            ),
            elevation: 0,
            child: const Icon(Icons.add, size: 20),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'fab_timer',
            onPressed: _showAddTimeEntrySheet,
            child: const Icon(Icons.timer_outlined),
          ),
        ],
      ),
    );
  }
}

// ── Bottom sheet for adding a project ──

class _AddProjectSheet extends StatefulWidget {
  const _AddProjectSheet();

  @override
  State<_AddProjectSheet> createState() => _AddProjectSheetState();
}

class _AddProjectSheetState extends State<_AddProjectSheet> {
  final _nameController = TextEditingController();
  final _rateController = TextEditingController();
  String _currency = 'USD';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final rawRate = _rateController.text.trim().replaceAll(',', '');
    final rate = double.tryParse(rawRate);

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a project name')),
      );
      return;
    }
    if (rate == null || rate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid hourly rate')),
      );
      return;
    }

    setState(() => _saving = true);
    final project = await IncomeDatabase.instance.createProject(
      name: name,
      hourlyRate: rate,
      baseCurrency: _currency,
    );
    if (!mounted) return;
    Navigator.of(context).pop<Project>(project);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'New Project',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Project name'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Hourly rate'),
          ),
          const SizedBox(height: 12),
          CurrencySelector(
            value: _currency,
            onChanged: (value) => setState(() => _currency = value),
          ),
          const SizedBox(height: 20),
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
                  : const Text('Create project'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
