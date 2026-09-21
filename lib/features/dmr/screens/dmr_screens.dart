import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../app/app_services.dart';
import '../../app/app_shell.dart';
import '../../pms/widgets/pickers.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../../settings/services/settings_apis.dart';

class DmrStatusScreen extends StatefulWidget {
  const DmrStatusScreen({super.key});

  @override
  State<DmrStatusScreen> createState() => _DmrStatusScreenState();
}

class _DmrStatusScreenState extends State<DmrStatusScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _status = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await context.read<AppServices>().dmr.listOrders({
        'page': 1,
        'limit': 30,
        if (_status.isNotEmpty) 'status': _status,
      });
      if (!mounted) return;
      setState(() {
        _items = res.items;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DMR status'),
        actions: const [WorkspaceSwitcherButton()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/dmr/create'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                for (final s in ['', 'pending', 'partial', 'closed'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.isEmpty ? 'All' : s),
                      selected: _status == s,
                      onSelected: (_) {
                        setState(() => _status = s);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? ListView(children: const [SizedBox(height: 80), Center(child: CircularProgressIndicator())])
                  : _error != null
                      ? ListView(children: [ErrorBanner(message: _error!, onRetry: _load)])
                      : _items.isEmpty
                          ? ListView(children: const [EmptyState(message: 'No DMR orders')])
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final row = _items[i];
                                return Card(
                                  child: ListTile(
                                    title: Text(row['ro_number']?.toString() ?? 'DMR PO'),
                                    subtitle: Text('${labelOf(row['vendor'])} · ${labelOf(row['site'])}'),
                                    trailing: StatusChip(status: row['status']?.toString()),
                                    onTap: () => context.push('/dmr/status/${idOf(row)}'),
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

class DmrOrderDetailScreen extends StatefulWidget {
  const DmrOrderDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<DmrOrderDetailScreen> createState() => _DmrOrderDetailScreenState();
}

class _DmrOrderDetailScreenState extends State<DmrOrderDetailScreen> {
  Map<String, dynamic>? _doc;
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final api = context.read<AppServices>().dmr;
      final doc = await api.getOrder(widget.id);
      final ro = doc['ro_number']?.toString();
      final entries = ro == null || ro.isEmpty
          ? <Map<String, dynamic>>[]
          : await api.entriesByRo({'ro_number': ro});
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _entries = entries;
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

  Future<void> _close() async {
    try {
      await context.read<AppServices>().dmr.closeOrder(widget.id, {'notes': ''});
      showPmsSnack(context, 'Close requested');
      _load();
    } on ApiException catch (e) {
      showPmsSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      appBar: AppBar(title: Text(doc?['ro_number']?.toString() ?? 'DMR order')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorBanner(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    StatusChip(status: doc?['status']?.toString()),
                    const SizedBox(height: 8),
                    Text('Vendor: ${labelOf(doc?['vendor'])}'),
                    Text('Site: ${labelOf(doc?['site'])}'),
                    const Divider(height: 32),
                    const Text('Entries', style: TextStyle(fontWeight: FontWeight.w700)),
                    for (final e in _entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(e['dmr_no']?.toString() ?? e['challan_number']?.toString() ?? 'Entry'),
                        subtitle: Text(e['entry_type']?.toString() ?? ''),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _close, child: const Text('Close order')),
                  ],
                ),
    );
  }
}

class DmrCreateScreen extends StatefulWidget {
  const DmrCreateScreen({super.key});

  @override
  State<DmrCreateScreen> createState() => _DmrCreateScreenState();
}

class _DmrCreateScreenState extends State<DmrCreateScreen> {
  String? _siteId;
  String _siteLabel = '';
  String? _vendorId;
  String _vendorLabel = '';
  String? _roId;
  String _roLabel = '';
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _vendors = [];
  List<Map<String, dynamic>> _open = [];
  final _challan = TextEditingController();
  final _dmrNo = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settings = context.read<SettingsApis>();
      final sites = await settings.sites.list({'limit': 100});
      final vendors = await settings.vendors.list({'limit': 100});
      if (!mounted) return;
      setState(() {
        _sites = sites.items;
        _vendors = vendors.items;
      });
    });
  }

  @override
  void dispose() {
    _challan.dispose();
    _dmrNo.dispose();
    super.dispose();
  }

  Future<void> _loadOpen() async {
    if (_siteId == null || _vendorId == null) return;
    final open = await context.read<AppServices>().dmr.listOpenOrders({
      'site': _siteId,
      'vendor_id': _vendorId,
    });
    if (!mounted) return;
    setState(() => _open = open);
  }

  Future<void> _save() async {
    if (_siteId == null || _challan.text.trim().isEmpty || _dmrNo.text.trim().isEmpty) {
      showPmsSnack(context, 'Site, DMR no and challan number are required', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppServices>().dmr.createChallan({
        'site': _siteId,
        'vendor_id': _vendorId,
        'ro_id': _roId,
        'dmr_no': _dmrNo.text.trim(),
        'challan_number': _challan.text.trim(),
        'pr_type': 'Site Establishment',
        'dmr_items': [
          {
            'item_name': 'Item',
            'received_qty': 1,
            'accepted_qty': 1,
          }
        ],
      });
      if (!mounted) return;
      showPmsSnack(context, 'Challan created');
      context.pop();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create DMR challan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PickerField(
            label: 'Site',
            required: true,
            valueLabel: _siteLabel,
            onTap: () async {
              final p = await showOptionPicker(
                context,
                title: 'Site',
                options: mapToOptions(_sites, labelOfRow: (r) => r['site_name']?.toString() ?? labelOf(r)),
                selected: _siteId,
              );
              if (p == null) return;
              setState(() {
                _siteId = p.value;
                _siteLabel = p.label;
              });
              _loadOpen();
            },
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Vendor',
            valueLabel: _vendorLabel,
            onTap: () async {
              final p = await showOptionPicker(
                context,
                title: 'Vendor',
                options: mapToOptions(_vendors, labelOfRow: (r) => r['vendor_name']?.toString() ?? labelOf(r)),
                selected: _vendorId,
              );
              if (p == null) return;
              setState(() {
                _vendorId = p.value;
                _vendorLabel = p.label;
              });
              _loadOpen();
            },
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Open PO',
            valueLabel: _roLabel,
            onTap: () async {
              final p = await showOptionPicker(
                context,
                title: 'Open PO',
                options: mapToOptions(_open, labelOfRow: (r) => r['ro_number']?.toString() ?? labelOf(r)),
                selected: _roId,
              );
              if (p == null) return;
              setState(() {
                _roId = p.value;
                _roLabel = p.label;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(controller: _dmrNo, decoration: const InputDecoration(labelText: 'DMR no *')),
          const SizedBox(height: 12),
          TextField(controller: _challan, decoration: const InputDecoration(labelText: 'Challan number *')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Submit challan'),
          ),
        ],
      ),
    );
  }
}
