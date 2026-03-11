import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_secrets.dart';
import '../exchange/exchange_rate_client.dart';
import '../exchange/open_exchange_rates_service.dart';
import '../income_database.dart';
import '../monthly_snapshot.dart';
import '../widgets/currency_badge.dart';
import '../widgets/skeleton_box.dart';
import 'add_archive_entry_page.dart';

class ArchiveMonthDetailPage extends StatefulWidget {
  const ArchiveMonthDetailPage({
    super.key,
    required this.month,
  });

  final String month;

  @override
  State<ArchiveMonthDetailPage> createState() => _ArchiveMonthDetailPageState();
}

class _ArchiveMonthDetailPageState extends State<ArchiveMonthDetailPage> {
  bool _isLoading = true;
  List<MonthlySnapshot> _snapshots = const [];
  bool _isMonthArchived = false;

  ExchangeRateClient? _exchangeClient;
  double? _xafToUsdRate;
  bool _isLoadingRate = false;

  bool get _allPaid =>
      _snapshots.isNotEmpty && _snapshots.every((s) => s.isClosed);

  int get _paidCount => _snapshots.where((s) => s.isClosed).length;

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
    final snapshots = await db.getSnapshotsForMonth(widget.month);
    final archived = await db.isMonthArchived(widget.month);
    if (!mounted) return;
    setState(() {
      _snapshots = snapshots;
      _isMonthArchived = archived;
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
      // Rate unavailable — show '—' for USD
    } finally {
      if (mounted) setState(() => _isLoadingRate = false);
    }
  }

  String get _monthLabel {
    final parts = widget.month.split('-');
    if (parts.length != 2) return widget.month;
    final year = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (year == null || m == null || m < 1 || m > 12) return widget.month;
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

  String _formatHours(double totalHours) {
    final totalSeconds = (totalHours * 3600).round();
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  Future<void> _markSnapshotAsPaid(MonthlySnapshot snapshot) async {
    final id = snapshot.id;
    if (id == null) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive project'),
        content: const Text(
          'Once archived, this project entry becomes immutable and can no longer be edited.\n\n'
          'Do you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final result = await showModalBottomSheet<_PayResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _FinalExchangeRateSheet(snapshot: snapshot),
    );
    if (result == null || !mounted) return;

    try {
      await IncomeDatabase.instance.closeSnapshot(
        snapshotId: id,
        baseToXafRate: result.rate,
        totalIncomeXaf: result.totalXaf,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${snapshot.name}" marked as paid')),
      );
      await _load();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  Future<void> _addEntry() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddArchiveEntryPage(prefilledMonth: widget.month),
      ),
    );
    if (result == true) await _load();
  }

  // ── Widgets ──

  Widget _buildSummaryCard() {
    double totalXaf = 0;
    for (final s in _snapshots) {
      totalXaf += s.totalIncomeXaf;
    }
    final totalUsd = (_xafToUsdRate != null && totalXaf > 0)
        ? totalXaf * _xafToUsdRate!
        : null;

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
              Expanded(
                child: Text(
                  'Expected Income · $_monthLabel',
                  style: TextStyle(
                    color: cardFg.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (_isMonthArchived)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check, size: 10, color: Colors.white),
                      const SizedBox(width: 3),
                      Text(
                        'ARCHIVED · ${_snapshots.length} project${_snapshots.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cardFg.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_paidCount/${_snapshots.length} paid',
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
          if (_isLoadingRate)
            const SkeletonBox(width: 200, height: 32)
          else
            Text(
              totalUsd != null ? _formatMoney(totalUsd, 'USD') : '—',
              style: const TextStyle(
                color: cardFg,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            totalXaf > 0 ? _formatMoney(totalXaf, 'XAF') : '—',
            style: TextStyle(
              color: cardFg.withOpacity(0.6),
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editEntry(MonthlySnapshot snapshot) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddArchiveEntryPage(
          prefilledMonth: widget.month,
          existingSnapshot: snapshot,
        ),
      ),
    );
    if (result == true) await _load();
  }

  Future<void> _deleteEntry(MonthlySnapshot snapshot) async {
    final id = snapshot.id;
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry'),
        content: Text('Remove "${snapshot.name}" from this month?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await IncomeDatabase.instance.deleteSnapshot(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${snapshot.name}" removed')),
    );
    await _load();
  }

  Widget _buildSnapshotCard(MonthlySnapshot snapshot) {
    final isPaid = snapshot.isClosed;

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: isPaid ? null : () => _editEntry(snapshot),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      snapshot.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CurrencyBadge(snapshot.baseCurrency),
                  const SizedBox(width: 6),
                  if (isPaid)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check, size: 10, color: Colors.white),
                          SizedBox(width: 3),
                          Text(
                            'Paid',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () => _markSnapshotAsPaid(snapshot),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.payment,
                                size: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6)),
                            const SizedBox(width: 3),
                            Text(
                              'Mark Paid',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6),
                              ),
                            ),
                          ],
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
                              snapshot.totalIncomeBase, snapshot.baseCurrency),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          snapshot.totalIncomeXaf > 0
                              ? _formatMoney(snapshot.totalIncomeXaf, 'XAF')
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
                        _formatHours(snapshot.totalHours),
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
                        '${_formatMoney(snapshot.hourlyRate, snapshot.baseCurrency)}/h',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.4),
                        ),
                      ),
                      if (snapshot.bonus > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '+${_formatMoney(snapshot.bonus, snapshot.baseCurrency)} bonus',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (!isPaid) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        size: 18,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.3)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (isPaid) return card;

    return Dismissible(
      key: ValueKey(snapshot.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete entry'),
            content: Text('Remove "${snapshot.name}" from this month?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        final id = snapshot.id;
        if (id == null) return;
        await IncomeDatabase.instance.deleteSnapshot(id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${snapshot.name}" removed')),
        );
        await _load();
      },
      child: card,
    );
  }

  Future<void> _archiveMonth() async {
    await IncomeDatabase.instance.setMonthArchived(widget.month);
    if (!mounted) return;
    setState(() => _isMonthArchived = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$_monthLabel archived')),
    );
  }

  Widget _buildStatusSection() {
    if (_isMonthArchived) return const SizedBox.shrink();

    if (_allPaid) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              side: BorderSide(color: Theme.of(context).colorScheme.onSurface),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _archiveMonth,
            child: Text('Archive $_monthLabel'),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _monthLabel,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (!_allPaid && !_isMonthArchived)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addEntry,
              tooltip: 'Add entry',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSummaryCard(),
                _buildStatusSection(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 24),
                    itemCount: _snapshots.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _buildSnapshotCard(_snapshots[index]),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _PayResult {
  const _PayResult({required this.rate, required this.totalXaf});
  final double rate;
  final double totalXaf;
}

class _FinalExchangeRateSheet extends StatefulWidget {
  const _FinalExchangeRateSheet({required this.snapshot});

  final MonthlySnapshot snapshot;

  @override
  State<_FinalExchangeRateSheet> createState() =>
      _FinalExchangeRateSheetState();
}

class _FinalExchangeRateSheetState extends State<_FinalExchangeRateSheet> {
  late final TextEditingController _rateController;

  @override
  void initState() {
    super.initState();
    _rateController = TextEditingController(
      text: widget.snapshot.baseToXafRate > 0
          ? widget.snapshot.baseToXafRate.toString()
          : '',
    );
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  double get _rate =>
      double.tryParse(_rateController.text.trim().replaceAll(',', '')) ?? 0;

  double get _totalXaf => widget.snapshot.totalIncomeBase * _rate;

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

  void _confirm() {
    if (_rate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid exchange rate')),
      );
      return;
    }
    Navigator.of(context).pop(_PayResult(rate: _rate, totalXaf: _totalXaf));
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.snapshot;
    final base = snap.baseCurrency.toUpperCase();
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
          Text(
            'Mark "${snap.name}" as Paid',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter the final exchange rate to calculate the revenue in XAF.',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Income in $base',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatMoney(snap.totalIncomeBase, base),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _rateController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: InputDecoration(
              labelText: '1 $base = ? XAF',
              hintText: 'Final exchange rate',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Revenue in XAF',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _rate > 0 ? _formatMoney(_totalXaf, 'XAF') : '—',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _rate > 0 ? _confirm : null,
              child: const Text('Confirm & Mark as Paid'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
