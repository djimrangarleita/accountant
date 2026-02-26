import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../income_database.dart';
import '../time_entry.dart';
import 'add_time_entry_sheet.dart';

class HourLogsPage extends StatefulWidget {
  const HourLogsPage({super.key, required this.projectId});

  final int projectId;

  @override
  State<HourLogsPage> createState() => _HourLogsPageState();
}

class _HourLogsPageState extends State<HourLogsPage> {
  List<TimeEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await IncomeDatabase.instance
        .getTimeEntriesForProject(widget.projectId);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _addEntry() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddTimeEntrySheet(projectId: widget.projectId),
    );
    if (result == true) _load();
  }

  Future<void> _editEntry(TimeEntry entry) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddTimeEntrySheet(
        projectId: widget.projectId,
        existingEntry: entry,
      ),
    );
    if (result == true) _load();
  }

  Future<void> _deleteEntry(TimeEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          'Remove ${_formatDuration(entry.hours)} on '
          '${DateFormat.yMMMd().format(entry.date)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await IncomeDatabase.instance.deleteTimeEntry(entry.id!);
      await IncomeDatabase.instance.syncProjectTotalHours(widget.projectId);
      _load();
    }
  }

  String _formatCreatedAt(DateTime dt) {
    final local = dt.toLocal();
    final dayOfWeek = DateFormat.E().format(local);
    final day = local.day;
    final time = DateFormat('h:mm a').format(local).toLowerCase();
    return '$dayOfWeek $day, $time';
  }

  String _formatDuration(double hours) {
    final totalSeconds = (hours * 3600).round();
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    final buf = StringBuffer();
    buf.write('${h}h');
    if (m > 0 || s > 0) buf.write(' ${m}m');
    if (s > 0) buf.write(' ${s}s');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hour Logs')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEntry,
        child: const Icon(Icons.timer_outlined),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmptyState()
              : _buildList(),
    );
  }

  Widget _buildEmptyState() {
    final muted = Theme.of(context).colorScheme.onSurface.withOpacity(0.4);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_off_outlined, size: 48, color: muted),
          const SizedBox(height: 12),
          Text(
            'No time entries yet',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the timer button to log your first entry',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final grouped = <String, List<TimeEntry>>{};
    for (final e in _entries) {
      final key = DateFormat.yMMMd().format(e.date);
      (grouped[key] ??= []).add(e);
    }

    final dateKeys = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: dateKeys.length,
      itemBuilder: (_, i) {
        final dateLabel = dateKeys[i];
        final entries = grouped[dateLabel]!;
        final dayTotal = entries.fold<double>(0, (s, e) => s + e.hours);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (i > 0) const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  dateLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDuration(dayTotal),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...entries.map((entry) => _buildEntryCard(entry)),
          ],
        );
      },
    );
  }

  Widget _buildEntryCard(TimeEntry entry) {
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red.shade400,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async => _confirmDismiss(entry),
      onDismissed: (_) {
        IncomeDatabase.instance.deleteTimeEntry(entry.id!);
        IncomeDatabase.instance.syncProjectTotalHours(widget.projectId);
        _load();
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _editEntry(entry),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatDuration(entry.hours),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.note.isNotEmpty ? entry.note : '—',
                    style: TextStyle(
                      color: entry.note.isNotEmpty
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatCreatedAt(entry.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDismiss(TimeEntry entry) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          'Remove ${_formatDuration(entry.hours)} on '
          '${DateFormat.yMMMd().format(entry.date)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
