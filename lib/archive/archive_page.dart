import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  List<({String month, bool isClosed, double totalBase, double totalXaf})>
      _months = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final months = await IncomeDatabase.instance.getArchivedMonths();
    if (!mounted) return;
    setState(() {
      _months = months;
      _isLoading = false;
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

  Future<void> _openMonth(String month, bool isClosed) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ArchiveMonthDetailPage(
          month: month,
          isClosed: isClosed,
        ),
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
              : ListView.separated(
                  padding: const EdgeInsets.only(top: 12, bottom: 88),
                  itemCount: _months.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = _months[index];
                    return _buildMonthTile(
                      entry.month,
                      entry.isClosed,
                      entry.totalBase,
                      entry.totalXaf,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.archive_outlined,
              size: 56,
              color: Colors.grey.shade300,
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
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthTile(
      String month, bool isClosed, double totalBase, double totalXaf) {
    return InkWell(
      onTap: () => _openMonth(month, isClosed),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _monthLabel(month),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isClosed
                              ? Colors.green.shade700
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isClosed)
                              const Padding(
                                padding: EdgeInsets.only(right: 3),
                                child: Icon(Icons.check,
                                    size: 10, color: Colors.white),
                              ),
                            Text(
                              isClosed ? 'Paid' : 'Pending',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isClosed
                                    ? Colors.white
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatMoney(totalBase, 'USD'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    totalXaf > 0 ? _formatMoney(totalXaf, 'XAF') : '—',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
