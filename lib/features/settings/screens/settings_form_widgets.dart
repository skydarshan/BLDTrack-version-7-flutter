import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../pms/widgets/pickers.dart';

Map<String, String> emptyAddress() => {
      'street_address': '',
      'street_address2': '',
      'city': '',
      'state': '',
      'zip_code': '',
      'country': '',
    };

Map<String, String> addressFrom(dynamic raw) {
  final base = emptyAddress();
  if (raw is! Map) return base;
  for (final key in base.keys) {
    base[key] = raw[key]?.toString() ?? '';
  }
  return base;
}

/// Nested address text fields (street / city / state / zip / country).
class AddressFields extends StatelessWidget {
  const AddressFields({
    super.key,
    required this.values,
    required this.onChanged,
  });

  final Map<String, String> values;
  final void Function(String key, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    Widget field(String key, String label, {int maxLines = 1}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          initialValue: values[key] ?? '',
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label),
          onChanged: (v) => onChanged(key, v),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8, top: 4),
          child: Text(
            'Address',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        field('street_address', 'Street'),
        field('street_address2', 'Street 2'),
        field('city', 'City'),
        field('state', 'State'),
        field('zip_code', 'ZIP'),
        field('country', 'Country'),
      ],
    );
  }
}

/// Multi-select chips backed by [OptionItem] list.
class MultiSelectField extends StatelessWidget {
  const MultiSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.selectedIds,
    required this.onChanged,
    this.required = false,
  });

  final String label;
  final List<OptionItem> options;
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;
  final bool required;

  Future<void> _open(BuildContext context) async {
    final selected = Set<String>.from(selectedIds);
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setLocal) {
            final filtered = options
                .where(
                  (o) => o.label.toLowerCase().contains(query.toLowerCase()),
                )
                .toList();
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, selected.toList()),
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
                          hintText: 'Search…',
                        ),
                        onChanged: (v) => setLocal(() => query = v),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final o = filtered[i];
                          final checked = selected.contains(o.value);
                          return CheckboxListTile(
                            value: checked,
                            title: Text(o.label),
                            onChanged: (v) {
                              setLocal(() {
                                if (v == true) {
                                  selected.add(o.value);
                                } else {
                                  selected.remove(o.value);
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
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final labels = <String>[];
    for (final id in selectedIds) {
      final match = options.where((o) => o.value == id);
      labels.add(match.isEmpty ? id : match.first.label);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PickerField(
          label: label,
          required: required,
          valueLabel: labels.isEmpty ? '' : '${labels.length} selected',
          onTap: () => _open(context),
        ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < selectedIds.length; i++)
                InputChip(
                  label: Text(labels[i]),
                  onDeleted: () {
                    final next = List<String>.from(selectedIds)..removeAt(i);
                    onChanged(next);
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

List<String> idsFromRefs(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .map((e) {
        if (e is Map) return (e['_id'] ?? e['id'])?.toString();
        return e?.toString();
      })
      .whereType<String>()
      .where((e) => e.isNotEmpty)
      .toList();
}

String refId(dynamic raw) {
  if (raw == null) return '';
  if (raw is Map) return (raw['_id'] ?? raw['id'])?.toString() ?? '';
  return raw.toString();
}

String formatModuleLabel(String module) {
  return module
      .split(RegExp(r'[-_]'))
      .where((p) => p.isNotEmpty)
      .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}

Widget settingsPaginationRow({
  required int page,
  required int totalPages,
  required VoidCallback? onPrev,
  required VoidCallback? onNext,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(onPressed: onPrev, child: const Text('Prev')),
        Text('$page / $totalPages', style: const TextStyle(color: AppTheme.muted)),
        TextButton(onPressed: onNext, child: const Text('Next')),
      ],
    ),
  );
}
