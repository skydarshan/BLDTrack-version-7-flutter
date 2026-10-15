import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';

class OptionItem {
  const OptionItem({required this.value, required this.label, this.raw});

  final String value;
  final String label;
  final Map<String, dynamic>? raw;
}

bool _optionMatches(OptionItem option, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (option.label.toLowerCase().contains(q)) return true;
  final raw = option.raw;
  if (raw == null) return false;
  for (final key in ['site_name', 'name', 'code', 'location', 'vendor_name', 'item_name']) {
    final text = raw[key]?.toString().toLowerCase() ?? '';
    if (text.contains(q)) return true;
  }
  return false;
}

Future<OptionItem?> showOptionPicker(
  BuildContext context, {
  required String title,
  required List<OptionItem> options,
  String? selected,
  String emptyMessage = 'No matches',
}) async {
  final topInset = MediaQuery.viewPaddingOf(context).top;
  return showModalBottomSheet<OptionItem>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      var query = '';
      return StatefulBuilder(
        builder: (context, setState) {
          final filtered = options.where((o) => _optionMatches(o, query)).toList();
          return FittedListSheet(
            title: title,
            topInset: topInset,
            onClose: () => Navigator.pop(ctx),
            search: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search…',
              ),
              onChanged: (v) => setState(() => query = v),
            ),
            emptyMessage: query.isEmpty ? emptyMessage : 'No matches',
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
  final topInset = MediaQuery.viewPaddingOf(context).top;
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      var query = '';
      final chosen = Set<String>.from(selected);
      return StatefulBuilder(
        builder: (context, setState) {
          final filtered = options.where((o) => _optionMatches(o, query)).toList();
          return FittedListSheet(
            title: title,
            topInset: topInset,
            headerTrailing: TextButton(
              onPressed: () => Navigator.pop(ctx, chosen.toList()),
              child: const Text('Done'),
            ),
            search: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search make…',
              ),
              onChanged: (v) => setState(() => query = v),
            ),
            emptyMessage: query.isEmpty ? emptyMessage : 'No matches',
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
          );
        },
      );
    },
  );
}

/// Filter and dropdown sheet that hugs its list. A short list does not leave
/// an empty band underneath. A list taller than the sheet scrolls, with the
/// scrollbar on the right.
class FittedListSheet extends StatelessWidget {
  const FittedListSheet({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.search,
    this.headerTrailing,
    this.onClose,
    this.emptyMessage = 'No matches',
    this.topInset = 0,
  });

  final String title;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget? search;
  final Widget? headerTrailing;
  final VoidCallback? onClose;
  final String emptyMessage;

  /// Status-bar / camera inset captured before the sheet route clears it.
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final available = media.size.height - media.viewInsets.bottom;
    final belowStatusBar = available - topInset - 8;
    final seventyFive = available * 0.75;
    final cap = seventyFive < belowStatusBar ? seventyFive : belowStatusBar;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: _FittedSheetBox(
        maxHeight: cap < 120 ? 120 : cap,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                ?headerTrailing,
                if (onClose != null)
                  IconButton(
                    tooltip: 'Close',
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
          if (search != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: search,
            ),
          if (itemCount == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(emptyMessage, textAlign: TextAlign.center),
            )
          else
            _SheetOptionList(
              itemCount: itemCount,
              itemBuilder: itemBuilder,
            ),
        ],
      ),
    );
  }
}

/// Sizes the sheet to its header plus the list. The list is not stretched,
/// so nothing is left blank under the last row. Past [maxHeight] it scrolls.
class _FittedSheetBox extends MultiChildRenderObjectWidget {
  const _FittedSheetBox({
    required this.maxHeight,
    required super.children,
  });

  final double maxHeight;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFittedSheetBox(maxHeight);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderFittedSheetBox renderObject) {
    renderObject.maxHeight = maxHeight;
  }
}

class _FittedSheetParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderFittedSheetBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FittedSheetParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FittedSheetParentData> {
  _RenderFittedSheetBox(this._maxHeight);

  double _maxHeight;

  double get maxHeight => _maxHeight;

  set maxHeight(double value) {
    if (_maxHeight == value) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FittedSheetParentData) {
      child.parentData = _FittedSheetParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final limit = constraints.maxHeight < _maxHeight ? constraints.maxHeight : _maxHeight;
    final kids = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      kids.add(child);
      child = childAfter(child);
    }
    if (kids.isEmpty || width <= 0) {
      size = constraints.constrain(Size(width, 0));
      return;
    }

    final body = kids.removeLast();
    var used = 0.0;
    for (final part in kids) {
      part.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      used += part.size.height;
    }

    final room = (limit - used) < 0 ? 0.0 : limit - used;
    // Keep the list height finite. An unbounded pass makes a shrink-wrapped
    // list build every row, which freezes the item catalog picker.
    body.layout(
      BoxConstraints(minWidth: width, maxWidth: width, maxHeight: room),
      parentUsesSize: true,
    );
    final bodyHeight = body.size.height;

    var y = 0.0;
    for (final part in kids) {
      (part.parentData! as _FittedSheetParentData).offset = Offset(0, y);
      y += part.size.height;
    }
    (body.parentData! as _FittedSheetParentData).offset = Offset(0, y);
    size = constraints.constrain(Size(width, y + bodyHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

class _SheetOptionList extends StatefulWidget {
  const _SheetOptionList({
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<_SheetOptionList> createState() => _SheetOptionListState();
}

class _SheetOptionListState extends State<_SheetOptionList> {
  final ScrollController _controller = ScrollController();
  bool _overflows = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncOverflow);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
  }

  @override
  void didUpdateWidget(covariant _SheetOptionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
    }
  }

  void _syncOverflow() {
    if (!mounted || !_controller.hasClients) return;
    final next = _controller.position.maxScrollExtent > 1;
    if (next != _overflows) setState(() => _overflows = next);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncOverflow);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Short menus hug their rows. Long catalogs must not shrink-wrap, or the
    // sheet lays out every row and the app stops responding.
    final hug = widget.itemCount <= 24;
    return Scrollbar(
      controller: _controller,
      thumbVisibility: _overflows,
      child: ListView.builder(
        controller: _controller,
        shrinkWrap: hug,
        primary: false,
        padding: EdgeInsets.zero,
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      ),
    );
  }
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

/// Form dropdown whose menu ends at the last item. A longer menu scrolls
/// and shows a scrollbar on the right instead of stretching the panel.
class AppDropdownFormField<T> extends StatelessWidget {
  const AppDropdownFormField({
    super.key,
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.decoration = const InputDecoration(),
  });

  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final T? initialValue;
  final InputDecoration decoration;

  String _textOf(Widget child) {
    if (child is Text) {
      return child.data ?? child.textSpan?.toPlainText() ?? '';
    }
    return '';
  }

  Future<void> _open(BuildContext context) async {
    final label = (decoration.labelText ?? 'Select').replaceAll('*', '').trim();
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final picked = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FittedListSheet(
        title: label.isEmpty ? 'Select' : label,
        topInset: topInset,
        onClose: () => Navigator.pop(ctx),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          final selected = item.value == initialValue;
          return ListTile(
            enabled: item.enabled,
            title: Text(_textOf(item.child)),
            trailing: selected
                ? Icon(Icons.check_circle_rounded, color: AppTheme.brand)
                : null,
            onTap: item.enabled ? () => Navigator.pop(ctx, item.value) : null,
          );
        },
      ),
    );
    if (picked != null) onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final match = items.where((item) => item.value == initialValue);
    final valueLabel = match.isEmpty ? '' : _textOf(match.first.child);
    final enabled = onChanged != null;
    return InkWell(
      onTap: enabled ? () => _open(context) : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        isEmpty: valueLabel.isEmpty,
        decoration: decoration.copyWith(
          suffixIcon: Icon(
            Icons.arrow_drop_down,
            color: enabled ? null : AppTheme.muted,
          ),
        ),
        child: valueLabel.isEmpty
            ? const SizedBox.shrink()
            : Text(
                valueLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: enabled ? AppTheme.primary : AppTheme.muted),
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
