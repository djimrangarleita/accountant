import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_secrets.dart';
import '../exchange/exchange_rate_client.dart';
import '../exchange/open_exchange_rates_service.dart';
import '../income_database.dart';
import '../widgets/skeleton_box.dart';
import 'add_archive_entry_page.dart';
import 'archive_month_detail_page.dart';

class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  bool _isLoading = true;
  List<({String month, bool allPaid, bool isArchived, double totalXaf, int projectCount, int paidCount})>
      _months = const [];

  ExchangeRateClient? _exchangeClient;
  double? _xafToUsdRate;
  bool _isLoadingRate = false;

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
    final months = await IncomeDatabase.instance.getArchivedMonths();
    if (!mounted) return;
    setState(() {
      _months = months;
      _isLoading = false;
    });
    _fetchXafToUsdRate();
  }

  Future<void> _fetchXafToUsdRate() async {
    if (_exchangeClient == null) return;
    setState(() => _isLoadingRate = true);
    try {
      final db = IncomeDatabase.instance;
      final cached = await db.getCachedFxRate(from: 'XAF', to: 'USD');
      final now = DateTime.now().toUtc();
      double rate;
      if (cached != null && now.difference(cached.asOf).inMinutes < 60) {
        rate = cached.rate;
      } else {
        final quote = await _exchangeClient!.getRate(from: 'XAF', to: 'USD');
        await db.setCachedFxRate(
            from: 'XAF', to: 'USD', rate: quote.rate, asOf: quote.asOf);
        rate = quote.rate;
      }
      if (!mounted) return;
      setState(() => _xafToUsdRate = rate);
    } on Object catch (_) {
      // Rate unavailable — tiles will show '—' for USD
    } finally {
      if (mounted) setState(() => _isLoadingRate = false);
    }
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
      ({String month, bool allPaid, bool isArchived, double totalXaf, int projectCount, int paidCount}) entry) {
    final month = entry.month;
    final totalXaf = entry.totalXaf;
    final totalUsd =
        (_xafToUsdRate != null && totalXaf > 0) ? totalXaf * _xafToUsdRate! : null;

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
              // Bottom row: income on left, chevron on right
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isLoadingRate)
                          const SkeletonBox(width: 160, height: 22)
                        else
                          Text(
                            totalUsd != null
                                ? _formatMoney(totalUsd, 'USD')
                                : '—',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          totalXaf > 0 ? _formatMoney(totalXaf, 'XAF') : '—',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
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
