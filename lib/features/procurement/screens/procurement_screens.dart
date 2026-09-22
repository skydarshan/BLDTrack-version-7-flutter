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

class ProcurementHomeScreen extends StatefulWidget {
  const ProcurementHomeScreen({super.key});

  @override
  State<ProcurementHomeScreen> createState() => _ProcurementHomeScreenState();
}

class _ProcurementHomeScreenState extends State<ProcurementHomeScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _overview = {};

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
      final overview = await context.read<AppServices>().pms.dashboard.overview();
      if (!mounted) return;
      setState(() {
        _overview = overview;
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
    final remaining = _overview['remainingInventory'] is Map
        ? Map<String, dynamic>.from(_overview['remainingInventory'] as Map)
        : <String, dynamic>{};
    final sites = _overview['activeSites'] is Map
        ? Map<String, dynamic>.from(_overview['activeSites'] as Map)
        : <String, dynamic>{};
    final pending = _overview['itemsYetToBeReceived'] is Map
        ? Map<String, dynamic>.from(_overview['itemsYetToBeReceived'] as Map)
        : <String, dynamic>{};
    final prs = _overview['totalPurchaseRequests'] is Map
        ? Map<String, dynamic>.from(_overview['totalPurchaseRequests'] as Map)
        : <String, dynamic>{};

    final pendingPrs = prs['pendingCount'] ?? prs['pending_count'] ?? 0;
    final pendingLines = pending['pendingLineItems'] ?? pending['pending_count'] ?? pending['count'];

    return Scaffold(
      extendBody: true,
      appBar: const ModernAppBar(
        title: 'Procurement',
        actions: [WorkspaceSwitcherButton()],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : ListView(
                padding: AppTheme.pagePadding,
                children: [
                  if (_error != null) ...[
                    ErrorBanner(message: _error!, onRetry: _load),
                    const SizedBox(height: 12),
                  ],
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.45,
                    children: [
                      BentoStatCard(
                        label: 'Inventory value',
                        value: '${remaining['valueFormatted'] ?? remaining['value'] ?? 0}',
                        icon: Icons.inventory_2_rounded,
                        color: AppTheme.accent,
                      ),
                      BentoStatCard(
                        label: 'Active sites',
                        value: '${sites['count'] ?? 0}',
                        icon: Icons.place_rounded,
                        color: AppTheme.info,
                      ),
                      BentoStatCard(
                        label: 'Yet to receive',
                        value: '${pending['valueFormatted'] ?? pending['value'] ?? 0}',
                        hint: pendingLines != null ? '$pendingLines pending lines' : null,
                        icon: Icons.local_shipping_rounded,
                        color: AppTheme.orange,
                        onTap: () => context.go('/dmr/status'),
                      ),
                      BentoStatCard(
                        label: 'Purchase requests',
                        value: '${prs['count'] ?? 0}',
                        hint: '$pendingPrs pending',
                        icon: Icons.description_rounded,
                        color: AppTheme.brand,
                        highlight: (pendingPrs is num ? pendingPrs > 0 : '$pendingPrs' != '0'),
                        onTap: () => context.go('/procurement/rr'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SectionHeader(title: 'Quick actions', color: AppTheme.brand),
                  const SizedBox(height: 4),
                  ModernListCard(
                    title: 'New requisition',
                    subtitle: 'Raise an RR',
                    icon: Icons.add_box_rounded,
                    color: AppTheme.brand,
                    onTap: () => context.push('/procurement/rr/new'),
                  ),
                  ModernListCard(
                    title: 'Approvals',
                    subtitle: 'Review pending PRs',
                    icon: Icons.verified_rounded,
                    color: AppTheme.success,
                    onTap: () => context.go('/procurement/approvals'),
                  ),
                  ModernListCard(
                    title: 'Purchase orders',
                    subtitle: 'Open orders',
                    icon: Icons.shopping_bag_rounded,
                    color: AppTheme.info,
                    onTap: () => context.go('/procurement/po'),
                  ),
                ],
              ),
      ),
    );
  }
}

class RrListScreen extends StatefulWidget {
  const RrListScreen({super.key, this.status});
  final String? status;

  @override
  State<RrListScreen> createState() => _RrListScreenState();
}

class _RrListScreenState extends State<RrListScreen> {
  String _tab = 'all';
  String _search = '';
  int _page = 1;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _pagination;
  Map<String, dynamic> _counts = {};

  @override
  void initState() {
    super.initState();
    _tab = widget.status ?? 'all';
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AppServices>().rr;
      final params = {
        'page': _page,
        'limit': 20,
        if (_search.isNotEmpty) 'search': _search,
        if (_tab != 'all') 'status': _tab,
      };
      final results = await Future.wait([
        api.list(params),
        api.statusCounts(),
      ]);
      if (!mounted) return;
      final list = results[0] as PaginatedResult;
      setState(() {
        _items = list.items;
        _pagination = list.pagination;
        _counts = results[1] as Map<String, dynamic>;
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
    final counts = _counts['statusCounts'] is Map
        ? Map<String, dynamic>.from(_counts['statusCounts'] as Map)
        : _counts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Requisitions'),
        actions: const [WorkspaceSwitcherButton()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/procurement/rr/new'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppTheme.searchPadding,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search PR / title…',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (v) {
                setState(() {
                  _search = v.trim();
                  _page = 1;
                });
                _load();
              },
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: AppTheme.chipRowPadding,
            child: Row(
              children: [
                for (final t in ['all', 'pending', 'revise', 'approved', 'revised', 'rejected'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        t == 'all' ? 'All (${_counts['total'] ?? ''})' : '$t (${counts[t] ?? ''})',
                      ),
                      selected: _tab == t,
                      onSelected: (_) {
                        setState(() {
                          _tab = t;
                          _page = 1;
                        });
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ErrorBanner(message: _error!, onRetry: _load),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? ListView(
                      children: const [SizedBox(height: 80), Center(child: CircularProgressIndicator())],
                    )
                  : _items.isEmpty
                      ? ListView(children: const [EmptyState(message: 'No requisitions')])
                      : ListView.separated(
                          padding: AppTheme.listPadding,
                          itemCount: _items.length + 1,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            if (i == _items.length) {
                              final pages = paginationTotalPages(_pagination);
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: _page > 1
                                        ? () {
                                            setState(() => _page -= 1);
                                            _load();
                                          }
                                        : null,
                                    child: const Text('Prev'),
                                  ),
                                  Text('$_page / $pages'),
                                  TextButton(
                                    onPressed: _page < pages
                                        ? () {
                                            setState(() => _page += 1);
                                            _load();
                                          }
                                        : null,
                                    child: const Text('Next'),
                                  ),
                                ],
                              );
                            }
                            final row = _items[i];
                            return Card(
                              child: ListTile(
                                title: Text(row['title']?.toString() ?? 'RR'),
                                subtitle: Text(
                                  '${row['requisition_request_number'] ?? ''} · ${labelOf(row['site'])}',
                                ),
                                trailing: StatusChip(status: row['status']?.toString()),
                                onTap: () => context.push('/procurement/rr/${idOf(row)}'),
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

class RrDetailScreen extends StatefulWidget {
  const RrDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<RrDetailScreen> createState() => _RrDetailScreenState();
}

class _RrDetailScreenState extends State<RrDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _doc;

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
      final doc = await context.read<AppServices>().rr.getDetail(widget.id);
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

  Future<void> _setStatus(String status) async {
    try {
      await context.read<AppServices>().rr.updateStatus(widget.id, {'status': status});
      showPmsSnack(context, 'Updated to $status');
      _load();
    } on ApiException catch (e) {
      showPmsSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final items = doc?['items'] is List
        ? (doc!['items'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    return Scaffold(
      appBar: AppBar(title: Text(doc?['title']?.toString() ?? 'Requisition')),
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
                    Row(
                      children: [
                        StatusChip(status: doc?['status']?.toString()),
                        const Spacer(),
                        Text('PR ${doc?['requisition_request_number'] ?? ''}'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Site: ${labelOf(doc?['site'])}'),
                    Text('Type: ${doc?['prType'] ?? '—'}'),
                    Text('Date: ${formatDate(doc?['date'])}'),
                    Text('Expected: ${formatDate(doc?['expected_delivery_date'])}'),
                    if ((doc?['remarks'] ?? '').toString().isNotEmpty)
                      Text('Remarks: ${doc?['remarks']}'),
                    const Divider(height: 32),
                    const Text('Items', style: TextStyle(fontWeight: FontWeight.w700)),
                    for (final item in items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(labelOf(item['item_id'] ?? item['item'])),
                        subtitle: Text(
                          'Qty ${item['qty'] ?? 0} · Rate ${item['rate'] ?? 0} · GST ${item['gst'] ?? 0}',
                        ),
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () => _setStatus('approved'),
                          child: const Text('Approve'),
                        ),
                        OutlinedButton(
                          onPressed: () => _setStatus('revise'),
                          child: const Text('Revise'),
                        ),
                        OutlinedButton(
                          onPressed: () => _setStatus('rejected'),
                          child: const Text('Reject'),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class RrCreateScreen extends StatefulWidget {
  const RrCreateScreen({super.key});

  @override
  State<RrCreateScreen> createState() => _RrCreateScreenState();
}

class _RrCreateScreenState extends State<RrCreateScreen> {
  final _title = TextEditingController();
  final _remarks = TextEditingController();
  String _prType = 'Project BOQ';
  String? _siteId;
  String _siteLabel = '';
  String _localPurchase = 'no';
  DateTime _date = DateTime.now();
  DateTime _expected = DateTime.now().add(const Duration(days: 7));
  dynamic _nextNumber;
  bool _saving = false;
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _catalogItems = [];
  final List<_RrLine> _lines = [_RrLine()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _title.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final settings = context.read<SettingsApis>();
    final sites = await settings.sites.list({'limit': 100, 'sortBy': 'site_name'});
    final items = await settings.items.list({'limit': 100, 'sortBy': 'item_name'});
    if (!mounted) return;
    setState(() {
      _sites = sites.items;
      _catalogItems = items.items;
    });
  }

  Future<void> _pickSite() async {
    final picked = await showOptionPicker(
      context,
      title: 'Site',
      options: mapToOptions(_sites, labelOfRow: (r) => r['site_name']?.toString() ?? labelOf(r)),
      selected: _siteId,
    );
    if (picked == null) return;
    setState(() {
      _siteId = picked.value;
      _siteLabel = picked.label;
    });
    try {
      final n = await context.read<AppServices>().rr.getNextNumber(picked.value);
      if (!mounted) return;
      setState(() => _nextNumber = n);
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _siteId == null) {
      showPmsSnack(context, 'Title and site are required', error: true);
      return;
    }
    final items = _lines
        .where((l) => l.itemId != null)
        .map(
          (l) => {
            'item_id': l.itemId,
            'qty': num.tryParse(l.qty.text) ?? 1,
            'rate': num.tryParse(l.rate.text) ?? 0,
            'gst': num.tryParse(l.gst.text) ?? 0,
            'remark': l.remark.text.trim(),
          },
        )
        .toList();
    setState(() => _saving = true);
    try {
      await context.read<AppServices>().rr.create({
        'title': _title.text.trim(),
        'prType': _prType,
        'date': _date.toIso8601String(),
        'expected_delivery_date': _expected.toIso8601String(),
        'requisition_request_number': _nextNumber is num
            ? _nextNumber
            : int.tryParse('$_nextNumber') ?? _nextNumber,
        'site': _siteId,
        'local_purchase': _localPurchase,
        'remarks': _remarks.text.trim(),
        'items': items,
      });
      if (!mounted) return;
      showPmsSnack(context, 'Requisition created');
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
      appBar: AppBar(title: const Text('New requisition')),
      body: ListView(
        padding: AppTheme.formPadding,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title *'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _prType,
            decoration: const InputDecoration(labelText: 'PR type'),
            items: const [
              DropdownMenuItem(value: 'Project BOQ', child: Text('Project BOQ')),
              DropdownMenuItem(value: 'Site Establishment', child: Text('Site Establishment')),
              DropdownMenuItem(value: 'Assets', child: Text('Assets')),
            ],
            onChanged: (v) => setState(() => _prType = v ?? _prType),
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Site',
            required: true,
            valueLabel: _siteLabel,
            onTap: _pickSite,
          ),
          const SizedBox(height: 8),
          Text('Next PR number: ${_nextNumber ?? '—'}', style: const TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Date ${formatDate(_date.toIso8601String())}'),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _date = d);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Expected ${formatDate(_expected.toIso8601String())}'),
            trailing: const Icon(Icons.event_outlined),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _expected,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _expected = d);
            },
          ),
          DropdownButtonFormField<String>(
            initialValue: _localPurchase,
            decoration: const InputDecoration(labelText: 'Local purchase'),
            items: const [
              DropdownMenuItem(value: 'no', child: Text('No')),
              DropdownMenuItem(value: 'yes', child: Text('Yes')),
            ],
            onChanged: (v) => setState(() => _localPurchase = v ?? 'no'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remarks,
            decoration: const InputDecoration(labelText: 'Remarks'),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Items', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _lines.add(_RrLine())),
                child: const Text('Add line'),
              ),
            ],
          ),
          for (var i = 0; i < _lines.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    PickerField(
                      label: 'Item',
                      valueLabel: _lines[i].itemLabel,
                      onTap: () async {
                        final picked = await showOptionPicker(
                          context,
                          title: 'Item',
                          options: mapToOptions(
                            _catalogItems,
                            labelOfRow: (r) => r['item_name']?.toString() ?? labelOf(r),
                          ),
                          selected: _lines[i].itemId,
                        );
                        if (picked == null) return;
                        setState(() {
                          _lines[i].itemId = picked.value;
                          _lines[i].itemLabel = picked.label;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _lines[i].qty,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Qty'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _lines[i].rate,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Rate'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _lines[i].gst,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'GST'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Create requisition'),
          ),
        ],
      ),
    );
  }
}

class _RrLine {
  String? itemId;
  String itemLabel = '';
  final qty = TextEditingController(text: '1');
  final rate = TextEditingController(text: '0');
  final gst = TextEditingController(text: '0');
  final remark = TextEditingController();
}

class RrApprovalsScreen extends StatefulWidget {
  const RrApprovalsScreen({super.key});

  @override
  State<RrApprovalsScreen> createState() => _RrApprovalsScreenState();
}

class _RrApprovalsScreenState extends State<RrApprovalsScreen> {
  int _step = 1;
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
      final api = context.read<AppServices>().rr;
      final res = _step == 1 ? await api.pendingFirst() : await api.pendingSecond();
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
        title: const Text('RR Approvals'),
        actions: const [WorkspaceSwitcherButton()],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppTheme.filterPadding,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Step 1')),
                ButtonSegment(value: 2, label: Text('Step 2')),
              ],
              selected: {_step},
              onSelectionChanged: (s) {
                setState(() => _step = s.first);
                _load();
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ErrorBanner(message: _error!, onRetry: _load),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? ListView(
                      children: const [SizedBox(height: 80), Center(child: CircularProgressIndicator())],
                    )
                  : _items.isEmpty
                      ? ListView(children: const [EmptyState(message: 'No pending approvals')])
                      : ListView.separated(
                          padding: AppTheme.formPadding,
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final row = _items[i];
                            return Card(
                              child: ListTile(
                                title: Text(row['title']?.toString() ?? 'RR'),
                                subtitle: Text('${row['requisition_request_number'] ?? ''}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push('/procurement/rr/${idOf(row)}'),
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
