import 'package:flutter/material.dart';

import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';

class OptionItem {
  const OptionItem({required this.value, required this.label, this.raw});

  final String value;
  final String label;
  final Map<String, dynamic>? raw;
}

Future<OptionItem?> showOptionPicker(
  BuildContext context, {
  required String title,
  required List<OptionItem> options,
  String? selected,
  String emptyMessage = 'No matches',
}) async {
  return showModalBottomSheet<OptionItem>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      var query = '';
      return StatefulBuilder(
        builder: (context, setState) {
          final filtered = options
              .where((o) => o.label.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search…',
                      ),
                      onChanged: (v) => setState(() => query = v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                query.isEmpty ? emptyMessage : 'No matches',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final o = filtered[i];
                              final isSelected = o.value == selected;
                              return ListTile(
                                title: Text(o.label),
                                trailing: isSelected
                                    ? Icon(Icons.check_circle_rounded, color: AppTheme.brand)
                                    : null,
                                onTap: () => Navigator.pop(ctx, o),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<List<String>?> showMultiOptionPicker(
  BuildContext context, {
  required String title,
  required List<OptionItem> options,
  List<String> selected = const [],
  String emptyMessage = 'No matches',
}) async {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      var query = '';
      final chosen = Set<String>.from(selected);
      return StatefulBuilder(
        builder: (context, setState) {
          final filtered = options
              .where((o) => o.label.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, chosen.toList()),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search make…',
                      ),
                      onChanged: (v) => setState(() => query = v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                query.isEmpty ? emptyMessage : 'No matches',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, i) {
                              final o = filtered[i];
                              final checked = chosen.contains(o.value);
                              return CheckboxListTile(
                                value: checked,
                                title: Text(o.label),
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      chosen.add(o.value);
                                    } else {
                                      chosen.remove(o.value);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.valueLabel,
    required this.onTap,
    this.required = false,
    this.enabled = true,
    this.errorText,
    this.hint = 'Select…',
  });

  final String label;
  final String valueLabel;
  final VoidCallback onTap;
  final bool required;
  final bool enabled;
  final String? errorText;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final empty = valueLabel.isEmpty;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        isEmpty: empty,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: empty ? hint : null,
          hintStyle: const TextStyle(color: AppTheme.muted),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          errorText: errorText,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: empty
            ? const SizedBox.shrink()
            : Text(
                valueLabel,
                style: const TextStyle(color: AppTheme.primary),
              ),
      ),
    );
  }
}

List<OptionItem> mapToOptions(
  List<Map<String, dynamic>> rows, {
  String Function(Map<String, dynamic>)? labelOfRow,
}) {
  return rows.map((row) {
    final id = idOf(row) ?? '';
    final label = labelOfRow?.call(row) ?? labelOf(row);
    return OptionItem(value: id, label: label, raw: row);
  }).where((o) => o.value.isNotEmpty).toList();
}
