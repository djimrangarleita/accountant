import 'package:flutter/material.dart';

import '../income_database.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _fxAdjustmentController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fxAdjustmentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final adj = await IncomeDatabase.instance.getFxAdjustmentPercent();
    setState(() {
      _fxAdjustmentController.text = adj.toString();
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    final rawAdj = _fxAdjustmentController.text.trim().replaceAll(',', '');
    final adj = double.tryParse(rawAdj);
    if (adj == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid adjustment')),
      );
      return;
    }
    await IncomeDatabase.instance.setFxAdjustmentPercent(adj);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bank FX adjustment (%)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _fxAdjustmentController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Adjustment in percent (e.g. -10 or 10)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _save,
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

