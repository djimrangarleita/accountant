import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final projects = await IncomeDatabase.instance.getProjects();
    setState(() {
      _projects = projects;
      _isLoading = false;
    });
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
              : ListView.separated(
                  itemCount: _projects.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final p = _projects[index];
                    return ListTile(
                      title: Text(p.name),
                      subtitle: Text(_formatMoney(p.totalIncome, p.baseCurrency)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openProject(p),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProject,
        child: const Icon(Icons.add),
      ),
    );
  }
}

