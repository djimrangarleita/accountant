import 'package:flutter/material.dart';

import '../income_database.dart';
import '../main.dart' show themeNotifier;
import '../widgets/currency_selector.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _secondCurrency = 'XAF';

  @override
  void initState() {
    super.initState();
    _loadSecondCurrency();
  }

  Future<void> _loadSecondCurrency() async {
    final code = await IncomeDatabase.instance.getSecondCurrency();
    if (!mounted) return;
    setState(() => _secondCurrency = code);
  }

  Future<void> _setSecondCurrency(String code) async {
    setState(() => _secondCurrency = code);
    await IncomeDatabase.instance.setSecondCurrency(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            _sectionHeader(context, 'APPEARANCE'),
            const SizedBox(height: 8),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (context, currentMode, _) {
                return Column(
                  children: [
                    _ThemeOption(
                      icon: Icons.brightness_auto,
                      label: 'System default',
                      selected: currentMode == ThemeMode.system,
                      onTap: () => themeNotifier.setMode(ThemeMode.system),
                    ),
                    _ThemeOption(
                      icon: Icons.light_mode_outlined,
                      label: 'Light',
                      selected: currentMode == ThemeMode.light,
                      onTap: () => themeNotifier.setMode(ThemeMode.light),
                    ),
                    _ThemeOption(
                      icon: Icons.dark_mode_outlined,
                      label: 'Dark',
                      selected: currentMode == ThemeMode.dark,
                      onTap: () => themeNotifier.setMode(ThemeMode.dark),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            _sectionHeader(context, 'SECOND CURRENCY'),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CurrencySelector(
                value: _secondCurrency,
                onChanged: _setSecondCurrency,
                decoration: const InputDecoration(
                  labelText: 'Second currency',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'All project incomes will be converted to this currency alongside the base currency.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Bank FX adjustment is set per project in each project\u2019s detail.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _sectionHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: colors.onSurface),
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check, color: colors.primary)
          : null,
      onTap: onTap,
    );
  }
}
