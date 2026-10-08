import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/form_validation_helpers.dart';
import '../../../core/utils/list_query.dart';
import '../../../core/theme/modern_widgets.dart';
import '../../app/app_services.dart';
import '../../app/app_shell.dart';
import '../../auth/providers/auth_provider.dart';
import '../../pms/utils/site_options.dart';
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
                                final title = itemLabel(row);
                                final balance =
                                    '${firstNonNull(row, ['remaining_quantity', 'remaining_qty', 'available_qty', 'balance']) ?? ''}';
                                final subtitle = _view == 'stats'
                                    ? 'In ${firstNonNull(row, ['inventory_in_quantity', 'in_qty', 'qty_in']) ?? '—'} · Remaining ${firstNonNull(row, ['remaining_quantity', 'remaining_qty']) ?? '—'}'
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
  Map<String, dynamic>? _pagination;
  List<Map<String, dynamic>> _sites = [];
  String _inventoryType = '';
  String? _siteId;
  String _siteLabel = '';
  DateTime? _date;
  String _draftType = '';
  String? _draftSiteId;
  String _draftSiteLabel = '';
  DateTime? _draftDate;
  int _page = 1;

  bool get _hasFilters => _inventoryType.isNotEmpty || _siteId != null || _date != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadSites();
      if (mounted) await _load();
    });
  }

  Future<void> _loadSites() async {
    try {
      final rows = await context.read<SettingsApis>().sites.listAll({
        'sortBy': 'site_name',
        'sortOrder': 'asc',
      });
      if (!mounted) return;
      setState(() => _sites = rows);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final issueDate = isoDateOnly(_date);
    final issueDateTo = issueDate == null ? null : '$issueDate~';
    try {
      final res = await context.read<AppServices>().inventory.listImr({
        'page': _page,
        'limit': 20,
        if (_inventoryType.isNotEmpty) 'inventoryType': _inventoryType,
        'site_id': ?_siteId,
        'issue_Date_from': ?issueDate,
        'issue_Date_to': ?issueDateTo,
      });
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _pagination = res.pagination;
        _loading = false;
      });
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

  void _applyFilters() {
    setState(() {
      _inventoryType = _draftType;
      _siteId = _draftSiteId;
      _siteLabel = _draftSiteLabel;
      _date = _draftDate;
      _page = 1;
    });
    _load();
  }

  void _resetFilters() {
    setState(() {
      _inventoryType = '';
      _siteId = null;
      _siteLabel = '';
      _date = null;
      _draftType = '';
      _draftSiteId = null;
      _draftSiteLabel = '';
      _draftDate = null;
      _page = 1;
    });
    _load();
  }

  Future<void> _openFilters() async {
    _draftType = _inventoryType;
    _draftSiteId = _siteId;
    _draftSiteLabel = _siteLabel;
    _draftDate = _date;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              return SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey('imr-type-$_draftType'),
                        initialValue: _draftType,
                        decoration: const InputDecoration(labelText: 'Inventory type'),
                        items: const [
                          DropdownMenuItem(value: '', child: Text('All inventory types')),
                          DropdownMenuItem(value: 'Project BOQ', child: Text('Project BOQ')),
                          DropdownMenuItem(value: 'Site Establishment', child: Text('Site Establishment')),
                          DropdownMenuItem(value: 'Assets', child: Text('Assets')),
                        ],
                        onChanged: (v) => setSheet(() => _draftType = v ?? ''),
                      ),
                      const SizedBox(height: 12),
                      PickerField(
                        label: 'Select sites',
                        hint: 'All sites — search...',
                        valueLabel: _draftSiteLabel,
                        onTap: () async {
                          final picked = await showOptionPicker(
                            sheetContext,
                            title: 'Select sites',
                            options: [
                              const OptionItem(value: '', label: 'All sites'),
                              ...mapToOptions(
                                _sites,
                                labelOfRow: (r) => r['site_name']?.toString() ?? labelOf(r),
                              ),
                            ],
                            selected: _draftSiteId,
                          );
                          if (picked == null) return;
                          setSheet(() {
                            if (picked.value.isEmpty) {
                              _draftSiteId = null;
                              _draftSiteLabel = '';
                            } else {
                              _draftSiteId = picked.value;
                              _draftSiteLabel = picked.label;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Issue date'),
                      ),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: sheetContext,
                            initialDate: _draftDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked == null) return;
                          setSheet(() => _draftDate = picked);
                        },
                        icon: const Icon(Icons.calendar_today_outlined, size: 18),
                        label: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _draftDate == null ? 'DD/MM/YYYY' : formatDate(_draftDate!.toIso8601String()),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          _applyFilters();
                          Navigator.pop(sheetContext);
                        },
                        child: const Text('Apply'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () {
                          _resetFilters();
                          Navigator.pop(sheetContext);
                        },
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = paginationTotalPages(_pagination);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Issued material'),
        actions: [
          IconButton(
            tooltip: 'Filters',
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: _hasFilters,
              smallSize: 8,
              child: const Icon(Icons.filter_list),
            ),
          ),
          const WorkspaceSwitcherButton(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/inventory/imr/new'),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const CenteredScrollLoader()
            : _error != null
                ? ListView(
                    padding: AppTheme.formPadding,
                    children: [ErrorBanner(message: _error!, onRetry: _load)],
                  )
                : _items.isEmpty
                    ? EmptyListBody(
                        message: _hasFilters
                            ? 'No issued material records found.'
                            : listEmptyMessage(noun: 'issue slips'),
                      )
                    : ListView.separated(
                        padding: AppTheme.formPadding,
                        itemCount: _items.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          if (i == _items.length) {
                            return ListPaginationRow(
                              page: _page,
                              totalPages: pages,
                              onPrev: _page > 1
                                  ? () {
                                      setState(() => _page -= 1);
                                      _load();
                                    }
                                  : null,
                              onNext: _page < pages
                                  ? () {
                                      setState(() => _page += 1);
                                      _load();
                                    }
                                  : null,
                            );
                          }
                          final row = _items[i];
                          return Card(
                            child: ListTile(
                              title: Text(row['issueSlip_number']?.toString() ?? 'Slip'),
                              subtitle: Text('${labelOf(row['site_id'] ?? row['site'])} · ${row['inventoryType'] ?? row['type'] ?? ''}'),
                              trailing: Text(formatDate(row['issue_Date'])),
                              onTap: () {
                                final id = idOf(row);
                                if (id != null) context.push('/inventory/imr/$id');
                              },
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class ImrDetailScreen extends StatefulWidget {
  const ImrDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<ImrDetailScreen> createState() => _ImrDetailScreenState();
}

class _ImrDetailScreenState extends State<ImrDetailScreen> {
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
      final services = context.read<AppServices>();
      final doc = await services.inventory.getImr(widget.id);
      if (!mounted) return;
      await resolveDocItemNames(doc, services.settings.items.getById);
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
    final items = asMapList(doc?['items'] is List ? doc!['items'] as List : const []);
    return Scaffold(
      appBar: AppBar(title: Text(doc?['issueSlip_number']?.toString() ?? 'Issue slip')),
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
                    Text('Site: ${labelOf(doc?['site_id'] ?? doc?['site'])}'),
                    Text('Type: ${doc?['type'] ?? '—'}'),
                    Text('Inventory: ${doc?['inventoryType'] ?? '—'}'),
                    Text('Date: ${formatDate(doc?['issue_Date'])}'),
                    Text('Authorized by: ${labelOf(doc?['authorizedBy'])}'),
                    Text('Received by: ${doc?['receivedByName'] ?? labelOf(doc?['receivedBy'])}'),
                    const Divider(height: 32),
                    NamedItemLines(items: items),
                  ],
                ),
    );
  }
}

class _IssueLine {
  String? itemId;
  String itemLabel = '';
  String itemCode = '—';
  String uom = '—';
  num available = 0;
  final qty = TextEditingController();
  final remarks = TextEditingController();

  void dispose() {
    qty.dispose();
    remarks.dispose();
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
  String _staffName = '—';
  String _empId = '—';
  String _staffRole = '—';
  String? _receivedBy;
  String _contractorName = '—';
  String _contactPerson = '—';
  String _contractorCode = '—';
  String _slip = '';
  final _slipCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _recvName = TextEditingController();
  final _wo = TextEditingController();
  final List<_IssueLine> _lines = [_IssueLine()];
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _contractors = [];
  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _stock = [];
  bool _saving = false;
  bool _loadingStock = false;
  final _fieldErrors = FieldErrors();
  final DateTime _issueDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _dateCtrl.text = _displayDate(_issueDate);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = context.read<SettingsApis>();
      final sites = await s.sites.listAll({'sortBy': 'site_name', 'sortOrder': 'asc'});
      final staff = await s.siteStaff.listAll({'sortBy': 'name', 'sortOrder': 'asc'});
      final contractors = await s.contractors.listAll({'sortBy': 'name', 'sortOrder': 'asc'});
      final items = await s.items.listAll({'sortBy': 'item_name', 'sortOrder': 'asc'});
      if (!mounted) return;
      setState(() {
        _sites = sites;
        _staff = staff;
        _contractors = contractors;
        _catalog = items;
      });
    });
  }

  @override
  void dispose() {
    _slipCtrl.dispose();
    _dateCtrl.dispose();
    _recvName.dispose();
    _wo.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  String _displayDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd-$mm-${d.year}';
  }

  String get _issueDateIso {
    final mm = _issueDate.month.toString().padLeft(2, '0');
    final dd = _issueDate.day.toString().padLeft(2, '0');
    return '${_issueDate.year}-$mm-$dd';
  }

  bool _coversSite(Map<String, dynamic> row, String siteId) {
    final sites = row['sites'];
    if (sites is! List || sites.isEmpty) return false;
    for (final site in sites) {
      if (mongoId(site) == siteId || site.toString() == siteId) return true;
    }
    return false;
  }

  List<Map<String, dynamic>> _forSite(List<Map<String, dynamic>> rows) {
    final siteId = _siteId;
    if (siteId == null) return const [];
    final matched = rows.where((row) => _coversSite(row, siteId)).toList();
    return matched.isEmpty ? rows : matched;
  }

  String _formatIssueSlip(String siteCode, dynamic raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return '';
    if (text.contains('/')) return text;
    final n = num.tryParse(text);
    if (n == null) return text;
    final code = siteCode.trim().isEmpty ? 'SITE' : siteCode.trim();
    return '$code/${n.toInt().toString().padLeft(5, '0')}';
  }

  Map<String, dynamic>? _catalogById(String? id) {
    if (id == null) return null;
    for (final row in _catalog) {
      if (idOf(row) == id) return row;
    }
    return null;
  }

  num _availableFor(String? itemId) {
    if (itemId == null) return 0;
    for (final row in _stock) {
      final id = mongoId(row['item_id']) ?? mongoId(row['item']);
      if (id == itemId) return asNum(row['availableStock']) ?? 0;
    }
    return 0;
  }

  void _applyItem(int index, OptionItem picked) {
    final line = _lines[index];
    final item = picked.raw ?? _catalogById(picked.value);
    line.itemId = picked.value;
    line.itemLabel = picked.label;
    line.itemCode = item?['item_code']?.toString().trim().isNotEmpty == true
        ? item!['item_code'].toString()
        : '—';
    line.uom = item == null ? '—' : labelOf(item['uom'], fallback: '—');
    line.available = _availableFor(picked.value);
  }

  Future<void> _loadSlip(String siteId, String siteCode) async {
    try {
      final n = await context.read<AppServices>().inventory.nextSlipNumber(siteId);
      if (!mounted) return;
      final raw = n['next_slip_number'] ?? n['issueSlip_number'] ?? n['number'] ?? n['next'];
      final formatted = _formatIssueSlip(siteCode, raw);
      _slipCtrl.text = formatted;
      setState(() => _slip = formatted);
      if (formatted.isEmpty) {
        showPmsSnack(context, 'Could not fetch the next slip number', error: true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      _slipCtrl.text = '';
      setState(() => _slip = '');
      showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _reloadStock() async {
    if (_siteId == null) {
      setState(() => _stock = []);
      return;
    }
    setState(() => _loadingStock = true);
    try {
      final rows = await context.read<AppServices>().inventory.availableStock({
        'site_id': _siteId,
        'inventoryType': _inventoryType,
      });
      if (!mounted) return;
      setState(() {
        _stock = rows;
        _loadingStock = false;
        for (final line in _lines) {
          line.available = _availableFor(line.itemId);
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _stock = [];
        _loadingStock = false;
      });
      showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _save() async {
    _fieldErrors.clear();
    _fieldErrors.set('site', requiredSelection(_siteId, 'Site'));
    _fieldErrors.set('slip', _slip.trim().isEmpty ? 'Issue slip number is required — pick the site again' : null);
    _fieldErrors.set('authorized', requiredSelection(_authorizedBy, 'Authorized by'));
    _fieldErrors.set('received', requiredSelection(_receivedBy, 'Received by'));
    _fieldErrors.set('recvName', requiredText(_recvName.text, 'Received by name'));
    final used = _lines.where((line) => (line.itemId ?? '').isNotEmpty).toList();
    if (used.isEmpty) {
      _fieldErrors.set('items', 'Add at least one item');
    }
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      if ((line.itemId ?? '').isEmpty) continue;
      final qty = num.tryParse(line.qty.text.trim());
      if (qty == null || qty <= 0) {
        _fieldErrors.set('qty$i', 'Issued quantity is required');
      } else if (qty > line.available) {
        final name = line.itemLabel.trim().isEmpty ? 'This item' : line.itemLabel.trim();
        _fieldErrors.set('qty$i', '$name: only ${_qtyLabel(line.available)} available');
      }
    }
    if (_fieldErrors.hasErrors) {
      setState(() {});
      showPmsSnack(context, _fieldErrors.messages.first, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppServices>().inventory.createImr({
        'site_id': _siteId,
        'issueSlip_number': _slip,
        'type': _type,
        'inventoryType': _inventoryType,
        'issue_Date': _issueDateIso,
        'authorizedBy': _authorizedBy,
        'receivedBy': _receivedBy,
        'receivedByName': _recvName.text.trim(),
        'wo_number': _wo.text.trim(),
        'items': [
          for (final line in used)
            {
              'item_id': line.itemId,
              'issued_Qty': num.tryParse(line.qty.text.trim()) ?? 0,
              if (line.remarks.text.trim().isNotEmpty) 'remarks': line.remarks.text.trim(),
            },
        ],
      });
      if (!mounted) return;
      await showSavedConfirmation(context, 'Issue slip created');
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        for (final entry in apiFieldErrors(e).entries) {
          _fieldErrors.set(entry.key, entry.value);
        }
      });
      showPmsSnack(context, _withItemNames(formatApiErrorSummary(e)), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _withItemNames(String message) {
    var text = message;
    for (final line in _lines) {
      final id = line.itemId;
      if (id == null || id.isEmpty || !text.contains(id)) continue;
      final name = line.itemLabel.trim().isEmpty ? 'this item' : line.itemLabel.trim();
      text = text.replaceAll('item $id', name).replaceAll(id, name);
    }
    return text;
  }

  String _qtyLabel(num value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  Widget _infoBox(String label, String value, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value.trim().isEmpty ? '—' : value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(title: const Text('Materials Requisition / Issue Slip')),
      body: ListView(
        padding: AppTheme.formPadding,
        children: [
          if (_fieldErrors.hasErrors) ValidationSummaryBanner(messages: _fieldErrors.messages),
          PickerField(
            label: 'Site / Project Name',
            required: true,
            valueLabel: _siteLabel,
            errorText: _fieldErrors['site'],
            onTap: () async {
              final p = await showOptionPicker(
                context,
                title: 'Site / Project Name',
                options: mapToOptions(_sites, labelOfRow: (r) => r['site_name']?.toString() ?? labelOf(r)),
                selected: _siteId,
              );
              if (p == null) return;
              setState(() {
                _siteId = p.value;
                _siteLabel = p.label;
                _authorizedBy = null;
                _authLabel = '';
                _staffName = '—';
                _empId = '—';
                _staffRole = '—';
                _receivedBy = null;
                _contractorName = '—';
                _contactPerson = '—';
                _contractorCode = '—';
                _recvName.clear();
              });
              await _loadSlip(p.value, p.raw?['code']?.toString() ?? '');
              await _reloadStock();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _slipCtrl,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Issue Slip No.',
              hintText: 'Select a site',
              errorText: _fieldErrors['slip'],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dateCtrl,
            readOnly: true,
            decoration: const InputDecoration(labelText: 'Date'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('type-$_type'),
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Select type *'),
            items: const [
              DropdownMenuItem(value: 'non-returnable', child: Text('NON-RETURNABLE')),
              DropdownMenuItem(value: 'returnable', child: Text('RETURNABLE')),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('use-$_inventoryType'),
            initialValue: _inventoryType,
            decoration: const InputDecoration(labelText: 'Select Use Type *'),
            items: const [
              DropdownMenuItem(value: 'Project BOQ', child: Text('Project BOQ')),
              DropdownMenuItem(value: 'Site Establishment', child: Text('Site Establishment')),
              DropdownMenuItem(value: 'Assets', child: Text('Assets')),
            ],
            onChanged: (v) async {
              setState(() => _inventoryType = v ?? _inventoryType);
              await _reloadStock();
            },
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _lines.length; i++) ...[
            _section('Item ${i + 1}', [
              PickerField(
                label: 'Item Name',
                required: true,
                valueLabel: _lines[i].itemLabel,
                errorText: _fieldErrors['items'],
                onTap: () async {
                  final p = await showOptionPicker(
                    context,
                    title: 'Select item',
                    options: mapToOptions(
                      _catalog,
                      labelOfRow: (r) => r['item_name']?.toString() ?? labelOf(r),
                    ),
                    selected: _lines[i].itemId,
                  );
                  if (p == null) return;
                  setState(() => _applyItem(i, p));
                },
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoBox(
                    'Item Code',
                    _lines[i].itemId == null ? '—' : _lines[i].itemCode,
                    flex: 3,
                  ),
                  const SizedBox(width: 8),
                  _infoBox('UOM', _lines[i].itemId == null ? '—' : _lines[i].uom, flex: 2),
                  const SizedBox(width: 8),
                  _infoBox(
                    'Available Qty',
                    _lines[i].itemId == null
                        ? '—'
                        : (_loadingStock ? '…' : _qtyLabel(_lines[i].available)),
                    flex: 3,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _lines[i].qty,
                enabled: _lines[i].itemId != null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Issued Quantity',
                  errorText: _fieldErrors['qty$i'],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _lines[i].remarks,
                decoration: const InputDecoration(labelText: 'Remarks'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Remove item',
                  onPressed: _lines.length == 1
                      ? null
                      : () {
                          final removed = _lines.removeAt(i);
                          removed.dispose();
                          setState(() {});
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: () => setState(() => _lines.add(_IssueLine())),
            icon: const Icon(Icons.add),
            label: const Text('Add Item +'),
          ),
          const SizedBox(height: 16),
          _section('Authorized By *', [
            PickerField(
              label: 'Select authorized by',
              required: true,
              valueLabel: _authLabel,
              errorText: _fieldErrors['authorized'],
              onTap: () async {
                if (_siteId == null) {
                  showPmsSnack(context, 'Select a site first', error: true);
                  return;
                }
                final p = await showOptionPicker(
                  context,
                  title: 'Select authorized by',
                  options: mapToOptions(_forSite(_staff), labelOfRow: (r) => r['name']?.toString() ?? labelOf(r)),
                  selected: _authorizedBy,
                  emptyMessage: 'No site staff found',
                );
                if (p == null) return;
                final row = p.raw ?? const <String, dynamic>{};
                setState(() {
                  _authorizedBy = p.value;
                  _authLabel = p.label;
                  _staffName = row['name']?.toString() ?? p.label;
                  _empId = row['employeeCode']?.toString() ?? '—';
                  _staffRole = row['role']?.toString() ?? '—';
                });
              },
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoBox('Name', _authorizedBy == null ? '—' : _staffName, flex: 3),
                const SizedBox(width: 8),
                _infoBox('Emp ID', _authorizedBy == null ? '—' : _empId, flex: 2),
                const SizedBox(width: 8),
                _infoBox('Designation', _authorizedBy == null ? '—' : _staffRole, flex: 3),
              ],
            ),
          ]),
          const SizedBox(height: 12),
          _section('Received By *', [
            PickerField(
              label: 'Search contractor',
              required: true,
              valueLabel: _contractorName == '—' ? '' : _contractorName,
              errorText: _fieldErrors['received'],
              onTap: () async {
                if (_siteId == null) {
                  showPmsSnack(context, 'Select a site first', error: true);
                  return;
                }
                final p = await showOptionPicker(
                  context,
                  title: 'Search contractor',
                  options: mapToOptions(
                    _forSite(_contractors),
                    labelOfRow: (r) => r['name']?.toString() ?? labelOf(r),
                  ),
                  selected: _receivedBy,
                  emptyMessage: 'No contractors found',
                );
                if (p == null) return;
                final row = p.raw ?? const <String, dynamic>{};
                final contact = row['contact_person']?.toString().trim() ?? '';
                setState(() {
                  _receivedBy = p.value;
                  _contractorName = row['name']?.toString() ?? p.label;
                  _contactPerson = contact.isEmpty ? '—' : contact;
                  _contractorCode = row['code']?.toString().trim().isNotEmpty == true
                      ? row['code'].toString()
                      : '—';
                  if (_recvName.text.trim().isEmpty) {
                    _recvName.text = contact.isNotEmpty ? contact : _contractorName;
                  }
                });
              },
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _recvName,
                    decoration: InputDecoration(
                      labelText: 'Name *',
                      errorText: _fieldErrors['recvName'],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _wo,
                    decoration: const InputDecoration(labelText: 'WO No'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoBox('Contractor', _receivedBy == null ? '—' : _contractorName, flex: 3),
                const SizedBox(width: 8),
                _infoBox('Contact', _receivedBy == null ? '—' : _contactPerson, flex: 3),
                const SizedBox(width: 8),
                _infoBox('Code', _receivedBy == null ? '—' : _contractorCode, flex: 2),
              ],
            ),
          ]),
          const SizedBox(height: 12),
          _section('Issued By', [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoBox('Name', user?.name ?? '—', flex: 2),
                const SizedBox(width: 8),
                _infoBox('Designation', user?.displayRole ?? '—', flex: 2),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _infoBox('User ID', user?.id ?? '—'),
              ],
            ),
          ]),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Issue Material'),
            ),
          ),
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
  static const _statuses = [
    '',
    'Pending',
    'Approved',
    'Dispatched',
    'Partially Received',
    'Closed',
    'Rejected',
  ];
  static const _types = ['', 'Project BOQ', 'Site Establishment', 'Assets'];

  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _pagination;
  List<Map<String, dynamic>> _sites = [];
  String _search = '';
  String _status = '';
  String _type = '';
  String? _origin;
  String _originLabel = '';
  String? _dest;
  String _destLabel = '';
  DateTime? _from;
  DateTime? _to;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadSites();
      if (mounted) await _load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSites() async {
    try {
      final opts = await loadSiteOptions(context);
      if (!mounted) return;
      setState(() {
        _sites = [
          for (final o in opts) o.raw ?? {'_id': o.value, 'site_name': o.label},
        ];
      });
    } catch (_) {}
  }

  Map<String, dynamic> _filters() {
    return {
      if (_status.isNotEmpty) 'status': _status,
      if (_type.isNotEmpty) 'inventoryType': _type,
      if (_origin != null) 'origin_site': _origin,
      if (_dest != null) 'destination_site': _dest,
      if (isoDateOnly(_from) != null) 'created_from': isoDateOnly(_from),
      if (isoDateOnly(_to) != null) 'created_to': isoDateOnly(_to),
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final services = context.read<AppServices>();
      final q = _search.trim();
      if (q.isEmpty) {
        final res = await services.inventory.listTransfers({
          'page': _page,
          'limit': 20,
          ..._filters(),
        });
        if (!mounted) return;
        setState(() {
          _items = res.items;
          _pagination = res.pagination;
          _loading = false;
        });
        return;
      }

      var itemIds = <String>[];
      try {
        final itemRes = await services.settings.items.list({
          'search': q,
          'page': 1,
          'limit': 20,
        });
        itemIds = itemRes.items
            .map(idOf)
            .whereType<String>()
            .where((id) => id.length == 24)
            .take(8)
            .toList();
      } on ApiException {
        itemIds = const [];
      }

      final siteIds = filterSitesByKeyword(_sites, q)
          .map(idOf)
          .whereType<String>()
          .where((id) => id.length == 24)
          .take(6)
          .toList();

      final parts = await Future.wait([
        services.inventory.listTransfers({
          'page': 1,
          'limit': 50,
          'search': q,
          ..._filters(),
        }),
        services.inventory.listTransfers({
          'page': 1,
          'limit': 50,
          'transfer_number': q,
          ..._filters(),
        }),
        for (final id in itemIds)
          services.inventory.listTransfers({
            'page': 1,
            'limit': 50,
            'item_id': id,
            ..._filters(),
          }),
        for (final id in siteIds) ...[
          if (_origin == null)
            services.inventory.listTransfers({
              'page': 1,
              'limit': 50,
              'origin_site': id,
              ..._filters(),
            }),
          if (_dest == null)
            services.inventory.listTransfers({
              'page': 1,
              'limit': 50,
              'destination_site': id,
              ..._filters(),
            }),
        ],
      ]);
      if (!mounted) return;

      final seen = <String>{};
      final merged = <Map<String, dynamic>>[];
      for (final part in parts) {
        for (final row in part.items) {
          final id = idOf(row);
          if (id == null || !seen.add(id)) continue;
          merged.add(row);
        }
      }
      const pageSize = 20;
      final totalPages = merged.isEmpty ? 1 : ((merged.length + pageSize - 1) ~/ pageSize);
      final start = (_page - 1) * pageSize;
      final slice = start >= merged.length
          ? <Map<String, dynamic>>[]
          : merged.sublist(start, (start + pageSize).clamp(0, merged.length));
      setState(() {
        _items = slice;
        _pagination = {'totalPages': totalPages};
        _loading = false;
      });
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

  void _applyAndReload(VoidCallback change) {
    setState(() {
      change();
      _page = 1;
    });
    _load();
  }

  Future<void> _pickSite({required bool origin}) async {
    final picked = await showOptionPicker(
      context,
      title: origin ? 'Origin site' : 'Destination site',
      options: mapSiteRowsToOptions(_sites),
      selected: origin ? _origin : _dest,
    );
    if (picked == null) return;
    _applyAndReload(() {
      if (origin) {
        _origin = picked.value;
        _originLabel = picked.label;
      } else {
        _dest = picked.value;
        _destLabel = picked.label;
      }
    });
  }

  Future<void> _pickDate({required bool from}) async {
    final initial = (from ? _from : _to) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    _applyAndReload(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  bool get _hasExtraFilters =>
      _origin != null || _dest != null || _from != null || _to != null;

  String get _emptyFilterLabel {
    final parts = [
      if (_status.isNotEmpty) _status,
      if (_type.isNotEmpty) _type,
      if (_originLabel.isNotEmpty) _originLabel,
      if (_destLabel.isNotEmpty) _destLabel,
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final pages = paginationTotalPages(_pagination);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Intersite transfers'),
        actions: const [WorkspaceSwitcherButton()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await context.push('/inventory/transfers/new');
          if (mounted) _load();
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppTheme.searchPadding,
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search number, site or item…',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (v) => _applyAndReload(() => _search = v.trim()),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: AppTheme.chipRowPadding,
            child: Row(
              children: [
                for (final s in _statuses)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.isEmpty ? 'All' : s),
                      selected: _status == s,
                      onSelected: (_) => _applyAndReload(() => _status = s),
                    ),
                  ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                for (final t in _types)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t.isEmpty ? 'All types' : t),
                      selected: _type == t,
                      onSelected: (_) => _applyAndReload(() => _type = t),
                    ),
                  ),
                FilterChip(
                  label: Text(_origin == null ? 'Origin site' : _originLabel),
                  selected: _origin != null,
                  onSelected: (_) {
                    if (_origin != null) {
                      _applyAndReload(() {
                        _origin = null;
                        _originLabel = '';
                      });
                    } else {
                      _pickSite(origin: true);
                    }
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(_dest == null ? 'Destination site' : _destLabel),
                  selected: _dest != null,
                  onSelected: (_) {
                    if (_dest != null) {
                      _applyAndReload(() {
                        _dest = null;
                        _destLabel = '';
                      });
                    } else {
                      _pickSite(origin: false);
                    }
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(_from == null ? 'From date' : formatDate(_from!.toIso8601String())),
                  selected: _from != null,
                  onSelected: (_) {
                    if (_from != null) {
                      _applyAndReload(() => _from = null);
                    } else {
                      _pickDate(from: true);
                    }
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(_to == null ? 'To date' : formatDate(_to!.toIso8601String())),
                  selected: _to != null,
                  onSelected: (_) {
                    if (_to != null) {
                      _applyAndReload(() => _to = null);
                    } else {
                      _pickDate(from: false);
                    }
                  },
                ),
                if (_hasExtraFilters) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _applyAndReload(() {
                      _origin = null;
                      _originLabel = '';
                      _dest = null;
                      _destLabel = '';
                      _from = null;
                      _to = null;
                    }),
                    child: const Text('Clear'),
                  ),
                ],
              ],
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
                          ? EmptyListBody(
                              message: listEmptyMessage(
                                noun: 'transfers',
                                search: _search,
                                filterLabel: _emptyFilterLabel.isEmpty ? null : _emptyFilterLabel,
                              ),
                            )
                          : ListView.separated(
                              padding: AppTheme.formPadding,
                              itemCount: _items.length + 1,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                if (i == _items.length) {
                                  return ListPaginationRow(
                                    page: _page,
                                    totalPages: pages,
                                    onPrev: _page > 1
                                        ? () {
                                            setState(() => _page -= 1);
                                            _load();
                                          }
                                        : null,
                                    onNext: _page < pages
                                        ? () {
                                            setState(() => _page += 1);
                                            _load();
                                          }
                                        : null,
                                  );
                                }
                                final row = _items[i];
                                final lines = lineItemsOf(row);
                                final date = firstNonNull(row, [
                                  'dispatch_date',
                                  'createdAt',
                                  'created_at',
                                ]);
                                return Card(
                                  child: ListTile(
                                    isThreeLine: true,
                                    title: Text(row['transfer_number']?.toString() ?? 'Transfer'),
                                    subtitle: Text(
                                      [
                                        '${labelOf(row['origin_site'])} → ${labelOf(row['destination_site'])}',
                                        [
                                          if ((row['inventoryType'] ?? '').toString().isNotEmpty)
                                            row['inventoryType'],
                                          '${lines.length} item${lines.length == 1 ? '' : 's'}',
                                          if (date != null) formatDate(date),
                                        ].join(' · '),
                                      ].join('\n'),
                                    ),
                                    trailing: StatusChip(status: row['status']?.toString()),
                                    onTap: () => context.push('/inventory/transfers/${idOf(row)}'),
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
      final services = context.read<AppServices>();
      final doc = await services.inventory.getTransfer(widget.id);
      if (!mounted) return;
      await resolveDocItemNames(doc, services.settings.items.getById);
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

  Future<void> _approve() async {
    try {
      await context.read<AppServices>().inventory.updateTransferStatus(widget.id, 'Approved');
      if (!mounted) return;
      showPmsSnack(context, 'Approved');
      _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _dispatch() async {
    final doc = _doc;
    if (doc == null) return;
    final current = doc['status']?.toString();
    if (current != 'Approved') {
      showPmsSnack(context, 'Approve the transfer before dispatch', error: true);
      return;
    }
    final items = transferDispatchItems(doc);
    if (items.isEmpty) {
      showPmsSnack(context, 'Cannot dispatch — transfer items are missing', error: true);
      return;
    }
    try {
      await context.read<AppServices>().inventory.dispatchTransfer(widget.id, {
        'items': items,
        'vehicle': {
          'vehicle_number': '',
          'driver_name': '',
          'driver_contact': '',
        },
      });
      if (!mounted) return;
      showPmsSnack(context, 'Dispatched');
      _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _receive() async {
    final doc = _doc;
    if (doc == null) return;
    final items = transferReceiveItems(doc);
    if (items.isEmpty) {
      showPmsSnack(context, 'Cannot receive — no dispatched quantity left', error: true);
      return;
    }
    try {
      await context.read<AppServices>().inventory.receiveTransfer(widget.id, {
        'items': items,
      });
      if (!mounted) return;
      showPmsSnack(context, 'Received');
      _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
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
                    Text('Requested: ${formatDate(firstNonNull(doc, ['createdAt', 'created_at']))}'),
                    if ((doc?['dispatch_date'] ?? '').toString().isNotEmpty)
                      Text('Dispatched: ${formatDate(doc?['dispatch_date'])}'),
                    if ((doc?['notes'] ?? '').toString().trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Notes: ${doc?['notes']}'),
                      ),
                    const Divider(height: 32),
                    NamedItemLines(items: lineItemsOf(doc)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(onPressed: _approve, child: const Text('Approve')),
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
  String _transferNumber = '';
  final _notes = TextEditingController();
  final _requestDate = DateTime.now();
  List<OptionItem> _siteOptions = [];
  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _stock = [];
  final List<_TransferLine> _lines = [_TransferLine()];
  bool _saving = false;
  bool _loadingStock = false;
  bool _stockFailed = false;
  final _fieldErrors = FieldErrors();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final sites = await loadSiteOptions(context);
        if (!mounted) return;
        final items = await context.read<SettingsApis>().items.listAll({
          'sortBy': 'item_name',
          'sortOrder': 'asc',
        });
        if (!mounted) return;
        setState(() {
          _siteOptions = sites;
          _catalog = items;
        });
      } on ApiException catch (e) {
        if (mounted) showPmsSnack(context, e.message, error: true);
      }
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  List<OptionItem> _sitesExcept(String? exclude) {
    return _siteOptions.where((o) => o.value != exclude).toList();
  }

  Map<String, dynamic>? _catalogById(String? id) {
    if (id == null) return null;
    for (final row in _catalog) {
      if (idOf(row) == id) return row;
    }
    return null;
  }

  String _uomFor(String? itemId) {
    final item = _catalogById(itemId);
    if (item == null) return '—';
    final label = labelOf(item['uom'], fallback: '');
    return label.isEmpty ? '—' : label;
  }

  num _availableFor(String? itemId) {
    if (itemId == null) return 0;
    for (final row in _stock) {
      final id = mongoId(row['item_id']) ?? mongoId(row['item']);
      if (id == itemId) {
        return asNum(firstNonNull(row, ['availableStock', 'available_stock', 'remaining_quantity'])) ?? 0;
      }
    }
    return 0;
  }

  Future<void> _afterOriginPicked() async {
    if (_origin == null) return;
    try {
      final n = await context.read<AppServices>().inventory.nextTransferNumber(_origin!);
      if (!mounted) return;
      setState(() {
        _transferNumber = '${n['transfer_number'] ?? n['number'] ?? n['next'] ?? ''}';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _transferNumber = '');
      showPmsSnack(context, e.message, error: true);
    }
    await _reloadStock();
  }

  Future<void> _reloadStock() async {
    if (_origin == null) {
      setState(() {
        _stock = [];
        _stockFailed = false;
      });
      return;
    }
    setState(() {
      _loadingStock = true;
      _stockFailed = false;
    });
    try {
      final rows = await context.read<AppServices>().inventory.availableStock({
        'site_id': _origin,
        'inventoryType': _type,
      });
      if (!mounted) return;
      setState(() {
        _stock = rows;
        _loadingStock = false;
        _stockFailed = false;
        for (final line in _lines) {
          line.available = _availableFor(line.itemId);
          line.uom = _uomFor(line.itemId);
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _stock = [];
        _loadingStock = false;
        _stockFailed = true;
      });
      showPmsSnack(context, e.message, error: true);
    }
  }

  List<OptionItem> get _stockOptions {
    if (_stockFailed || (_stock.isEmpty && _origin == null)) {
      return mapToOptions(_catalog, labelOfRow: (r) => r['item_name']?.toString() ?? labelOf(r));
    }
    return _stock.map((row) {
      final item = row['item'];
      final itemMap = item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{};
      final id = mongoId(row['item_id']) ?? mongoId(itemMap) ?? '';
      final name = itemMap['item_name']?.toString() ?? labelOf(itemMap);
      final qty = asNum(firstNonNull(row, ['availableStock', 'available_stock'])) ?? 0;
      return OptionItem(
        value: id,
        label: qty > 0 ? '$name  ·  avail $qty' : name,
        raw: row,
      );
    }).where((o) => o.value.isNotEmpty).toList();
  }

  Future<void> _pickItem(int index) async {
    if (_origin == null) {
      showPmsSnack(context, 'Select origin site first', error: true);
      return;
    }
    final picked = await showOptionPicker(
      context,
      title: 'Select item',
      options: _stockOptions,
      selected: _lines[index].itemId,
      emptyMessage: 'No stock at origin for this inventory type',
    );
    if (picked == null || !mounted) return;
    final taken = _lines.asMap().entries.any((e) => e.key != index && e.value.itemId == picked.value);
    if (taken) {
      showPmsSnack(context, 'This item is already on the transfer', error: true);
      return;
    }
    setState(() {
      _lines[index].itemId = picked.value;
      _lines[index].itemLabel = picked.label.split('  ·  ').first;
      _lines[index].uom = _uomFor(picked.value);
      _lines[index].available = _availableFor(picked.value);
      if (_lines[index].qty.text.trim().isEmpty) {
        _lines[index].qty.text = '1';
      }
    });
  }

  void _addRow() {
    if (_origin == null) {
      showPmsSnack(context, 'Select origin site first', error: true);
      return;
    }
    setState(() => _lines.add(_TransferLine()));
  }

  void _removeRow(int index) {
    if (_lines.length == 1) {
      setState(_lines.first.clear);
      return;
    }
    setState(() {
      _lines.removeAt(index).dispose();
    });
  }

  Future<void> _save() async {
    _fieldErrors.clear();
    _fieldErrors.set('origin', requiredSelection(_origin, 'Origin site'));
    _fieldErrors.set('dest', requiredSelection(_dest, 'Destination site'));
    if (_origin != null && _origin == _dest) {
      _fieldErrors.set('dest', 'Origin and destination cannot be the same');
    }
    final items = <Map<String, dynamic>>[];
    var filled = 0;
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      if (line.itemId == null) continue;
      filled++;
      final rawQty = line.qty.text.trim();
      final qty = num.tryParse(rawQty);
      if (rawQty.isEmpty || qty == null || qty <= 0) {
        _fieldErrors.set('line${i}Qty', 'Requested quantity must be greater than 0');
        continue;
      }
      if (!_stockFailed && qty > line.available) {
        _fieldErrors.set(
          'line${i}Qty',
          'Requested qty for ${line.itemLabel} exceeds available ${line.available}',
        );
        continue;
      }
      items.add({
        'item_id': line.itemId,
        'requested_quantity': qty,
        if (line.remarks.text.trim().isNotEmpty) 'remarks': line.remarks.text.trim(),
      });
    }
    if (filled == 0) {
      _fieldErrors.set('lines', 'Add at least one line item');
    }
    if (_fieldErrors.hasErrors) {
      setState(() {});
      showPmsSnack(context, _fieldErrors.messages.first, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppServices>().inventory.createTransfer({
        'origin_site': _origin,
        'destination_site': _dest,
        'inventoryType': _type,
        'notes': _notes.text.trim(),
        'items': items,
      });
      if (!mounted) return;
      await showSavedConfirmation(context, 'Transfer created');
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        for (final entry in apiFieldErrors(e).entries) {
          _fieldErrors.set(entry.key, entry.value);
        }
      });
      showPmsSnack(context, formatApiErrorSummary(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New inter-site transfer')),
      body: ListView(
        padding: AppTheme.formPadding,
        children: [
          if (_fieldErrors.hasErrors) ValidationSummaryBanner(messages: _fieldErrors.messages),
          const Text(
            'Request material movement between sites',
            style: TextStyle(color: AppTheme.muted),
          ),
          const SizedBox(height: 16),
          PickerField(
            label: 'Origin site',
            required: true,
            valueLabel: _originLabel,
            errorText: _fieldErrors['origin'],
            onTap: () async {
              final p = await showOptionPicker(
                context,
                title: 'Origin site',
                options: _sitesExcept(_dest),
                selected: _origin,
              );
              if (p == null) return;
              setState(() {
                _origin = p.value;
                _originLabel = p.label;
                if (_dest == _origin) {
                  _dest = null;
                  _destLabel = '';
                }
              });
              await _afterOriginPicked();
            },
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Destination site',
            required: true,
            valueLabel: _destLabel,
            errorText: _fieldErrors['dest'],
            onTap: () async {
              final p = await showOptionPicker(
                context,
                title: 'Destination site',
                options: _sitesExcept(_origin),
                selected: _dest,
              );
              if (p == null) return;
              setState(() {
                _dest = p.value;
                _destLabel = p.label;
              });
            },
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Transfer number',
              helperText: 'Assigned on save (preview from origin site)',
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            child: Text(
              _origin == null
                  ? 'Select origin site'
                  : (_transferNumber.isEmpty ? 'Assigned on save' : _transferNumber),
              style: TextStyle(
                color: _transferNumber.isEmpty ? AppTheme.muted : AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Request date',
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            child: Text(formatDate(_requestDate.toIso8601String())),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Inventory type *'),
            items: const [
              DropdownMenuItem(value: 'Project BOQ', child: Text('Project BOQ')),
              DropdownMenuItem(value: 'Site Establishment', child: Text('Site Establishment')),
              DropdownMenuItem(value: 'Assets', child: Text('Assets')),
            ],
            onChanged: (v) {
              setState(() => _type = v ?? _type);
              _reloadStock();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('Line items', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add row'),
              ),
            ],
          ),
          if (_fieldErrors['lines'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_fieldErrors['lines']!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
            ),
          if (_loadingStock)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_origin != null && !_loadingStock && _stock.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'No available stock at origin for this inventory type.',
                style: TextStyle(color: AppTheme.muted),
              ),
            ),
          for (var i = 0; i < _lines.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('Row ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Remove row',
                          onPressed: () => _removeRow(i),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    PickerField(
                      label: 'Item',
                      required: true,
                      valueLabel: _lines[i].itemLabel,
                      enabled: _origin != null,
                      errorText: _fieldErrors['line${i}Item'],
                      onTap: () => _pickItem(i),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'UOM',
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                            ),
                            child: Text(_lines[i].uom),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Available qty',
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                            ),
                            child: Text(_lines[i].itemId == null ? '—' : '${_lines[i].available}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _lines[i].qty,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Requested qty *',
                        errorText: _fieldErrors['line${i}Qty'],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _lines[i].remarks,
                      decoration: const InputDecoration(labelText: 'Remarks'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Create transfer'),
          ),
        ],
      ),
    );
  }
}

class _TransferLine {
  String? itemId;
  String itemLabel = '';
  String uom = '—';
  num available = 0;
  final qty = TextEditingController();
  final remarks = TextEditingController();

  void clear() {
    itemId = null;
    itemLabel = '';
    uom = '—';
    available = 0;
    qty.clear();
    remarks.clear();
  }

  void dispose() {
    qty.dispose();
    remarks.dispose();
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
  Map<String, dynamic>? _pagination;
  String _search = '';
  int _page = 1;

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
      final res = await context.read<AppServices>().inventory.listScrap({
        'page': _page,
        'limit': 20,
        if (_search.isNotEmpty) 'search': _search,
      });
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _pagination = res.pagination;
        _loading = false;
      });
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

  @override
  Widget build(BuildContext context) {
    final pages = paginationTotalPages(_pagination);
    return Scaffold(
      appBar: AppBar(title: const Text('Scrap'), actions: const [WorkspaceSwitcherButton()]),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/inventory/scrap/new'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: AppTheme.searchPadding,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search scrap number…',
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
                          ? EmptyListBody(
                              message: listEmptyMessage(noun: 'scrap records', search: _search),
                            )
                          : ListView.separated(
                              padding: AppTheme.formPadding,
                              itemCount: _items.length + 1,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                if (i == _items.length) {
                                  return ListPaginationRow(
                                    page: _page,
                                    totalPages: pages,
                                    onPrev: _page > 1
                                        ? () {
                                            setState(() => _page -= 1);
                                            _load();
                                          }
                                        : null,
                                    onNext: _page < pages
                                        ? () {
                                            setState(() => _page += 1);
                                            _load();
                                          }
                                        : null,
                                  );
                                }
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
          ),
        ],
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
      final services = context.read<AppServices>();
      final doc = await services.inventory.getScrap(widget.id);
      if (!mounted) return;
      await resolveDocItemNames(doc, services.settings.items.getById);
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
                    const Divider(height: 32),
                    NamedItemLines(items: lineItemsOf(doc)),
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
  final _fieldErrors = FieldErrors();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = context.read<SettingsApis>();
      final sites = await s.sites.listAll({'sortBy': 'site_name', 'sortOrder': 'asc'});
      final items = await s.items.listAll({'sortBy': 'item_name', 'sortOrder': 'asc'});
      if (!mounted) return;
      setState(() {
        _sites = sites;
        _catalog = items;
      });
    });
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _fieldErrors.clear();
    _fieldErrors.set('site', requiredSelection(_siteId, 'Site'));
    _fieldErrors.set('number', _number.trim().isEmpty ? 'Scrap number is required — pick the site again' : null);
    _fieldErrors.set('item', requiredSelection(_itemId, 'Item'));
    if (_fieldErrors.hasErrors) {
      setState(() {});
      showPmsSnack(context, _fieldErrors.messages.first, error: true);
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
      await showSavedConfirmation(context, 'Scrap created');
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        for (final entry in apiFieldErrors(e).entries) {
          _fieldErrors.set(entry.key, entry.value);
        }
      });
      showPmsSnack(context, formatApiErrorSummary(e), error: true);
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
          if (_fieldErrors.hasErrors) ValidationSummaryBanner(messages: _fieldErrors.messages),
          PickerField(
            label: 'Site',
            required: true,
            valueLabel: _siteLabel,
            errorText: _fieldErrors['site'],
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
          if (_fieldErrors['number'] != null)
            Text(_fieldErrors['number']!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
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
            errorText: _fieldErrors['item'],
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
