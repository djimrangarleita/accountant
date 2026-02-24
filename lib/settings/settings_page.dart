import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: const SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No global settings. Bank FX adjustment is set per project in each project’s detail.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

