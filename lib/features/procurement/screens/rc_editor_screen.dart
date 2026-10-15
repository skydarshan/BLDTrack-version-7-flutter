import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../app/app_services.dart';
import '../../pms/widgets/media_widgets.dart';
import '../../pms/widgets/pickers.dart';
import '../../pms/widgets/pms_widgets.dart';

const _gstOptions = ['0', '5', '12', '18', '28'];
const _orderTypes = ['Purchase Order', 'Work Order'];

class RcEditorScreen extends StatefulWidget {
  const RcEditorScreen({super.key, required this.id});

  final String id;

  @override
  State<RcEditorScreen> createState() => _RcEditorScreenState();
}

class _RcEditorScreenState extends State<RcEditorScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _status = '';
  String _stage = '';
  String _requestType = '';
  String _category = '';
  String _prNo = '';
  String _siteName = '';
  String _requestDate = '';
  String _requiredBy = '';
  String _comparativeNo = '';
  String _orderType = 'Purchase Order';
  bool _openOrder = false;
  bool _ratesVisible = false;

  final _remarks = TextEditingController();
  final _vendorSearch = TextEditingController();
  final _ratesKey = GlobalKey();

  final _items = <_ItemDraft>[];
  final _vendors = <_VendorDraft>[];
  List<Map<String, dynamic>> _vendorMaster = [];

  bool get _canEdit =>
      _stage != 'rate_approval' &&
      (_status == 'pending' || _status == 'draft' || _status == 'revise');

  bool get _canApprove =>
      _stage == 'rate_approval' && (_status == 'pending' || _status == 'revised');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _remarks.dispose();
    _vendorSearch.dispose();
    for (final item in _items) {
      item.dispose();
    }
    for (final vendor in _vendors) {
      vendor.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final services = context.read<AppServices>();
      final doc = await services.rc.getById(widget.id);
      await resolveDocItemNames(doc, services.settings.items.getById);
      if (!mounted) return;
      _hydrate(doc);
      setState(() => _loading = false);
      _loadVendors();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadVendors() async {
    try {
      final rows = await context.read<AppServices>().settings.vendors.listAll();
      if (!mounted) return;
      setState(() => _vendorMaster = rows);
    } catch (_) {}
  }

  void _hydrate(Map<String, dynamic> doc) {
    for (final item in _items) {
      item.dispose();
    }
    for (final vendor in _vendors) {
      vendor.dispose();
    }
    _items.clear();
    _vendors.clear();
    final rr = doc['requisition_request_id'];
    final rrMap = rr is Map ? Map<String, dynamic>.from(rr) : null;
    _status = doc['status']?.toString() ?? '';
    _stage = doc['stage']?.toString() ?? '';
    _requestType = _requestTypeLabel(rrMap?['prType']?.toString() ?? '');
    _category = rrMap?['title']?.toString().trim() ?? '';
    _prNo = rrMap?['requisition_request_number']?.toString() ?? '';
    _siteName = siteNameOf(doc);
    if (_siteName.isEmpty && rrMap != null) _siteName = siteNameOf(rrMap);
    _requestDate = formatDate(rrMap?['date'] ?? doc['createdAt']);
    _requiredBy = formatDate(rrMap?['expected_delivery_date']);
    _comparativeNo = doc['comparative_no']?.toString() ?? '';
    final order = doc['order_type']?.toString() ?? '';
    _orderType = _orderTypes.contains(order) ? order : 'Purchase Order';
    _openOrder = doc['open_order']?.toString() == 'yes';
    _remarks.text = doc['remarks']?.toString() ?? '';

    final totals = asMapList(doc['vendors_total'] is List ? doc['vendors_total'] : const []);
    final lines = lineItemsOf(doc);
    for (final line in lines) {
      final item = line['item_id'];
      final itemMap = item is Map ? Map<String, dynamic>.from(item) : null;
      final qty = asNum(line['qty']) ?? 1;
      final gstRaw = asNum(line['gst']) ?? 0;
      final gst = gstRaw > 0 && gstRaw <= 1 ? gstRaw * 100 : gstRaw;
      final draft = _ItemDraft(
        itemId: idOf(item) ?? '',
        name: _itemName(line, itemMap),
        code: _text(itemMap?['item_code'] ?? itemMap?['item_number']),
        spec: _text(itemMap?['specification']),
        subCategory: _cleanLabel(itemMap?['sub_category']),
        uom: _firstLabel([line['uom'], itemMap?['uom']]),
        uomId: idOf(line['uom']),
        qty: qty < 1 ? 1 : qty,
        gst: _snapGst(gst),
        remark: line['remark']?.toString() ?? '',
        brandIds: _idList(line['brandName']),
      );
      final budget = asNum(line['budget']) ?? 0;
      if (budget > 0) draft.budget.text = _plain(budget);
      draft.procurement.text = line['procurement_remarks']?.toString() ?? '';
      _items.add(draft);

      for (final vendor in asMapList(line['vendors'] is List ? line['vendors'] : const [])) {
        final id = idOf(vendor['vendor_id']);
        if (id == null || id.isEmpty) continue;
        _ensureVendor(id, _vendorName(vendor), _vendorCode(vendor));
      }
    }
    for (final row in totals) {
      final id = idOf(row['vendor_id']);
      if (id == null || id.isEmpty) continue;
      final vendor = _ensureVendor(id, _vendorName(row), _vendorCode(row));
      final freight = asNum(row['freight_charges']) ?? 0;
      final freightTax = asNum(row['freight_tax']) ?? 0;
      final other = asNum(row['other_charges']) ?? 0;
      if (freight > 0) vendor.freight.text = _plain(freight);
      vendor.freightGst = _freightPercent(freight, freightTax);
      if (other > 0) vendor.other.text = _plain(other);
      vendor.payment.text = row['paymentTerms']?.toString() ?? '';
      vendor.delivery.text = row['deliveryTerms']?.toString() ?? '';
      vendor.remark.text = row['vendorRemark']?.toString() ?? '';
      vendor.quoteUrl = row['vendor_quotation']?.toString() ?? '';
    }
    for (final item in _items) {
      for (final vendor in _vendors) {
        item.cells.putIfAbsent(vendor.id, () => _RateCell(qtyText: _plain(item.qty)));
      }
    }
    for (final line in lines) {
      final itemId = idOf(line['item_id']);
      _ItemDraft? item;
      for (final row in _items) {
        if (row.itemId == itemId) item = row;
      }
      if (item == null) continue;
      for (final vendor in asMapList(line['vendors'] is List ? line['vendors'] : const [])) {
        final id = idOf(vendor['vendor_id']);
        final cell = id == null ? null : item.cells[id];
        if (cell == null) continue;
        final available = asNum(vendor['requiredQty']) ?? 0;
        cell.qtyCtrl.text = _plain(available > 0 ? available : item.qty);
        final rate = asNum(vendor['rate']) ?? 0;
        if (rate > 0) cell.rateCtrl.text = _plain(rate);
        cell.preferred = vendor['preferred'] == true;
      }
    }
    _ratesVisible = _vendors.isNotEmpty;
  }

  _VendorDraft _ensureVendor(String id, String name, String code) {
    for (final vendor in _vendors) {
      if (vendor.id == id) {
        if (vendor.name.isEmpty && name.isNotEmpty) vendor.name = name;
        if (vendor.code.isEmpty && code.isNotEmpty) vendor.code = code;
        return vendor;
      }
    }
    final created = _VendorDraft(id: id, name: name, code: code);
    _vendors.add(created);
    return created;
  }

  void _addVendor(Map<String, dynamic> row) {
    if (!_canEdit) return;
    final id = idOf(row);
    if (id == null || id.isEmpty) return;
    if (_vendors.any((vendor) => vendor.id == id)) return;
    final draft = _VendorDraft(
      id: id,
      name: row['vendor_name']?.toString() ?? '',
      code: _text(row['code'] ?? row['Uniquecode']),
    );
    setState(() {
      _vendors.add(draft);
      for (final item in _items) {
        item.cells[id] = _RateCell(qtyText: _plain(item.qty));
      }
    });
  }

  void _removeVendor(_VendorDraft vendor) {
    if (!_canEdit) return;
    final cells = <_RateCell>[];
    for (final item in _items) {
      final cell = item.cells.remove(vendor.id);
      if (cell != null) cells.add(cell);
    }
    setState(() => _vendors.remove(vendor));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final cell in cells) {
        cell.dispose();
      }
      vendor.dispose();
    });
  }

  List<Map<String, dynamic>> get _vendorMatches {
    final query = _vendorSearch.text.trim().toLowerCase();
    final rows = _vendorMaster.where((row) {
      final id = idOf(row);
      if (id != null && _vendors.any((vendor) => vendor.id == id)) return false;
      if (query.isEmpty) return true;
      final name = row['vendor_name']?.toString().toLowerCase() ?? '';
      final code = '${row['code'] ?? ''} ${row['Uniquecode'] ?? ''}'.toLowerCase();
      return name.contains(query) || code.contains(query);
    }).toList();
    return rows.take(30).toList();
  }

  double _lineSubtotal(_ItemDraft item, _RateCell? cell) {
    final rate = _number(cell?.rateCtrl.text);
    return item.qty * rate;
  }

  double _budgetSubtotal(_ItemDraft item) => item.qty * _number(item.budget.text);

  _VendorTotals _totals(_VendorDraft vendor) {
    var subtotal = 0.0;
    var tax = 0.0;
    for (final item in _items) {
      final amount = _lineSubtotal(item, item.cells[vendor.id]);
      subtotal += amount;
      tax += amount * (int.tryParse(item.gst) ?? 0) / 100;
    }
    final freight = _number(vendor.freight.text);
    final freightTax = freight * (int.tryParse(vendor.freightGst) ?? 0) / 100;
    final other = _number(vendor.other.text);
    return _VendorTotals(
      subtotal: subtotal,
      tax: tax,
      freight: freight,
      freightTax: freightTax,
      other: other,
      total: subtotal + tax + freight + freightTax + other,
    );
  }

  bool get _hasRate {
    for (final item in _items) {
      for (final cell in item.cells.values) {
        if (_number(cell.rateCtrl.text) > 0) return true;
      }
    }
    return false;
  }

  bool get _hasQuotation =>
      _vendors.any((vendor) => vendor.file != null || vendor.quoteUrl.trim().isNotEmpty);

  Map<String, dynamic> _payload({required bool submit}) {
    final vendorsTotal = <Map<String, dynamic>>[];
    for (final vendor in _vendors) {
      final totals = _totals(vendor);
      final preferred = _items.any((item) => item.cells[vendor.id]?.preferred == true);
      vendorsTotal.add({
        'vendor_id': vendor.id,
        'subtotal': totals.subtotal,
        'total_tax': totals.tax,
        'freight_charges': totals.freight,
        'freight_tax': totals.freightTax,
        'other_charges': totals.other,
        'other_tax': 0,
        'total_amount': totals.total,
        'preferred': preferred,
        'vendor_quotation': vendor.file == null ? vendor.quoteUrl.trim() : '',
        'paymentTerms': vendor.payment.text.trim(),
        'deliveryTerms': vendor.delivery.text.trim(),
        'vendorRemark': vendor.remark.text.trim(),
      });
    }
    return {
      if (!submit || _status != 'revise') 'status': submit ? 'pending' : 'draft',
      'order_type': _orderType,
      'open_order': _openOrder ? 'yes' : 'no',
      'remarks': _remarks.text.trim(),
      'vendorRatesItemWise': <dynamic>[],
      'items': [
        for (final item in _items)
          if (item.itemId.length == 24)
          {
            'item_id': item.itemId,
            'qty': item.qty,
            if (item.uomId != null) 'uom': item.uomId,
            'remark': item.remark,
            'procurement_remarks': item.procurement.text.trim(),
            'brandName': item.brandIds,
            'gst': int.tryParse(item.gst) ?? 0,
            'budget': _number(item.budget.text),
            'budget_subtotal': _budgetSubtotal(item),
            'vendors': [
              for (final vendor in _vendors)
                {
                  'vendor_id': vendor.id,
                  'vendor_name': vendor.name,
                  'requiredQty': _number(item.cells[vendor.id]?.qtyCtrl.text),
                  'preferred': item.cells[vendor.id]?.preferred == true,
                  'rate': _number(item.cells[vendor.id]?.rateCtrl.text),
                  'amount': _lineSubtotal(item, item.cells[vendor.id]),
                },
            ],
          },
      ],
      'vendors_total': vendorsTotal,
    };
  }

  Map<String, MultipartFileEntry> _files() {
    final files = <String, MultipartFileEntry>{};
    for (var i = 0; i < _vendors.length; i++) {
      final file = _vendors[i].file;
      if (file != null) files['vendors_total_${i}_vendor_quotation'] = file.toEntry();
    }
    return files;
  }

  void _rememberQuotes(Map<String, dynamic> saved) {
    final totals = asMapList(saved['vendors_total'] is List ? saved['vendors_total'] : const []);
    for (final row in totals) {
      final id = idOf(row['vendor_id']);
      final url = row['vendor_quotation']?.toString() ?? '';
      if (id == null || url.isEmpty) continue;
      for (final vendor in _vendors) {
        if (vendor.id == id) {
          vendor.quoteUrl = url;
          vendor.file = null;
        }
      }
    }
    final status = saved['status']?.toString();
    final stage = saved['stage']?.toString();
    if (status != null && status.isNotEmpty) _status = status;
    if (stage != null && stage.isNotEmpty) _stage = stage;
  }

  Future<void> _save({required bool submit}) async {
    if (_vendors.isEmpty) {
      showPmsSnack(context, 'Select at least one vendor', error: true);
      return;
    }
    if (submit) {
      for (final vendor in _vendors) {
        if (vendor.file == null && vendor.quoteUrl.trim().isEmpty) {
          showPmsSnack(context, 'Upload a quotation for ${vendor.label}', error: true);
          return;
        }
      }
    }
    setState(() => _saving = true);
    try {
      final rc = context.read<AppServices>().rc;
      final path = submit && _status == 'revise'
          ? '/rate-comparatives/${widget.id}/revise'
          : '/rate-comparatives/${widget.id}';
      final saved = await rc.saveForm(path, _payload(submit: submit), files: _files());
      if (!mounted) return;
      setState(() {
        _rememberQuotes(saved);
        _saving = false;
      });
      if (submit) {
        showPmsSnack(context, 'Comparative submitted');
        context.pop();
      } else {
        showPmsSnack(context, 'Draft saved');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showPmsSnack(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showPmsSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _setStatus(String status) async {
    setState(() => _saving = true);
    try {
      final body = _payload(submit: true);
      await context.read<AppServices>().rc.updateStatus(widget.id, {
        'status': status,
        'items': body['items'],
        'vendors_total': body['vendors_total'],
        if (_remarks.text.trim().isNotEmpty) 'remarks': _remarks.text.trim(),
      });
      if (!mounted) return;
      showPmsSnack(context, 'Marked $status');
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showPmsSnack(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showPmsSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _pickOrderType() async {
    final picked = await showOptionPicker(
      context,
      title: 'Site Order Type',
      options: [
        for (final type in _orderTypes) OptionItem(value: type, label: type),
      ],
      selected: _orderType,
    );
    if (picked == null || !mounted) return;
    setState(() => _orderType = picked.value);
  }

  Future<void> _pickGst(_ItemDraft item) async {
    final picked = await showOptionPicker(
      context,
      title: 'GST %',
      options: [for (final gst in _gstOptions) OptionItem(value: gst, label: '$gst%')],
      selected: item.gst,
    );
    if (picked == null || !mounted) return;
    setState(() => item.gst = picked.value);
  }

  Future<void> _pickFreightGst(_VendorDraft vendor) async {
    final picked = await showOptionPicker(
      context,
      title: 'Freight GST %',
      options: [for (final gst in _gstOptions) OptionItem(value: gst, label: '$gst%')],
      selected: vendor.freightGst,
    );
    if (picked == null || !mounted) return;
    setState(() => vendor.freightGst = picked.value);
  }

  Future<void> _pickQuote(_VendorDraft vendor) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'xls', 'xlsx'],
    );
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null || !mounted) return;
    setState(() {
      vendor.file = PendingFile(bytes: file.bytes!, filename: file.name);
    });
  }

  Future<void> _extractOne(_VendorDraft vendor) async {
    if (vendor.file == null && vendor.quoteUrl.trim().isEmpty) {
      showPmsSnack(context, 'Choose a quotation file first', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await context.read<AppServices>().rc.extractQuotation(
            widget.id,
            vendorId: vendor.id,
            file: vendor.file?.toEntry(),
            fileUrl: vendor.file == null ? vendor.quoteUrl : null,
          );
      if (!mounted) return;
      setState(() {
        _applyExtract(vendor, result);
        _saving = false;
      });
      final warnings = result['warnings'];
      final message = warnings is List && warnings.isNotEmpty
          ? warnings.first.toString()
          : 'Rates filled from ${vendor.label}';
      showPmsSnack(context, message, error: warnings is List && warnings.isNotEmpty);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showPmsSnack(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showPmsSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _extractAll() async {
    final targets = _vendors
        .where((vendor) => vendor.file != null || vendor.quoteUrl.trim().isNotEmpty)
        .toList();
    if (targets.isEmpty) return;
    setState(() => _saving = true);
    var filled = 0;
    String? error;
    try {
      final rc = context.read<AppServices>().rc;
      for (final vendor in targets) {
        try {
          final result = await rc.extractQuotation(
            widget.id,
            vendorId: vendor.id,
            file: vendor.file?.toEntry(),
            fileUrl: vendor.file == null ? vendor.quoteUrl : null,
          );
          _applyExtract(vendor, result);
          filled += 1;
        } on ApiException catch (e) {
          error ??= e.message;
        }
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        showPmsSnack(
          context,
          filled == 0 ? (error ?? 'Could not extract quotations') : 'Extracted $filled quotation${filled == 1 ? '' : 's'}',
          error: filled == 0,
        );
      }
    }
  }

  void _applyExtract(_VendorDraft vendor, Map<String, dynamic> result) {
    final lines = result['items'];
    if (lines is List) {
      for (final raw in lines) {
        if (raw is! Map) continue;
        final line = Map<String, dynamic>.from(raw);
        _ItemDraft? item;
        final itemId = line['item_id']?.toString() ?? '';
        for (final row in _items) {
          if (row.itemId == itemId) item = row;
        }
        if (item == null && line['item_index'] is num) {
          final index = (line['item_index'] as num).toInt();
          if (index >= 0 && index < _items.length) item = _items[index];
        }
        final rate = asNum(line['apply_rate'] ?? line['unit_rate']);
        if (item == null || rate == null) continue;
        item.cells[vendor.id]?.rateCtrl.text = _plain(rate);
        final gst = asNum(line['gst_percent']);
        if (gst != null && gst > 0) item.gst = _snapGst(gst > 1 ? gst : gst * 100);
      }
    }
    final freight = asNum(result['freight_charges']);
    final other = asNum(result['other_charges']);
    if (freight != null && freight > 0) vendor.freight.text = _plain(freight);
    if (other != null && other > 0) vendor.other.text = _plain(other);
    final payment = result['payment_terms']?.toString();
    final delivery = result['delivery_terms']?.toString();
    final remark = result['vendor_remark']?.toString();
    if (payment != null && payment.isNotEmpty) vendor.payment.text = payment;
    if (delivery != null && delivery.isNotEmpty) vendor.delivery.text = delivery;
    if (remark != null && remark.isNotEmpty) vendor.remark.text = remark;
    _ratesVisible = true;
  }

  void _enterRates() {
    if (_vendors.isEmpty) {
      showPmsSnack(context, 'Select at least one vendor', error: true);
      return;
    }
    setState(() => _ratesVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _ratesKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 300));
      }
    });
  }

  Future<void> _compare() async {
    final rows = [
      for (final vendor in _vendors) (vendor: vendor, totals: _totals(vendor)),
    ]..sort((a, b) => a.totals.total.compareTo(b.totals.total));
    final lowest = rows.isEmpty ? 0.0 : rows.first.totals.total;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: AppTheme.formPadding,
          children: [
            Text('Compare Rates', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final row in rows)
              Card(
                child: ListTile(
                  title: Text(row.vendor.label),
                  subtitle: Text('GST ${_inr(row.totals.tax)} · Freight ${_inr(row.totals.freight)}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_inr(row.totals.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (row.totals.total == lowest && lowest > 0)
                        const Text('Lowest', style: TextStyle(color: AppTheme.success, fontSize: 12)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _analyze() async {
    setState(() => _saving = true);
    try {
      final result = await context.read<AppServices>().rc.analyze(widget.id);
      if (!mounted) return;
      setState(() => _saving = false);
      final text = _analysisText(result);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('AI Analysis'),
          content: SingleChildScrollView(child: Text(text.isEmpty ? 'Analysis finished.' : text)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showPmsSnack(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showPmsSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _openQuote(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate Comparative'),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _analyze,
            child: const Text('AI Analysis'),
          ),
        ],
      ),
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
                    if (_saving) const LinearProgressIndicator(),
                    _headerCard(),
                    const SizedBox(height: 12),
                    _vendorCard(),
                    if (_ratesVisible && _vendors.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _ratesSection(),
                      const SizedBox(height: 12),
                      _termsSection(),
                    ],
                    const SizedBox(height: 12),
                    _footer(),
                  ],
                ),
    );
  }

  Widget _headerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _kv('Request Type', _requestType),
            _kv('Request Category', _category),
            _kv('Purchase Request No.', _prNo.isEmpty ? '—' : _prNo),
            _kv('Site name', _siteName),
            _kv('Request date', _requestDate),
            _kv('Required by', _requiredBy),
            const SizedBox(height: 8),
            InkWell(
              onTap: _canEdit && !_saving ? _pickOrderType : null,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Site Order Type *'),
                child: Text(_orderType),
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _openOrder,
              onChanged: _canEdit && !_saving ? (value) => setState(() => _openOrder = value ?? false) : null,
              title: const Text('Open Order'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            _kv('Status', _status.isEmpty ? '—' : _status),
            _kv('Comparative No', _comparativeNo.isEmpty ? '—' : _comparativeNo),
          ],
        ),
      ),
    );
  }

  Widget _vendorCard() {
    final matches = _vendorMatches;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Select your Vendors', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_vendors.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final vendor in _vendors)
                    InputChip(
                      label: Text(vendor.label),
                      onDeleted: _canEdit && !_saving ? () => _removeVendor(vendor) : null,
                    ),
                ],
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _vendorSearch,
              enabled: _canEdit && !_saving,
              decoration: const InputDecoration(
                hintText: 'Search vendors / suppliers...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_canEdit && matches.isNotEmpty)
              SizedBox(
                height: 180,
                child: ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final row = matches[index];
                    final code = _text(row['code'] ?? row['Uniquecode']);
                    final name = row['vendor_name']?.toString() ?? 'Vendor';
                    return CheckboxListTile(
                      dense: true,
                      value: false,
                      title: Text(code.isEmpty ? name : '$name ($code)'),
                      onChanged: _saving ? null : (_) => _addVendor(row),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saving ? null : _enterRates,
              child: const Text('Enter Vendor Rates'),
            ),
            if (_items.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Items / Sub Category', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final item in _items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${item.name}${item.uom.isEmpty ? '' : ' (${item.uom})'}'
                    '${item.subCategory.isEmpty ? '' : ' / ${item.subCategory}'}',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ratesSection() {
    return Column(
      key: _ratesKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in _items) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _kv('Item Code', item.code.isEmpty ? '—' : item.code),
                  _kv('Specification', item.spec.isEmpty ? '-' : item.spec),
                  _kv('Sub Category', item.subCategory.isEmpty ? '—' : item.subCategory),
                  _kv('UOM', item.uom.isEmpty ? '—' : item.uom),
                  _kv('Quantity', _plain(item.qty)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _canEdit && !_saving ? () => _pickGst(item) : null,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'GST %'),
                      child: Text('${item.gst}%'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: item.budget,
                    enabled: _canEdit && !_saving,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Budget (₹)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  _kv('Budget SubTotal (₹)', _inr(_budgetSubtotal(item))),
                  const SizedBox(height: 8),
                  TextField(
                    controller: item.procurement,
                    enabled: _canEdit && !_saving,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Procurement Remarks'),
                  ),
                  for (final vendor in _vendors) _vendorRateBox(item, vendor),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Totals', style: Theme.of(context).textTheme.titleMedium),
                for (final vendor in _vendors) ...[
                  const Divider(),
                  Text(vendor.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  _kv('Total Amount (₹)', _inr(_totals(vendor).subtotal)),
                  _kv('GST Amount (₹)', _inr(_totals(vendor).tax)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _vendorRateBox(_ItemDraft item, _VendorDraft vendor) {
    final cell = item.cells[vendor.id];
    if (cell == null) return const SizedBox.shrink();
    final available = _number(cell.qtyCtrl.text);
    final overPreferred = cell.preferred && available > item.qty;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: cell.preferred,
            onChanged: _canEdit && !_saving
                ? (value) => setState(() => cell.preferred = value ?? false)
                : null,
            title: Text(vendor.label),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          TextField(
            controller: cell.qtyCtrl,
            enabled: _canEdit && !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Available Qty'),
            onChanged: (_) => setState(() {}),
          ),
          if (overPreferred)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppTheme.warning),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Max ${_plain(item.qty)} when preferred',
                      style: const TextStyle(color: AppTheme.warning, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: cell.rateCtrl,
            enabled: _canEdit && !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Rate (₹)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          _kv('Sub Total (₹)', _inr(_lineSubtotal(item, cell))),
        ],
      ),
    );
  }

  Widget _termsSection() {
    return Column(
      children: [
        for (final vendor in _vendors) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(vendor.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: vendor.freight,
                    enabled: _canEdit && !_saving,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Freight (₹)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _canEdit && !_saving ? () => _pickFreightGst(vendor) : null,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Freight GST (%)'),
                      child: Text('${vendor.freightGst}%'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: vendor.other,
                    enabled: _canEdit && !_saving,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Other Charges (₹)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: vendor.payment,
                    enabled: _canEdit && !_saving,
                    decoration: const InputDecoration(labelText: 'Payment Terms'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: vendor.delivery,
                    enabled: _canEdit && !_saving,
                    decoration: const InputDecoration(labelText: 'Delivery Terms'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: vendor.remark,
                    enabled: _canEdit && !_saving,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Vendor remark'),
                  ),
                  const SizedBox(height: 8),
                  const Text('Vendor Quotation'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_canEdit)
                        OutlinedButton(
                          onPressed: _saving ? null : () => _pickQuote(vendor),
                          child: const Text('Choose File'),
                        ),
                      if (vendor.file != null || vendor.quoteUrl.trim().isNotEmpty)
                        InputChip(
                          label: Text(_quoteName(vendor), overflow: TextOverflow.ellipsis),
                          onPressed: vendor.quoteUrl.trim().isEmpty ? null : () => _openQuote(vendor.quoteUrl),
                          onDeleted: _canEdit && !_saving
                              ? () => setState(() {
                                    vendor.file = null;
                                    vendor.quoteUrl = '';
                                  })
                              : null,
                        ),
                      if (_canEdit)
                        TextButton(
                          onPressed: _saving ? null : () => _extractOne(vendor),
                          child: const Text('Auto-extract'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _footer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving || !_hasRate ? null : _compare,
                child: const Text('Compare Rates'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _saving || !_hasQuotation || !_canEdit ? null : _extractAll,
                child: const Text('Extract All Quotations'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _remarks,
          enabled: _canEdit && !_saving,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Remarks'),
        ),
        const SizedBox(height: 12),
        if (_canEdit)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save(submit: false),
                  child: const Text('Save Draft'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(submit: true),
                  child: const Text('Submit Comparative'),
                ),
              ),
            ],
          ),
        if (_canApprove) ...[
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : () => _setStatus('approved'),
            child: const Text('Approve'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _saving ? null : () => _setStatus('revise'),
            child: const Text('Revise'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _saving ? null : () => _setStatus('rejected'),
            child: const Text('Reject'),
          ),
        ],
      ],
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 148, child: Text(label, style: const TextStyle(color: AppTheme.muted))),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}

class _ItemDraft {
  _ItemDraft({
    required this.itemId,
    required this.name,
    required this.code,
    required this.spec,
    required this.subCategory,
    required this.uom,
    required this.uomId,
    required this.qty,
    required this.gst,
    required this.remark,
    required this.brandIds,
  });

  final String itemId;
  final String name;
  final String code;
  final String spec;
  final String subCategory;
  final String uom;
  final String? uomId;
  final num qty;
  String gst;
  final String remark;
  final List<String> brandIds;
  final budget = TextEditingController();
  final procurement = TextEditingController();
  final cells = <String, _RateCell>{};

  void dispose() {
    budget.dispose();
    procurement.dispose();
    for (final cell in cells.values) {
      cell.dispose();
    }
  }
}

class _RateCell {
  _RateCell({this.qtyText = ''}) {
    qtyCtrl.text = qtyText;
  }

  final qtyCtrl = TextEditingController();
  final rateCtrl = TextEditingController();
  bool preferred = false;
  final String qtyText;

  void dispose() {
    qtyCtrl.dispose();
    rateCtrl.dispose();
  }
}

class _VendorDraft {
  _VendorDraft({required this.id, required this.name, required this.code});

  final String id;
  String name;
  String code;
  String freightGst = '0';
  String quoteUrl = '';
  PendingFile? file;
  final freight = TextEditingController();
  final other = TextEditingController();
  final payment = TextEditingController();
  final delivery = TextEditingController();
  final remark = TextEditingController();

  String get label {
    if (name.isEmpty) return code.isEmpty ? 'Vendor' : code;
    return code.isEmpty ? name : '$name ($code)';
  }

  void dispose() {
    freight.dispose();
    other.dispose();
    payment.dispose();
    delivery.dispose();
    remark.dispose();
  }
}

class _VendorTotals {
  const _VendorTotals({
    required this.subtotal,
    required this.tax,
    required this.freight,
    required this.freightTax,
    required this.other,
    required this.total,
  });

  final double subtotal;
  final double tax;
  final double freight;
  final double freightTax;
  final double other;
  final double total;
}

String _plain(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

String _inr(num value) => '₹${value.toStringAsFixed(2)}';

double _number(String? raw) => double.tryParse((raw ?? '').replaceAll(',', '').trim()) ?? 0;

String _text(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text == 'null' ? '' : text;
}

String _snapGst(num value) {
  const options = [0, 5, 12, 18, 28];
  var best = options.first;
  var bestDiff = (value - best).abs();
  for (final option in options) {
    final diff = (value - option).abs();
    if (diff < bestDiff) {
      best = option;
      bestDiff = diff;
    }
  }
  return '$best';
}

String _freightPercent(num freight, num tax) {
  if (freight <= 0 || tax <= 0) return '0';
  return _snapGst(tax / freight * 100);
}

String _requestTypeLabel(String raw) {
  switch (raw.trim()) {
    case 'Assets':
      return 'Plant & Machinery';
    case 'Site Establishment':
      return 'Site Establishment';
    case 'Project BOQ':
      return 'Project BOQ';
    default:
      return raw.trim().isEmpty ? '—' : raw.trim();
  }
}

String _itemName(Map<String, dynamic> line, Map<String, dynamic>? item) {
  final direct = line['item_name']?.toString().trim() ?? '';
  if (direct.isNotEmpty && !looksLikeObjectId(direct)) return direct;
  final named = labelOf(item, fallback: '');
  return named.isEmpty ? 'Item' : named;
}

String _cleanLabel(dynamic value) {
  final text = labelOf(value, fallback: '');
  return text == '—' ? '' : text;
}

String _firstLabel(List<dynamic> values) {
  for (final value in values) {
    final text = _cleanLabel(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

List<String> _idList(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map(idOf).whereType<String>().where((id) => id.length == 24).toList();
}

String _vendorName(Map<String, dynamic> row) {
  final nested = row['vendor_id'];
  if (nested is Map) {
    final name = nested['vendor_name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
  }
  return row['vendor_name']?.toString().trim() ?? '';
}

String _vendorCode(Map<String, dynamic> row) {
  final nested = row['vendor_id'];
  if (nested is Map) {
    final code = _text(nested['code'] ?? nested['Uniquecode']);
    if (code.isNotEmpty) return code;
  }
  return _text(row['code'] ?? row['Uniquecode']);
}

String _quoteName(_VendorDraft vendor) {
  final name = vendor.file?.filename ?? '';
  if (name.isNotEmpty) return name.length > 22 ? '${name.substring(0, 22)}...' : name;
  final uri = Uri.tryParse(vendor.quoteUrl);
  final last = uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : vendor.quoteUrl;
  return last.length > 22 ? '${last.substring(0, 22)}...' : last;
}

String _analysisText(Map<String, dynamic> result) {
  final lines = <String>[];
  final analysis = result['ai_analysis'];
  if (analysis is Map) {
    final summary = analysis['executive_summary']?.toString().trim() ?? '';
    final vendor = analysis['recommended_vendor_name']?.toString().trim() ?? '';
    final confidence = analysis['recommendation_confidence']?.toString().trim() ?? '';
    final detail = analysis['detailed_reasoning']?.toString().trim() ?? '';
    if (vendor.isNotEmpty) {
      lines.add('Recommended: $vendor${confidence.isEmpty ? '' : ' ($confidence)'}');
    }
    if (summary.isNotEmpty) lines.add(summary);
    if (detail.isNotEmpty) lines.add(detail);
  }
  final items = result['item_wise_best'];
  if (items is List && items.isNotEmpty) {
    lines.add('Best price');
    for (final raw in items) {
      if (raw is! Map) continue;
      final name = raw['item_name']?.toString() ?? 'Item';
      final best = raw['best_price_vendor'];
      if (best is Map) {
        lines.add('$name: ${best['vendor_name'] ?? '—'} @ ${_plain(asNum(best['rate']) ?? 0)}');
      } else {
        lines.add('$name: no quote');
      }
    }
  }
  return lines.join('\n\n');
}
