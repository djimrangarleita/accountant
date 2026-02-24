import 'package:flutter/material.dart';

import '../income_database.dart';
import '../project.dart';
import '../widgets/currency_selector.dart';

class AddProjectPage extends StatefulWidget {
  const AddProjectPage({super.key});

  @override
  State<AddProjectPage> createState() => _AddProjectPageState();
}

class _AddProjectPageState extends State<AddProjectPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();
  String _currency = 'USD';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Add project')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Project name',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _rateController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Hourly rate',
                ),
              ),
              const SizedBox(height: 16),
              CurrencySelector(
                value: _currency,
                onChanged: (value) => setState(() => _currency = value),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Create project'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

