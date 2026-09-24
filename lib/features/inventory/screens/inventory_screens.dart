import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/modern_widgets.dart';
import '../../app/app_services.dart';
import '../../app/app_shell.dart';
import '../../pms/widgets/pickers.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../../settings/services/settings_apis.dart';

class InventoryHomeScreen extends StatefulWidget {
  const InventoryHomeScreen({super.key});

  @override
  State<InventoryHomeScreen> createState() => _InventoryHomeScreenState();
}

class _InventoryHomeScreenState extends State<InventoryHomeScreen> {
  String _view = 'stats';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

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
      final api = context.read<AppServices>().inventory;
      final res = switch (_view) {
        'in' => await api.ins({'page': 1, 'limit': 30}),
        'out' => await api.outs({'page': 1, 'limit': 30}),
        _ => await api.statistics({'page': 1, 'limit': 30}),
      };
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
      extendBody: true,
      appBar: const ModernAppBar(
        title: 'Inventory',
        actions: [WorkspaceSwitcherButton()],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppTheme.filterPadding,
            child: SegmentedButton<String>(
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppTheme.brandLight;
                  }
                  return Colors.white;
                }),
              ),
              segments: const [
                ButtonSegment(value: 'stats', label: Text('Stock'), icon: Icon(Icons.inventory_2_outlined, size: 16)),
                ButtonSegment(value: 'in', label: Text('In'), icon: Icon(Icons.south_west_rounded, size: 16)),
                ButtonSegment(value: 'out', label: Text('Out'), icon: Icon(Icons.north_east_rounded, size: 16)),
              ],
              selected: {_view},
              onSelectionChanged: (s) {
                setState(() => _view = s.first);
                _load();
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const CenteredScrollLoader()
                  : _error != null
                      ? ListView(
                          padding: AppTheme.formPadding,
                          children: [ErrorBanner(message: _error!, onRetry: _load)],
                        )
                      : _items.isEmpty
                          ? EmptyListBody(message: 'No inventory rows')
                          : ListView.builder(
                              padding: AppTheme.pagePadding,
                              itemCount: _items.length,
                              itemBuilder: (context, i) {
                                final row = _items[i];
                                final title = labelOf(row['item'] ?? row['item_id'] ?? row);
                                final balance = '${row['balance'] ?? row['available_qty'] ?? row['remaining_qty'] ?? ''}';
                                final subtitle = _view == 'stats'
                                    ? 'In ${row['in_qty'] ?? row['qty_in'] ?? '—'} · Out ${row['out_qty'] ?? row['qty_out'] ?? '—'}'
                                    : [
                                        if (row['vendor'] != null) labelOf(row['vendor']),
                                        '${row['quantity'] ?? row['qty'] ?? ''}',
                                      ].where((s) => s.toString().trim().isNotEmpty).join(' · ');
                                return ModernListCard(
                                  title: title,
                                  subtitle: subtitle.isEmpty ? null : subtitle,
                                  icon: _view == 'in'
                                      ? Icons.south_west_rounded
                                      : _view == 'out'
                                          ? Icons.north_east_rounded
                                          : Icons.inventory_2_rounded,
                                  color: AppTheme.colorAt(i),
                                  trailing: balance.isEmpty
                                      ? null
                                      : Text(
                                          balance,
                                          style: AppTheme.titleSmall.copyWith(color: AppTheme.brand),
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

class ImrListScreen extends StatefulWidget {
  const ImrListScreen({super.key});

  @override
  State<ImrListScreen> createState() => _ImrListScreenState();
}

class _ImrListScreenState extends State<ImrListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final res = await context.read<AppServices>().inventory.listImr({'page': 1, 'limit': 30});
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
      appBar: AppBar(title: const Text('Issued material'), actions: const [WorkspaceSwitcherButton()]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/inventory/imr/new'),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const CenteredScrollLoader()
            : _error != null
                ? ListView(padding: AppTheme.formPadding, children: [ErrorBanner(message: _error!, onRetry: _load)])
                : _items.isEmpty
                    ? EmptyListBody(message: 'No issue slips')
                    : ListView.separated(
                        padding: AppTheme.formPadding,
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final row = _items[i];
                          return Card(
                            child: ListTile(
                              title: Text(row['issueSlip_number']?.toString() ?? 'Slip'),
                              subtitle: Text('${labelOf(row['site_id'] ?? row['site'])} · ${row['type'] ?? ''}'),
                              trailing: Text(formatDate(row['issue_Date'])),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class ImrCreateScreen extends StatefulWidget {
  const ImrCreateScreen({super.key});

  @override
  State<ImrCreateScreen> createState() => _ImrCreateScreenState();
}

class _ImrCreateScreenState extends State<ImrCreateScreen> {
  String? _siteId;
  String _siteLabel = '';
  String _type = 'non-returnable';
  String _inventoryType = 'Project BOQ';
  String? _authorizedBy;
  String _authLabel = '';
  String? _receivedBy;
  String _recvLabel = '';
  String _slip = '';
  final _wo = TextEditingController();
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _catalog = [];
  String? _itemId;
  String _itemLabel = '';
  final _qty = TextEditingController(text: '1');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = context.read<SettingsApis>();
      final sites = await s.sites.list({'limit': 100});
      final users = await s.users.list({'limit': 100});
      final items = await s.items.list({'limit': 100});
      if (!mounted) return;
      setState(() {
        _sites = sites.items;
        _users = users.items;
        _catalog = items.items;
      });
    });
  }

  @override
  void dispose() {
    _wo.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_siteId == null || _authorizedBy == null || _receivedBy == null || _itemId == null) {
      showPmsSnack(context, 'Site, users and item are required', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppServices>().inventory.createImr({
        'site_id': _siteId,
        'issueSlip_number': _slip,
        'type': _type,
        'inventoryType': _inventoryType,
        'issue_Date': DateTime.now().toIso8601String().substring(0, 10),
        'authorizedBy': _authorizedBy,
        'receivedBy': _receivedBy,
        'receivedByName': _recvLabel,
        'wo_number': _wo.text.trim(),
        'items': [
          {
            'item_id': _itemId,
            'issued_Qty': num.tryParse(_qty.text) ?? 1,
          }
        ],
      });
      if (!mounted) return;
      showPmsSnack(context, 'Issue slip created');
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
      appBar: AppBar(title: const Text('Issue material')),
      body: ListView(
        padding: AppTheme.formPadding,
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
              try {
                final n = await context.read<AppServices>().inventory.nextSlipNumber(p.value);
                if (!mounted) return;
                setState(() => _slip = '${n['issueSlip_number'] ?? n['number'] ?? n['next'] ?? ''}');
              } catch (_) {}
            },
          ),
          const SizedBox(height: 8),
          Text('Slip: ${_slip.isEmpty ? '—' : _slip}', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: 'non-returnable', child: Text('Non-returnable')),
              DropdownMenuItem(value: 'returnable', child: Text('Returnable')),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _inventoryType,
            decoration: const InputDecoration(labelText: 'Inventory type'),
            items: const [
              DropdownMenuItem(value: 'Project BOQ', child: Text('Project BOQ')),
              DropdownMenuItem(value: 'Site Establishment', child: Text('Site Establishment')),
              DropdownMenuItem(value: 'Assets', child: Text('Assets')),
            ],
            onChanged: (v) => setState(() => _inventoryType = v ?? _inventoryType),
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Authorized by',
            required: true,
            valueLabel: _authLabel,
            onTap: () async {
              final p = await showOptionPicker(
                context,
                title: 'Authorized by',
                options: mapToOptions(_users),
                selected: _authorizedBy,
              );
              if (p == null) return;
              setState(() {
                _authorizedBy = p.value;
                _authLabel = p.label;
              });
            },
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Received by',
            required: true,
            valueLabel: _recvLabel,
            onTap: () async {
              final p = await showOptionPicker(
                context,
                title: 'Received by',
                options: mapToOptions(_users),
                selected: _receivedBy,
              );
              if (p == null) return;
              setState(() {
                _receivedBy = p.value;
                _recvLabel = p.label;
              });
            },
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Item',
            required: true,
            valueLabel: _itemLabel,
            onTap: () async {
              final p = await showOptionPicker(
                context,
                title: 'Item',
                options: mapToOptions(_catalog, labelOfRow: (r) => r['item_name']?.toString() ?? labelOf(r)),
                selected: _itemId,
              );
              if (p == null) return;
              setState(() {
                _itemId = p.value;
                _itemLabel = p.label;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(controller: _qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty')),
          const SizedBox(height: 12),
          TextField(controller: _wo, decoration: const InputDecoration(labelText: 'WO number')),
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Create slip')),
        ],
      ),
    );
  }
}

class TransferListScreen extends StatefulWidget {
  const TransferListScreen({super.key});

  @override
  State<TransferListScreen> createState() => _TransferListScreenState();
}

class _TransferListScreenState extends State<TransferListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final res = await context.read<AppServices>().inventory.listTransfers({'page': 1, 'limit': 30});
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
      appBar: AppBar(title: const Text('Intersite transfers'), actions: const [WorkspaceSwitcherButton()]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/inventory/transfers/new'),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const CenteredScrollLoader()
            : _error != null
                ? ListView(padding: AppTheme.formPadding, children: [ErrorBanner(message: _error!, onRetry: _load)])
                : _items.isEmpty
                    ? EmptyListBody(message: 'No transfers')
                    : ListView.separated(
                        padding: AppTheme.formPadding,
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final row = _items[i];
                          return Card(
                            child: ListTile(
                              title: Text(row['transfer_number']?.toString() ?? 'Transfer'),
                              subtitle: Text(
                                '${labelOf(row['origin_site'])} → ${labelOf(row['destination_site'])}',
                              ),
                              trailing: StatusChip(status: row['status']?.toString()),
                              onTap: () => context.push('/inventory/transfers/${idOf(row)}'),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class TransferDetailScreen extends StatefulWidget {
  const TransferDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<TransferDetailScreen> createState() => _TransferDetailScreenState();
}

class _TransferDetailScreenState extends State<TransferDetailScreen> {
  Map<String, dynamic>? _doc;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final doc = await context.read<AppServices>().inventory.getTransfer(widget.id);
      if (!mounted) return;
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

  Future<void> _dispatch() async {
    try {
      await context.read<AppServices>().inventory.dispatchTransfer(widget.id, {
        'vehicle': {'vehicle_number': '', 'driver_name': ''},
      });
      showPmsSnack(context, 'Dispatched');
      _load();
    } on ApiException catch (e) {
      showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _receive() async {
    try {
      await context.read<AppServices>().inventory.receiveTransfer(widget.id, {});
      showPmsSnack(context, 'Received');
      _load();
    } on ApiException catch (e) {
      showPmsSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      appBar: AppBar(title: Text(doc?['transfer_number']?.toString() ?? 'Transfer')),
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
                    StatusChip(status: doc?['status']?.toString()),
                    const SizedBox(height: 8),
                    Text('${labelOf(doc?['origin_site'])} → ${labelOf(doc?['destination_site'])}'),
                    Text('Type: ${doc?['inventoryType'] ?? ''}'),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(onPressed: _dispatch, child: const Text('Dispatch')),
                        OutlinedButton(onPressed: _receive, child: const Text('Receive')),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class TransferCreateScreen extends StatefulWidget {
  const TransferCreateScreen({super.key});

  @override
  State<TransferCreateScreen> createState() => _TransferCreateScreenState();
}

class _TransferCreateScreenState extends State<TransferCreateScreen> {
  String? _origin;
  String _originLabel = '';
  String? _dest;
  String _destLabel = '';
  String _type = 'Project BOQ';
  String? _itemId;
  String _itemLabel = '';
  final _qty = TextEditingController(text: '1');
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _catalog = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = context.read<SettingsApis>();
      final sites = await s.sites.list({'limit': 100});
      final items = await s.items.list({'limit': 100});
      if (!mounted) return;
      setState(() {
        _sites = sites.items;
        _catalog = items.items;
      });
    });
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_origin == null || _dest == null || _itemId == null) {
      showPmsSnack(context, 'Origin, destination and item are required', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppServices>().inventory.createTransfer({
        'origin_site': _origin,
        'destination_site': _dest,
        'inventoryType': _type,
        'items': [
          {
            'item_id': _itemId,
            'requested_quantity': num.tryParse(_qty.text) ?? 1,
          }
        ],
      });
      if (!mounted) return;
      showPmsSnack(context, 'Transfer created');
      context.pop();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final opts = mapToOptions(_sites, labelOfRow: (r) => r['site_name']?.toString() ?? labelOf(r));
    return Scaffold(
      appBar: AppBar(title: const Text('New transfer')),
      body: ListView(
        padding: AppTheme.formPadding,
        children: [
          PickerField(
            label: 'Origin',
            required: true,
            valueLabel: _originLabel,
            onTap: () async {
              final p = await showOptionPicker(context, title: 'Origin', options: opts, selected: _origin);
              if (p == null) return;
              setState(() {
                _origin = p.value;
                _originLabel = p.label;
              });
            },
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Destination',
            required: true,
            valueLabel: _destLabel,
            onTap: () async {
              final p = await showOptionPicker(context, title: 'Destination', options: opts, selected: _dest);
              if (p == null) return;
              setState(() {
                _dest = p.value;
                _destLabel = p.label;
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Inventory type'),
            items: const [
              DropdownMenuItem(value: 'Project BOQ', child: Text('Project BOQ')),
              DropdownMenuItem(value: 'Site Establishment', child: Text('Site Establishment')),
              DropdownMenuItem(value: 'Assets', child: Text('Assets')),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Item',
            required: true,
            valueLabel: _itemLabel,
            onTap: () async {
              final p = await showOptionPicker(
                context,
                title: 'Item',
                options: mapToOptions(_catalog, labelOfRow: (r) => r['item_name']?.toString() ?? labelOf(r)),
                selected: _itemId,
              );
              if (p == null) return;
              setState(() {
                _itemId = p.value;
                _itemLabel = p.label;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(controller: _qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty')),
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Create transfer')),
        ],
      ),
    );
  }
}

class ScrapListScreen extends StatefulWidget {
  const ScrapListScreen({super.key});

  @override
  State<ScrapListScreen> createState() => _ScrapListScreenState();
}

class _ScrapListScreenState extends State<ScrapListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final res = await context.read<AppServices>().inventory.listScrap({'page': 1, 'limit': 30});
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
      appBar: AppBar(title: const Text('Scrap'), actions: const [WorkspaceSwitcherButton()]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/inventory/scrap/new'),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const CenteredScrollLoader()
            : _error != null
                ? ListView(padding: AppTheme.formPadding, children: [ErrorBanner(message: _error!, onRetry: _load)])
                : _items.isEmpty
                    ? EmptyListBody(message: 'No scrap records')
                    : ListView.separated(
                        padding: AppTheme.formPadding,
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final row = _items[i];
                          return Card(
                            child: ListTile(
                              title: Text(row['scrap_number']?.toString() ?? 'Scrap'),
                              subtitle: Text(labelOf(row['site_id'] ?? row['site'])),
                              trailing: StatusChip(status: row['status']?.toString()),
                              onTap: () => context.push('/inventory/scrap/${idOf(row)}'),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class ScrapDetailScreen extends StatefulWidget {
  const ScrapDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<ScrapDetailScreen> createState() => _ScrapDetailScreenState();
}

class _ScrapDetailScreenState extends State<ScrapDetailScreen> {
  Map<String, dynamic>? _doc;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final doc = await context.read<AppServices>().inventory.getScrap(widget.id);
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      appBar: AppBar(title: Text(doc?['scrap_number']?.toString() ?? 'Scrap')),
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
                    StatusChip(status: doc?['status']?.toString()),
                    const SizedBox(height: 8),
                    Text('Site: ${labelOf(doc?['site_id'] ?? doc?['site'])}'),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () async {
                            try {
                              await context.read<AppServices>().inventory.approveScrap(
                                    widget.id,
                                    {'status': 'Approved'},
                                  );
                              showPmsSnack(context, 'Approved');
                              _load();
                            } on ApiException catch (e) {
                              showPmsSnack(context, e.message, error: true);
                            }
                          },
                          child: const Text('Approve'),
                        ),
                        OutlinedButton(
                          onPressed: () async {
                            try {
                              await context.read<AppServices>().inventory.closeScrap(widget.id);
                              showPmsSnack(context, 'Closed');
                              _load();
                            } on ApiException catch (e) {
                              showPmsSnack(context, e.message, error: true);
                            }
                          },
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class ScrapCreateScreen extends StatefulWidget {
  const ScrapCreateScreen({super.key});

  @override
  State<ScrapCreateScreen> createState() => _ScrapCreateScreenState();
}

class _ScrapCreateScreenState extends State<ScrapCreateScreen> {
  String? _siteId;
  String _siteLabel = '';
  String _type = 'Project BOQ';
  String _number = '';
  String? _itemId;
  String _itemLabel = '';
  final _qty = TextEditingController(text: '1');
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _catalog = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = context.read<SettingsApis>();
      final sites = await s.sites.list({'limit': 100});
      final items = await s.items.list({'limit': 100});
      if (!mounted) return;
      setState(() {
        _sites = sites.items;
        _catalog = items.items;
      });
    });
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_siteId == null || _itemId == null || _number.isEmpty) {
      showPmsSnack(context, 'Site, scrap number and item are required', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppServices>().inventory.createScrap({
        'site_id': _siteId,
        'scrap_number': _number,
        'inventoryType': _type,
        'items': [
          {
            'item_id': _itemId,
            'requested_quantity': num.tryParse(_qty.text) ?? 1,
          }
        ],
      });
      if (!mounted) return;
      showPmsSnack(context, 'Scrap created');
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
      appBar: AppBar(title: const Text('New scrap')),
      body: ListView(
        padding: AppTheme.formPadding,
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
              try {
                final n = await context.read<AppServices>().inventory.nextScrapNumber(p.value);
                if (!mounted) return;
                setState(() => _number = '${n['scrap_number'] ?? n['number'] ?? n['next'] ?? ''}');
              } catch (_) {}
            },
          ),
          const SizedBox(height: 8),
          Text('Number: ${_number.isEmpty ? '—' : _number}'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Inventory type'),
            items: const [
              DropdownMenuItem(value: 'Project BOQ', child: Text('Project BOQ')),
              DropdownMenuItem(value: 'Site Establishment', child: Text('Site Establishment')),
              DropdownMenuItem(value: 'Assets', child: Text('Assets')),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Item',
            required: true,
            valueLabel: _itemLabel,
            onTap: () async {
              final p = await showOptionPicker(
                context,
                title: 'Item',
                options: mapToOptions(_catalog, labelOfRow: (r) => r['item_name']?.toString() ?? labelOf(r)),
                selected: _itemId,
              );
              if (p == null) return;
              setState(() {
                _itemId = p.value;
                _itemLabel = p.label;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(controller: _qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty')),
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Create scrap')),
        ],
      ),
    );
  }
}
