import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/list_query.dart';
import '../../app/app_services.dart';
import '../../pms/widgets/pickers.dart';
import '../../pms/widgets/pms_widgets.dart';

enum DmrEditKind { order, entry, imprest }

class DmrRecordEditScreen extends StatefulWidget {
  const DmrRecordEditScreen({super.key, required this.id, required this.kind});

  final String id;
  final DmrEditKind kind;

  @override
  State<DmrRecordEditScreen> createState() => _DmrRecordEditScreenState();
}

class _QtyLine {
  _QtyLine({required this.source});

  final Map<String, dynamic> source;
  final qty = TextEditingController();
  final remark = TextEditingController();
  final amount = TextEditingController();

  void seed(String qtyText, String remarkText, String amountText) {
    qty.text = qtyText;
    remark.text = remarkText;
    amount.text = amountText;
  }

  void dispose() {
    qty.dispose();
    remark.dispose();
    amount.dispose();
  }
}

class _DmrRecordEditScreenState extends State<DmrRecordEditScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _doc;
  String _status = '';
  DateTime? _date;
  final _remarks = TextEditingController();
  final _gate = TextEditingController();
  final _vehicle = TextEditingController();
  final _mode = TextEditingController();
  final _invoice = TextEditingController();
  final _challan = TextEditingController();
  final _vendorName = TextEditingController();
  final List<_QtyLine> _lines = [];

  String get _title => switch (widget.kind) {
        DmrEditKind.order => 'Edit DMR order',
        DmrEditKind.entry => 'Edit DMR entry',
        DmrEditKind.imprest => 'Edit cash purchase',
      };

  List<OptionItem> get _statuses => switch (widget.kind) {
        DmrEditKind.order => const [
            OptionItem(value: 'pending', label: 'Pending'),
            OptionItem(value: 'partial', label: 'Partial Delivered'),
            OptionItem(value: 'completed', label: 'Closed'),
            OptionItem(value: 'hold', label: 'Closure Pending'),
          ],
        DmrEditKind.entry || DmrEditKind.imprest => const [
            OptionItem(value: 'open', label: 'Open'),
            OptionItem(value: 'completed', label: 'Completed'),
          ],
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _remarks.dispose();
    _gate.dispose();
    _vehicle.dispose();
    _mode.dispose();
    _invoice.dispose();
    _challan.dispose();
    _vendorName.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String _plain(dynamic value) {
    if (value is Map) {
      final named = labelOf(value, fallback: '');
      return named == '—' ? '' : named;
    }
    final text = _text(value);
    if (text.isEmpty || looksLikeObjectId(text)) return '';
    return text;
  }

  String _qtyKey() => switch (widget.kind) {
        DmrEditKind.order => 'po_qty',
        DmrEditKind.entry => 'received_qty',
        DmrEditKind.imprest => 'qty',
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dmr = context.read<AppServices>().dmr;
      final doc = switch (widget.kind) {
        DmrEditKind.order => await dmr.getOrder(widget.id),
        DmrEditKind.entry => await dmr.getEntry(widget.id),
        DmrEditKind.imprest => await dmr.getImprest(widget.id),
      };
      if (!mounted) return;
      for (final line in _lines) {
        line.dispose();
      }
      _lines.clear();
      final qtyKey = _qtyKey();
      for (final raw in lineItemsOf(doc)) {
        final line = _QtyLine(source: raw);
        final qty = asNum(raw[qtyKey]) ?? asNum(raw['qty']) ?? asNum(raw['po_qty']);
        line.seed(
          qty == null ? '' : _trimNum(qty),
          _text(raw['remark']),
          asNum(raw['amount']) == null ? '' : _trimNum(asNum(raw['amount'])!),
        );
        _lines.add(line);
      }
      _remarks.text = _text(doc['remarks']);
      _gate.text = _text(doc['gate_register_entry']);
      _vehicle.text = _text(doc['vehicle_number']);
      _mode.text = _text(doc['mode']);
      _invoice.text = _text(doc['invoice_number']);
      _challan.text = _text(doc['challan_number']);
      _vendorName.text = vendorNamesOf(doc);
      _status = _text(doc['status']);
      if (_statuses.every((option) => option.value != _status)) {
        _status = _statuses.first.value;
      }
      _date = DateTime.tryParse(_text(doc['date']).isEmpty ? _text(doc['invoice_date']) : _text(doc['date']));
      setState(() {
        _doc = doc;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  String _trimNum(num value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  String? _objectId(dynamic value) {
    final id = idOf(value);
    return looksLikeObjectId(id) ? id : null;
  }

  void _copyNum(Map<String, dynamic> target, Map<String, dynamic> source, String key) {
    final value = asNum(source[key]);
    if (value != null) target[key] = value;
  }

  Map<String, dynamic> _orderOrEntryItem(_QtyLine line, num qty) {
    final source = line.source;
    final item = <String, dynamic>{
      'item_name': () {
        final named = itemLabel(source, fallback: '');
        return named == '—' ? '' : named;
      }(),
      'hsn_code': _text(source['hsn_code']),
      'uom': _plain(source['uom']),
      'remark': line.remark.text.trim(),
    };
    final itemId = _objectId(source['item_id']);
    final uomId = _objectId(source['uom_id']);
    if (itemId != null) item['item_id'] = itemId;
    if (uomId != null) item['uom_id'] = uomId;
    for (final key in [
      'po_qty',
      'received_qty',
      'accepted_qty',
      'rejected_qty',
      'rate',
      'amount',
      'gst',
      if (widget.kind == DmrEditKind.entry) ...['gst_amount', 'total_amount'],
      if (widget.kind == DmrEditKind.order) ...['invoice_qty', 'exceeded_qty'],
    ]) {
      _copyNum(item, source, key);
    }
    item[_qtyKey()] = qty;
    return item;
  }

  Map<String, dynamic> _imprestItem(_QtyLine line, num qty, num amount) {
    final source = line.source;
    final item = <String, dynamic>{
      'uom': _plain(source['uom']),
      'qty': qty,
      'amount': amount,
      'remark': line.remark.text.trim(),
    };
    final categoryId = _objectId(source['category_id']);
    final subId = _objectId(source['sub_category_id']);
    if (categoryId != null) item['category_id'] = categoryId;
    if (subId != null) item['sub_category_id'] = subId;
    return item;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _save() async {
    final doc = _doc;
    if (doc == null) return;
    final items = <Map<String, dynamic>>[];
    num total = 0;
    for (final line in _lines) {
      final qty = num.tryParse(line.qty.text.trim());
      if (qty == null || qty < 0) {
        showPmsSnack(context, 'Enter a valid quantity for ${itemLabel(line.source)}', error: true);
        return;
      }
      if (widget.kind == DmrEditKind.imprest) {
        final amount = num.tryParse(line.amount.text.trim()) ?? 0;
        if (amount < 0) {
          showPmsSnack(context, 'Enter a valid amount for ${itemLabel(line.source)}', error: true);
          return;
        }
        total += amount;
        items.add(_imprestItem(line, qty, amount));
      } else {
        items.add(_orderOrEntryItem(line, qty));
      }
    }

    final payload = <String, dynamic>{
      'status': _status,
      'remarks': _remarks.text.trim(),
    };
    if (widget.kind == DmrEditKind.order) {
      payload['items'] = items;
    } else {
      payload['dmr_items'] = items;
      payload['gate_register_entry'] = _gate.text.trim();
      payload['vehicle_number'] = _vehicle.text.trim();
      payload['mode'] = _mode.text.trim();
      payload['invoice_number'] = _invoice.text.trim();
      if (widget.kind == DmrEditKind.entry) {
        payload['challan_number'] = _challan.text.trim();
      }
    }
    if (widget.kind == DmrEditKind.imprest) {
      payload['vendor_name'] = _vendorName.text.trim();
      final vendorId = _objectId(doc['vendor_id']);
      if (vendorId != null) payload['vendor_id'] = vendorId;
      final when = isoDateOnly(_date);
      if (when != null) payload['date'] = when;
      payload['total_amount'] = total;
      final docUrl = _text(doc['invoice_or_challan_doc']);
      if (docUrl.isNotEmpty) payload['invoice_or_challan_doc'] = docUrl;
    }

    setState(() => _saving = true);
    try {
      final dmr = context.read<AppServices>().dmr;
      switch (widget.kind) {
        case DmrEditKind.order:
          await dmr.updateOrder(widget.id, payload);
        case DmrEditKind.entry:
          await dmr.updateEntry(widget.id, payload);
        case DmrEditKind.imprest:
          await dmr.updateImprest(widget.id, payload);
      }
      if (!mounted) return;
      await showSavedConfirmation(context, '$_title saved');
      if (mounted) context.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final vendor = doc == null ? '' : vendorNamesOf(doc);
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: AppTheme.formPadding,
                  child: ErrorBanner(message: _error!, onRetry: _load),
                )
              : ListView(
                  padding: AppTheme.formPadding,
                  children: [
                    Text('Site: ${labelOf(doc?['site'] ?? doc?['site_id'])}'),
                    if (vendor.isNotEmpty) Text('Vendor: $vendor'),
                    const SizedBox(height: 12),
                    PickerField(
                      label: 'Status',
                      required: true,
                      valueLabel: _statuses
                          .where((option) => option.value == _status)
                          .map((option) => option.label)
                          .firstOrNull ??
                          '',
                      onTap: () async {
                        final picked = await showOptionPicker(
                          context,
                          title: 'Status',
                          options: _statuses,
                          selected: _status,
                        );
                        if (picked == null || !mounted) return;
                        setState(() => _status = picked.value);
                      },
                    ),
                    if (widget.kind != DmrEditKind.order) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _gate,
                        decoration: const InputDecoration(labelText: 'Gate entry'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _vehicle,
                        decoration: const InputDecoration(labelText: 'Vehicle number'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _mode,
                        decoration: const InputDecoration(labelText: 'Mode'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _invoice,
                        decoration: const InputDecoration(labelText: 'Invoice number'),
                      ),
                    ],
                    if (widget.kind == DmrEditKind.entry) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _challan,
                        decoration: const InputDecoration(labelText: 'Challan number'),
                      ),
                    ],
                    if (widget.kind == DmrEditKind.imprest) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _vendorName,
                        decoration: const InputDecoration(labelText: 'Vendor name'),
                      ),
                      const SizedBox(height: 12),
                      PickerField(
                        label: 'Date',
                        valueLabel: _date == null ? '' : formatDate(_date!.toIso8601String()),
                        onTap: _pickDate,
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _remarks,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Remarks'),
                    ),
                    const SizedBox(height: 16),
                    const Text('Items', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (_lines.isEmpty) const Text('No items on this record'),
                    for (final line in _lines) ...[
                      Text(itemLabel(line.source), style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: line.qty,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: widget.kind == DmrEditKind.order
                              ? 'PO quantity'
                              : widget.kind == DmrEditKind.entry
                                  ? 'Received quantity'
                                  : 'Quantity',
                        ),
                      ),
                      if (widget.kind == DmrEditKind.imprest) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: line.amount,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Amount'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextField(
                        controller: line.remark,
                        decoration: const InputDecoration(labelText: 'Item remark'),
                      ),
                      const Divider(height: 24),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving ? null : () => context.pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }
}
