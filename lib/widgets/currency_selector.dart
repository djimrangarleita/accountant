import 'package:flutter/material.dart';

import 'package:accountant_app/currencies.dart';

class CurrencySelector extends StatelessWidget {
  const CurrencySelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.decoration,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final InputDecoration? decoration;

  String get _safeValue {
    final v = value.trim().toUpperCase();
    return v.isEmpty ? 'USD' : v;
  }

  static String _displayLabel(String code) {
    final c = code.toUpperCase();
    for (final e in kAllCurrencies) {
      if (e.code == c) return '${e.code} – ${e.name}';
    }
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final safeValue = _safeValue;
    return InkWell(
      onTap: () => _openPicker(context, safeValue),
      child: InputDecorator(
        decoration: decoration ?? InputDecoration(
          labelText: 'Base currency',
          border: const OutlineInputBorder(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _displayLabel(safeValue),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context, String initialValue) async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => _CurrencyPickerPage(initialValue: initialValue),
      ),
    );
    if (selected != null) {
      onChanged(selected);
    }
  }
}

class _CurrencyPickerPage extends StatefulWidget {
  const _CurrencyPickerPage({required this.initialValue});

  final String initialValue;

  @override
  State<_CurrencyPickerPage> createState() => _CurrencyPickerPageState();
}

class _CurrencyPickerPageState extends State<_CurrencyPickerPage> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<({String code, String name})> get _filtered {
    if (_query.isEmpty) return kAllCurrencies;
    return kAllCurrencies.where((c) {
      return c.code.toLowerCase().contains(_query) ||
          c.name.toLowerCase().contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select currency'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search by code or name…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No currency found'))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final c = filtered[index];
                      final isSelected =
                          c.code.toUpperCase() == widget.initialValue.toUpperCase();
                      return ListTile(
                        title: Text(c.code),
                        subtitle: Text(c.name),
                        selected: isSelected,
                        trailing: isSelected
                            ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                            : null,
                        onTap: () => Navigator.of(context).pop(c.code),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
