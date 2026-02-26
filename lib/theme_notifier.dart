import 'package:flutter/material.dart';

import 'income_database.dart';

class ThemeNotifier extends ValueNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.system);

  Future<void> load() async {
    final stored = await IncomeDatabase.instance.getThemeMode();
    value = _parse(stored);
  }

  Future<void> setMode(ThemeMode mode) async {
    value = mode;
    await IncomeDatabase.instance.setThemeMode(_serialize(mode));
  }

  static ThemeMode _parse(String raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _serialize(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
