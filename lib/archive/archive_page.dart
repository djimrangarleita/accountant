import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_secrets.dart';
import '../exchange/exchange_rate_client.dart';
import '../exchange/open_exchange_rates_service.dart';
import '../exchange/snapshot_fx_aggregator.dart';
import '../income_database.dart';
import 'add_archive_entry_page.dart';
import 'archive_month_detail_page.dart';

class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  bool _isLoading = true;
  List<({String month, bool allPaid, bool isArchived, double totalUsd, double totalSecond, String secondCurrency, int projectCount, int paidCount})>
      _months = const [];

  String _secondCurrency = 'XAF';

  ExchangeRateClient? _exchangeClient;
  Map<String, ({double totalUsd, double totalSecond})> _liveTotals = const {};
  Set<String> _liveLoadingMonths = const {};

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
    final db = IncomeDatabase.instance;
    final secondCurrency = await db.getSecondCurrency();
    final months = await db.getArchivedMonths();
    if (!mounted) return;
    setState(() {
      _secondCurrency = secondCurrency;
      _months = months;
      _isLoading = false;
    });

    await _computeLiveTotals(months);
  }

  Future<void> _computeLiveTotals(
    List<({String month, bool allPaid, bool isArchived, double totalUsd, double totalSecond, String secondCurrency, int projectCount, int paidCount})> months,
  ) async {
    final client = _exchangeClient;
    if (client == null) return;

    final nonArchived = months.where((m) => !m.isArchived).toList();
    if (nonArchived.isEmpty) return;

    final loadingSet = nonArchived.map((m) => m.month).toSet();
    setState(() => _liveLoadingMonths = loadingSet);

    final db = IncomeDatabase.instance;
    final results = <String, ({double totalUsd, double totalSecond})>{};

    for (final entry in nonArchived) {
      try {
        final snapshots = await db.getSnapshotsForMonth(entry.month);
        final result = await computeSnapshotAggregates(
          snapshots: snapshots,
          secondCurrency: _secondCurrency,
          client: client,
          db: db,
        );
        results[entry.month] = (
          totalUsd: result.totalUsd,
          totalSecond: result.totalSecond,
        );
      } on Object {
        // On FX failure, fall back to stored values for this month.
      }
    }

    if (!mounted) return;
    setState(() {
      _liveTotals = results;
      _liveLoadingMonths = const {};
    });
  }

  String _monthLabel(String month) {
    final parts = month.split('-');
    if (parts.length != 2) return month;
    final year = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (year == null || m == null || m < 1 || m > 12) return month;
    return DateFormat.yMMMM().format(DateTime(year, m));
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

  Future<void> _openMonth(String month) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ArchiveMonthDetailPage(month: month),
      ),
    );
    await _load();
  }

  Future<void> _addEntry() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddArchiveEntryPage()),
    );
    if (result == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Archive',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _months.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 88),
                  itemCount: _months.length,
                  itemBuilder: (context, index) {
                    final entry = _months[index];
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _buildMonthTile(entry),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEntry,
        child: const Icon(Icons.add),
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
              Icons.archive_outlined,
              size: 56,
              color: muted,
            ),
            const SizedBox(height: 16),
            const Text(
              'No archived months',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to manually add an archive entry,\nor wait for a new month to begin.',
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

  Future<bool> _confirmDeleteMonth(String month) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete archived month'),
        content: Text(
          'Delete all data for ${_monthLabel(month)}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildMonthTile(
      ({String month, bool allPaid, bool isArchived, double totalUsd, double totalSecond, String secondCurrency, int projectCount, int paidCount}) entry) {
    final month = entry.month;
    final secondLabel = entry.isArchived ? entry.secondCurrency : _secondCurrency;
    final isLiveLoading = _liveLoadingMonths.contains(month);

    final double totalUsd;
    final double totalSecond;
    if (entry.isArchived) {
      totalUsd = entry.totalUsd;
      totalSecond = entry.totalSecond;
    } else {
      final live = _liveTotals[month];
      totalUsd = live?.totalUsd ?? entry.totalUsd;
      totalSecond = live?.totalSecond ?? entry.totalSecond;
    }

    final String statusLabel;
    final bool isGreen;
    if (entry.isArchived) {
      statusLabel = 'Archived · ${entry.projectCount} project${entry.projectCount == 1 ? '' : 's'}';
      isGreen = true;
    } else if (entry.allPaid) {
      statusLabel = '${entry.projectCount}/${entry.projectCount} paid';
      isGreen = false;
    } else {
      statusLabel = '${entry.paidCount}/${entry.projectCount} paid';
      isGreen = false;
    }

    final card = GestureDetector(
      onTap: () => _openMonth(month),
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
                      _monthLabel(month),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isGreen
                          ? Colors.green.shade700
                          : Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isGreen)
                          const Padding(
                            padding: EdgeInsets.only(right: 3),
                            child:
                                Icon(Icons.check, size: 10, color: Colors.white),
                          ),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color:
                                isGreen ? Colors.white : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: isLiveLoading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                totalUsd > 0
                                    ? _formatMoney(totalUsd, 'USD')
                                    : '—',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              if (totalSecond > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    _formatMoney(totalSecond, secondLabel),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey(month),
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
      confirmDismiss: (_) => _confirmDeleteMonth(month),
      onDismissed: (_) async {
        await IncomeDatabase.instance.deleteAllSnapshotsForMonth(month);
        _load();
      },
      child: card,
    );
  }
}
