import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../income_database.dart';
import '../monthly_snapshot.dart';
import '../widgets/currency_badge.dart';
import 'add_archive_entry_page.dart';

class ArchiveMonthDetailPage extends StatefulWidget {
  const ArchiveMonthDetailPage({
    super.key,
    required this.month,
    required this.isClosed,
  });

  final String month;
  final bool isClosed;

  @override
  State<ArchiveMonthDetailPage> createState() =>
      _ArchiveMonthDetailPageState();
}

class _ArchiveMonthDetailPageState extends State<ArchiveMonthDetailPage> {
  bool _isLoading = true;
  bool _isClosed = false;
  bool _isClosing = false;
  List<MonthlySnapshot> _snapshots = const [];

  @override
  void initState() {
    super.initState();
    _isClosed = widget.isClosed;
    _load();
  }

  Future<void> _load() async {
    final snapshots =
        await IncomeDatabase.instance.getSnapshotsForMonth(widget.month);
    if (!mounted) return;
    setState(() {
      _snapshots = snapshots;
      _isLoading = false;
      if (snapshots.isNotEmpty) {
        _isClosed = snapshots.first.isClosed;
      }
    });
  }

  String get _currentMonth {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  String get _monthLabel {
    final parts = widget.month.split('-');
    if (parts.length != 2) return widget.month;
    final year = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (year == null || m == null || m < 1 || m > 12) return widget.month;
    return DateFormat.yMMMM().format(DateTime(year, m));
  }

  bool get _canClose => !_isClosed && widget.month.compareTo(_currentMonth) < 0;

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

  Future<void> _approveAndPay() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve & Pay'),
        content: Text(
          'Mark $_monthLabel as approved and paid?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black,
              side: const BorderSide(color: Colors.black),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Approve & Pay'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isClosing = true);

    try {
      await IncomeDatabase.instance.closeMonth(widget.month);
      if (!mounted) return;
      setState(() => _isClosed = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_monthLabel approved & paid')),
      );
      await _load();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isClosing = false);
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
    double totalBase = 0;
    double totalXaf = 0;
    for (final s in _snapshots) {
      totalBase += s.totalIncomeBase;
      totalXaf += s.totalIncomeXaf;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black,
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
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (_isClosed)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 10, color: Colors.white),
                      SizedBox(width: 3),
                      Text(
                        'PAID',
                        style: TextStyle(
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
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_snapshots.length} project${_snapshots.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _formatMoney(totalBase, 'USD'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatMoney(totalXaf, 'XAF'),
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
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
    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: _isClosed ? null : () => _editEntry(snapshot),
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
                  if (!_isClosed) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        size: 18, color: Colors.grey.shade400),
                  ],
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
                            color: Colors.grey.shade600,
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
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_formatMoney(snapshot.hourlyRate, snapshot.baseCurrency)}/h',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      if (snapshot.bonus > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '+${_formatMoney(snapshot.bonus, snapshot.baseCurrency)} bonus',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (_isClosed) return card;

    return Dismissible(
      key: ValueKey(snapshot.id),
      direction: DismissDirection.endToStart,
      child: card,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: Colors.red.shade700),
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
    );
  }

  Widget _buildStatusSection() {
    if (_isClosed) {
      final closedAt = _snapshots.isNotEmpty ? _snapshots.first.closedAt : null;
      final dateLabel = closedAt != null
          ? DateFormat.yMMMd().add_jm().format(closedAt.toLocal())
          : '';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
            const SizedBox(width: 6),
            Text(
              'Paid${dateLabel.isNotEmpty ? ' on $dateLabel' : ''}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.green.shade600,
              ),
            ),
          ],
        ),
      );
    }

    if (!_canClose) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black,
            side: const BorderSide(color: Colors.black),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _isClosing ? null : _approveAndPay,
          child: _isClosing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : Text('Approve & Pay $_monthLabel'),
        ),
      ),
    );
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
          if (!_isClosed)
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
