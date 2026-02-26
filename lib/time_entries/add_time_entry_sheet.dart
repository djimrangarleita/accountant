import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../income_database.dart';
import '../project.dart';
import '../time_entry.dart';

class AddTimeEntrySheet extends StatefulWidget {
  const AddTimeEntrySheet({
    super.key,
    this.projectId,
    this.existingEntry,
  });

  /// Pre-selected project. If null, a project dropdown is shown.
  final int? projectId;

  /// If provided, the sheet operates in edit mode.
  final TimeEntry? existingEntry;

  @override
  State<AddTimeEntrySheet> createState() => _AddTimeEntrySheetState();
}

class _AddTimeEntrySheetState extends State<AddTimeEntrySheet> {
  bool _isLoadingProjects = true;
  List<Project> _projects = const [];
  int? _selectedProjectId;

  final _hoursController = TextEditingController();
  final _minutesController = TextEditingController();
  final _secondsController = TextEditingController();
  final _noteController = TextEditingController();

  late DateTime _selectedDate;
  bool _saving = false;

  bool get _isEditing => widget.existingEntry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.existingEntry;
    if (entry != null) {
      _selectedProjectId = entry.projectId;
      final totalSeconds = (entry.hours * 3600).round();
      final h = totalSeconds ~/ 3600;
      final m = (totalSeconds % 3600) ~/ 60;
      final s = totalSeconds % 60;
      _hoursController.text = h.toString();
      _minutesController.text = m > 0 ? m.toString() : '';
      _secondsController.text = s > 0 ? s.toString() : '';
      _noteController.text = entry.note;
      _selectedDate = entry.date;
    } else {
      _selectedProjectId = widget.projectId;
      _selectedDate = DateTime.now();
    }
    if (widget.projectId == null && !_isEditing) {
      _loadProjects();
    } else {
      _isLoadingProjects = false;
    }
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    final db = IncomeDatabase.instance;
    final projects = await db.getProjects();
    final mruId = await db.getMostRecentlyUsedProjectId();
    if (!mounted) return;
    setState(() {
      _projects = projects;
      if (_selectedProjectId == null &&
          mruId != null &&
          projects.any((p) => p.id == mruId)) {
        _selectedProjectId = mruId;
      }
      _isLoadingProjects = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  double? _parseDuration() {
    final rawH = _hoursController.text.trim();
    final rawM = _minutesController.text.trim();
    final rawS = _secondsController.text.trim();

    final h = rawH.isEmpty ? 0.0 : double.tryParse(rawH);
    final m = rawM.isEmpty ? 0 : int.tryParse(rawM);
    final s = rawS.isEmpty ? 0 : int.tryParse(rawS);

    if (h == null || h < 0) return null;
    if (m == null || m < 0 || m >= 60) return null;
    if (s == null || s < 0 || s >= 60) return null;

    final total = h + m / 60.0 + s / 3600.0;
    return total > 0 ? total : null;
  }

  Future<void> _save() async {
    final projectId = _selectedProjectId;
    if (projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a project')),
      );
      return;
    }

    final hours = _parseDuration();
    if (hours == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid duration')),
      );
      return;
    }

    setState(() => _saving = true);
    final db = IncomeDatabase.instance;

    try {
      if (_isEditing) {
        await db.updateTimeEntry(widget.existingEntry!.copyWith(
          hours: hours,
          note: _noteController.text.trim(),
          date: _selectedDate,
        ));
      } else {
        await db.insertTimeEntry(TimeEntry(
          projectId: projectId,
          hours: hours,
          note: _noteController.text.trim(),
          date: _selectedDate,
          createdAt: DateTime.now().toUtc(),
        ));
      }
      await db.syncProjectTotalHours(projectId);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final showProjectPicker = widget.projectId == null && !_isEditing;

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
            _isEditing ? 'Edit Time Entry' : 'Log Time',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),

          if (showProjectPicker) ...[
            if (_isLoadingProjects)
              const Center(child: CircularProgressIndicator())
            else if (_projects.isEmpty)
              Text(
                'No projects available. Create a project first.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
              )
            else
              DropdownButtonFormField<int>(
                value: _selectedProjectId,
                decoration: const InputDecoration(labelText: 'Project'),
                items: _projects.map((p) {
                  return DropdownMenuItem(
                    value: p.id,
                    child: Text(p.name),
                  );
                }).toList(),
                onChanged: (id) => setState(() => _selectedProjectId = id),
              ),
            const SizedBox(height: 16),
          ],

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hoursController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Hours'),
                  autofocus: !showProjectPicker,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _minutesController,
                  keyboardType: const TextInputType.numberWithOptions(),
                  decoration: const InputDecoration(labelText: 'Min'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _secondsController,
                  keyboardType: const TextInputType.numberWithOptions(),
                  decoration: const InputDecoration(labelText: 'Sec'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          GestureDetector(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date',
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              child: Text(DateFormat.yMMMd().format(_selectedDate)),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _noteController,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'What did you work on?',
            ),
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
                  : Text(_isEditing ? 'Save changes' : 'Log time'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
