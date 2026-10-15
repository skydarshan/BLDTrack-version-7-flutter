import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/widgets/sort_menu.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/form_validation_helpers.dart';
import '../../../core/utils/list_query.dart';
import '../../app/app_services.dart';
import '../../app/app_shell.dart';
import '../../pms/utils/site_options.dart';
import '../../pms/widgets/media_widgets.dart';
import '../../pms/widgets/pickers.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../../settings/services/settings_apis.dart';
import 'dmr_finance_screens.dart';

class DmrStatusScreen extends StatefulWidget {
  const DmrStatusScreen({super.key});

  @override
  State<DmrStatusScreen> createState() => _DmrStatusScreenState();
}

class _DmrFeed {
  const _DmrFeed({this.rows = const [], this.error, this.hasMore = false});
  final List<Map<String, dynamic>> rows;
  final Object? error;
  final bool hasMore;
}

class _DmrStatusScreenState extends State<DmrStatusScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _status = '';
  String _search = '';
  String? _siteId;
  String _siteLabel = '';
  DateTime? _date;
  String? _draftSiteId;
  String _draftSiteLabel = '';
  DateTime? _draftDate;
  List<Map<String, dynamic>> _sites = [];
  final _searchCtrl = TextEditingController();
  int _page = 1;
  String _sortBy = 'createdAt';
  String _sortOrder = 'desc';
  bool _hasMore = false;
  bool _loadingMore = false;
  static const _pageSize = 20;
  int _countAll = 0;
  int _countPending = 0;
  int _countPartial = 0;
  int _countClosed = 0;
  int _countHold = 0;
  int _countImprest = 0;

  static const _orderStatuses = {'pending', 'partial', 'hold', 'completed'};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final sites = await loadSiteOptions(context);
        if (!mounted) return;
        setState(() {
          _sites = [
            for (final o in sites) o.raw ?? {'_id': o.value, 'site_name': o.label},
          ];
        });
      } catch (_) {}
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<_DmrFeed> _loadFeed(Future<_DmrFeed> Function() load) async {
    try {
      return await load();
    } on ApiException catch (e) {
      return _DmrFeed(error: e);
    } catch (e) {
      return _DmrFeed(error: e);
    }
  }

  String? get _day => isoDateOnly(_date);

  bool _onSelectedDay(Map<String, dynamic> row) {
    final day = _date;
    if (day == null) return true;
    final raw = firstNonNull(row, ['date', 'createdAt', 'created_at', 'invoice_date', 'gate_entry_date']);
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return false;
    final local = parsed.toLocal();
    return local.year == day.year && local.month == day.month && local.day == day.day;
  }

  Future<void> _loadCounts(dynamic api) async {
    final search = _search.trim();
    final day = _day;
    try {
      final counts = await api.orderStatusCounts({
        if (search.isNotEmpty) 'search': search,
        if (_siteId != null) 'site': _siteId,
        if (day != null) 'dateFrom': day,
        if (day != null) 'dateTo': day,
      });
      final totals = await api.entryTotals({
        if (search.isNotEmpty) 'search': search,
        if (_siteId != null) 'site': _siteId,
        if (day != null) 'date_from': day,
        if (day != null) 'date_to': day,
      });
      if (!mounted) return;
      int n(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
      final byStatus = counts['statusCounts'];
      int statusCount(String key) {
        if (byStatus is Map && byStatus[key] != null) return n(byStatus[key]);
        return 0;
      }
      final orders = n(counts['total']);
      final entries = n(totals['dmr_entries_total']);
      final imprest = n(counts['imperest_entries_total'] ?? totals['imperest_entries_total']);
      setState(() {
        _countPending = statusCount('pending');
        _countPartial = statusCount('partial');
        _countClosed = statusCount('completed');
        _countHold = statusCount('hold');
        _countImprest = imprest;
        _countAll = orders + entries + imprest;
      });
    } catch (_) {}
  }

  bool _pageHasMore(PaginatedResult res, int page) {
    final pages = res.pagination?['totalPages'];
    if (pages is num) return page < pages.toInt();
    return res.items.length >= _pageSize;
  }

  Future<void> _load({bool reset = true}) async {
    if (!reset && (!_hasMore || _loadingMore)) return;
    final page = reset ? 1 : _page + 1;
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final api = context.read<AppServices>().dmr;
      final search = _search.trim();
      final day = _day;
      final wantOrders = _status != 'imprest' && (_status.isEmpty || _orderStatuses.contains(_status));
      final wantEntries = _status.isEmpty || _status == 'completed';
      final wantImprest = _status.isEmpty || _status == 'imprest' || _status == 'completed';
      final results = await Future.wait([
        if (wantOrders)
          _loadFeed(() async {
            final res = await api.listOrders({
              'page': page,
              'limit': _pageSize,
              'sortBy': _sortBy,
              'sortOrder': _sortOrder,
              if (search.isNotEmpty) 'search': search,
              if (_siteId != null) 'site': _siteId,
              if (day != null) 'dateFrom': day,
              if (day != null) 'dateTo': day,
              if (_status.isNotEmpty && _orderStatuses.contains(_status)) 'status': _status,
            });
            return _DmrFeed(
              hasMore: _pageHasMore(res, page),
              rows: res.items.map((e) => {...e, '_dmrKind': 'order'}).toList(),
            );
          })
        else
          Future.value(const _DmrFeed()),
        if (wantEntries)
          _loadFeed(() async {
            final res = await api.listEntries({
              'page': page,
              'limit': _pageSize,
              'sortBy': _sortBy,
              'sortOrder': _sortOrder,
              if (search.isNotEmpty) 'search': search,
              if (_siteId != null) 'site': _siteId,
              if (day != null) 'date_from': day,
              if (day != null) 'date_to': day,
              if (_status == 'completed') 'status': 'completed',
            });
            return _DmrFeed(
              hasMore: _pageHasMore(res, page),
              rows: res.items.map((e) => {...e, '_dmrKind': 'entry'}).toList(),
            );
          })
        else
          Future.value(const _DmrFeed()),
        if (wantImprest)
          _loadFeed(() async {
            final res = await api.listImprest({
              'page': page,
              'limit': _pageSize,
              'sortBy': _sortBy,
              'sortOrder': _sortOrder,
              if (search.isNotEmpty) 'search': search,
              if (_siteId != null) 'site': _siteId,
              if (_status == 'completed') 'status': 'completed',
            });
            return _DmrFeed(
              hasMore: _pageHasMore(res, page),
              rows: res.items
                  .map((e) => {...e, '_dmrKind': 'imprest'})
                  .where(_onSelectedDay)
                  .toList(),
            );
          })
        else
          Future.value(const _DmrFeed()),
      ]);
      final merged = <Map<String, dynamic>>[
        ...results[0].rows,
        ...results[1].rows,
        ...results[2].rows,
      ];
      final errors = results.map((r) => r.error).whereType<Object>().toList();
      if (!mounted) return;
      if (reset && merged.isEmpty && errors.isNotEmpty) {
        final first = errors.first;
        setState(() {
          _items = const [];
          _page = 1;
          _hasMore = false;
          _error = first is ApiException ? first.message : first.toString();
          _loading = false;
          _loadingMore = false;
        });
        return;
      }
      if (!reset && merged.isEmpty && errors.isNotEmpty) {
        final first = errors.first;
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
        if (mounted) {
          showPmsSnack(
            context,
            first is ApiException ? first.message : first.toString(),
            error: true,
          );
        }
        return;
      }
      setState(() {
        _page = page;
        _items = reset ? merged : [..._items, ...merged];
        _hasMore = results.any((feed) => feed.hasMore);
        _loading = false;
        _loadingMore = false;
      });
      if (reset) await _loadCounts(api);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = reset ? e.message : _error;
        _loading = false;
        _loadingMore = false;
      });
      if (!reset) showPmsSnack(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = reset ? e.toString() : _error;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  String _clean(dynamic value) {
    if (value == null) return '';
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty || looksLikeObjectId(text)) return '';
      return text;
    }
    final labeled = labelOf(value, fallback: '');
    return labeled == '—' ? '' : labeled;
  }

  String _orDash(String value) => value.trim().isEmpty ? '—' : value.trim();

  String _locationOf(Map<String, dynamic> row) {
    final site = row['site'];
    if (site is Map) {
      final location = site['location']?.toString().trim() ?? '';
      if (location.isNotEmpty) return location;
      final name = site['site_name']?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
    }
    return _clean(site);
  }

  String _vendorOf(Map<String, dynamic> row) => vendorNamesOf(row);

  String _itemNames(Map<String, dynamic> row) {
    final names = <String>[];
    for (final line in _linesOf(row)) {
      final item = itemLabel(line, fallback: '');
      final category = _clean(line['category_id']);
      final name = item.isNotEmpty ? item : category;
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
    return names.join(', ');
  }

  List<Map<String, dynamic>> _linesOf(Map<String, dynamic> row) {
    final raw = row['dmr_items'] ?? row['items'];
    if (raw is! List) return const [];
    return [
      for (final line in raw)
        if (line is Map) Map<String, dynamic>.from(line),
    ];
  }

  String _statusText(Map<String, dynamic> row) {
    return switch (row['status']?.toString()) {
      'pending' => 'Pending',
      'partial' => 'Partial Delivered',
      'completed' => 'Closed',
      'hold' => 'Closure Pending',
      'open' => 'Open',
      final other => statusLabel(other),
    };
  }

  String? get _statusFilterLabel => switch (_status) {
        '' => null,
        'partial' => 'Partial Delivered',
        'completed' => 'Closed',
        'hold' => 'Closure Pending',
        'imprest' => 'Imprest',
        'pending' => 'Pending',
        _ => _status,
      };

  bool get _hasFilters => _search.isNotEmpty || _siteId != null || _date != null;

  void _applyFilters() {
    setState(() {
      _search = _searchCtrl.text.trim();
      _siteId = _draftSiteId;
      _siteLabel = _draftSiteLabel;
      _date = _draftDate;
    });
    _load();
  }

  void _resetFilters() {
    _searchCtrl.clear();
    setState(() {
      _search = '';
      _siteId = null;
      _siteLabel = '';
      _date = null;
      _draftSiteId = null;
      _draftSiteLabel = '';
      _draftDate = null;
      _status = '';
    });
    _load();
  }

  Future<void> _openFilters() async {
    _searchCtrl.text = _search;
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
                      TextField(
                        controller: _searchCtrl,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText: 'Search RO, site, vendor, item...',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onSubmitted: (_) {
                          _applyFilters();
                          Navigator.pop(sheetContext);
                        },
                      ),
                      const SizedBox(height: 12),
                      PickerField(
                        label: 'Select sites',
                        hint: 'All sites — search...',
                        valueLabel: _draftSiteLabel,
                        onTap: () async {
                          await _pickSite(sheetContext);
                          setSheet(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Date'),
                      ),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _pickDate(sheetContext);
                          setSheet(() {});
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

  Future<void> _pickSite(BuildContext pickerContext) async {
    final picked = await showOptionPicker(
      pickerContext,
      title: 'Select sites',
      options: mapSiteRowsToOptions(_sites),
      selected: _draftSiteId,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _draftSiteId = picked.value;
      _draftSiteLabel = picked.label;
    });
  }

  Future<void> _pickDate(BuildContext pickerContext) async {
    final picked = await showDatePicker(
      context: pickerContext,
      initialDate: _draftDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _draftDate = picked);
  }

  Widget _statusCard(Map<String, dynamic> row) {
    final id = idOf(row);
    final number = _clean(row['ro_number']).isNotEmpty ? _clean(row['ro_number']) : _clean(row['dmr_no']);
    final date = formatDate(firstNonNull(row, ['date', 'createdAt', 'created_at', 'poStartDate', 'gate_entry_date', 'invoice_date']));
    final items = _itemNames(row);
    final canOpen = looksLikeObjectId(id);
    return Card(
      child: ListTile(
        isThreeLine: true,
        title: Text(_orDash(number), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          [
            '$date · ${_orDash(_locationOf(row))}',
            _orDash(_vendorOf(row)),
            if (items.isNotEmpty) items,
          ].join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusChip(status: row['status']?.toString(), label: _statusText(row)),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (value) {
                if (value == 'delete') _deleteRow(row);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: AppTheme.danger)),
                ),
              ],
            ),
          ],
        ),
        onTap: canOpen ? () => _openRow(row) : null,
      ),
    );
  }

  Future<void> _openRow(Map<String, dynamic> row) async {
    final id = idOf(row);
    final kind = row['_dmrKind']?.toString() ?? '';
    if (!looksLikeObjectId(id)) return;
    final path = switch (kind) {
      'order' => '/dmr/status/$id',
      'entry' => '/dmr/entries/$id',
      'imprest' => '/dmr/imprest/$id',
      _ => null,
    };
    if (path == null) return;
    await context.push<bool>(path);
    if (mounted) _load();
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    final id = idOf(row);
    final kind = row['_dmrKind']?.toString() ?? '';
    if (id == null || id.isEmpty) return;
    final label = switch (kind) {
      'order' => 'DMR order',
      'entry' => 'DMR entry',
      'imprest' => 'cash purchase',
      _ => 'record',
    };
    final ok = await confirmAction(
      context,
      title: 'Delete $label?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      final dmr = context.read<AppServices>().dmr;
      if (kind == 'order') await dmr.deleteOrder(id);
      if (kind == 'entry') await dmr.deleteEntry(id);
      if (kind == 'imprest') await dmr.deleteImprest(id);
      if (!mounted) return;
      showPmsSnack(context, '$label deleted');
      _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  void _openCreate() => context.push('/dmr/create');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DMR status'),
        actions: [
          SortMenuButton(
            choices: const [
              SortChoice(by: 'createdAt', order: 'desc', label: 'Newest'),
              SortChoice(by: 'createdAt', order: 'asc', label: 'Oldest'),
            ],
            sortBy: _sortBy,
            sortOrder: _sortOrder,
            onSelected: (by, order) {
              setState(() {
                _sortBy = by;
                _sortOrder = order;
              });
              _load();
            },
          ),
          IconButton(
            tooltip: 'Filters',
            onPressed: _openFilters,
            icon: Badge(
              isLabelVisible: _hasFilters,
              smallSize: 8,
              child: const Icon(Icons.filter_list),
            ),
          ),
          IconButton(
            tooltip: 'Create DMR',
            onPressed: _openCreate,
            icon: const Icon(Icons.add),
          ),
          const WorkspaceSwitcherButton(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: AppTheme.chipRowPadding,
            child: Row(
              children: [
                for (final chip in const [
                  ('', 'All'),
                  ('pending', 'Pending'),
                  ('partial', 'Partial Delivered'),
                  ('completed', 'Closed'),
                  ('hold', 'Closure Pending'),
                  ('imprest', 'Imprest'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${chip.$2} (${switch (chip.$1) {
                        '' => _countAll,
                        'pending' => _countPending,
                        'partial' => _countPartial,
                        'completed' => _countClosed,
                        'hold' => _countHold,
                        _ => _countImprest,
                      }})'),
                      selected: _status == chip.$1,
                      onSelected: (_) {
                        setState(() => _status = chip.$1);
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
                  ? const CenteredScrollLoader()
                  : _error != null
                      ? ListView(padding: AppTheme.formPadding, children: [ErrorBanner(message: _error!, onRetry: _load)])
                      : _items.isEmpty
                          ? EmptyListBody(
                              message: listEmptyMessage(
                                noun: 'DMR records',
                                search: _search,
                                filterLabel: [
                                  if (_statusFilterLabel != null) _statusFilterLabel!,
                                  if (_siteId != null) 'selected site',
                                  if (_date != null) formatDate(_date!.toIso8601String()),
                                ].join(', '),
                              ),
                            )
                          : ListView.separated(
                              padding: AppTheme.formPadding,
                              itemCount: _items.length + (_hasMore || _loadingMore ? 1 : 0),
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                if (i >= _items.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: _loadingMore
                                        ? const Center(child: CircularProgressIndicator())
                                        : OutlinedButton(
                                            onPressed: () => _load(reset: false),
                                            child: const Text('Load more'),
                                          ),
                                  );
                                }
                                return _statusCard(_items[i]);
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

List<Widget> _dmrDetailActions(
  BuildContext context, {
  required String id,
  required String kind,
  required Future<void> Function() reload,
}) {
  return [
    IconButton(
      tooltip: 'Edit',
      onPressed: () async {
        final path = switch (kind) {
          'order' => '/dmr/status/$id/edit',
          'entry' => '/dmr/entries/$id/edit',
          'imprest' => '/dmr/imprest/$id/edit',
          _ => '',
        };
        if (path.isEmpty) return;
        final updated = await context.push<bool>(path);
        if (updated == true && context.mounted) reload();
      },
      icon: const Icon(Icons.edit_outlined),
    ),
  ];
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
  List<Map<String, dynamic>> _debits = [];
  List<Map<String, dynamic>> _credits = [];
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
      final doc = await services.dmr.getOrder(widget.id);
      if (!mounted) return;
      await resolveDocItemNames(doc, services.settings.items.getById);
      if (!mounted) return;
      final ro = doc['ro_number']?.toString();
      final entries = ro == null || ro.isEmpty
          ? <Map<String, dynamic>>[]
          : await services.dmr.entriesByRo({'ro_number': ro});
      var debits = <Map<String, dynamic>>[];
      var credits = <Map<String, dynamic>>[];
      if (ro != null && ro.isNotEmpty) {
        try {
          debits = await services.dmr.debitNotes({'ro_number': ro});
        } on ApiException {
          debits = const [];
        }
        try {
          credits = await services.dmr.creditNotes({'ro_number': ro});
        } on ApiException {
          credits = const [];
        }
      }
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _entries = entries;
        _debits = debits;
        _credits = credits;
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
      await context.read<AppServices>().dmr.closeOrder(widget.id, {
        'status': 'completed',
        'closing_category': '',
        'closing_remark': '',
      });
      if (!mounted) return;
      showPmsSnack(context, 'Order closed');
      _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  String? get _roNumber {
    final value = _doc?['ro_number']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get _siteId => mongoId(_doc?['site']);

  String? get _vendorId => mongoId(_doc?['vendor_id'] ?? _doc?['vendor'] ?? _doc?['vendor_detail']);

  bool get _variancePending {
    return _doc?['status']?.toString() == 'hold' && _doc?['variance_approval']?.toString() == 'pending';
  }

  Future<void> _downloadDocs() {
    final ro = _roNumber ?? widget.id;
    return shareDmrDownload(
      context,
      load: () => context.read<AppServices>().dmr.downloadOrderDocs(widget.id),
      filename: 'dmr_$ro.zip',
      label: 'DMR documents',
    );
  }

  Future<void> _variance(String decision) async {
    try {
      await context.read<AppServices>().dmr.varianceApproval(widget.id, {
        'variance_approval': decision,
      });
      if (!mounted) return;
      showPmsSnack(context, decision == 'approved' ? 'Variance approved' : 'Variance rejected');
      _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _raiseDebit() async {
    final ro = _roNumber;
    final site = _siteId;
    final vendor = _vendorId;
    if (ro == null || site == null || vendor == null) {
      showPmsSnack(context, 'This order is missing a site, vendor, or RO number', error: true);
      return;
    }
    final created = await context.push<bool>(
      '/dmr/debit/new?order=${widget.id}&ro=${Uri.encodeQueryComponent(ro)}&site=$site&vendor=$vendor',
    );
    if (created == true && mounted) _load();
  }

  Future<void> _addCredit() async {
    final ro = _roNumber;
    final site = _siteId;
    final vendor = _vendorId;
    if (ro == null || site == null || vendor == null) {
      showPmsSnack(context, 'This order is missing a site, vendor, or RO number', error: true);
      return;
    }
    final created = await showCreditNoteSheet(
      context,
      roNumber: ro,
      vendorId: vendor,
      siteId: site,
    );
    if (created && mounted) {
      showPmsSnack(context, 'Credit note saved');
      _load();
    }
  }

  Future<void> _downloadCreditDocs() {
    final ro = _roNumber;
    if (ro == null) {
      showPmsSnack(context, 'RO number is missing', error: true);
      return Future.value();
    }
    return shareDmrDownload(
      context,
      load: () => context.read<AppServices>().dmr.downloadCreditDocs({'ro_number': ro}),
      filename: 'credit_notes_$ro.zip',
      label: 'Credit note documents',
    );
  }

  Future<void> _downloadDebit(String id, String number) {
    return shareDmrDownload(
      context,
      load: () => context.read<AppServices>().dmr.downloadDebitPdf(id),
      filename: '${number.isEmpty ? 'debit_note' : number}.pdf',
      label: 'Debit note',
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      appBar: AppBar(
        title: Text(doc?['ro_number']?.toString() ?? 'DMR order'),
        actions: _dmrDetailActions(
          context,
          id: widget.id,
          kind: 'order',
          reload: _load,
        ),
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
                    StatusChip(status: doc?['status']?.toString()),
                    const SizedBox(height: 8),
                    Text('Vendor: ${doc == null ? '—' : (vendorNamesOf(doc).isEmpty ? '—' : vendorNamesOf(doc))}'),
                    Text('Site: ${labelOf(doc?['site'])}'),
                    Text('Date: ${formatDate(doc?['poStartDate'] ?? doc?['createdAt'])}'),
                    if ((doc?['remarks'] ?? '').toString().trim().isNotEmpty)
                      Text('Remarks: ${doc?['remarks']}'),
                    const Divider(height: 32),
                    NamedItemLines(items: lineItemsOf(doc)),
                    const Divider(height: 32),
                    const Text('Entries', style: TextStyle(fontWeight: FontWeight.w700)),
                    for (final e in _entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(e['dmr_no']?.toString() ?? e['challan_number']?.toString() ?? 'Entry'),
                        subtitle: Text(e['entry_type']?.toString() ?? ''),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final entryId = idOf(e);
                          if (!looksLikeObjectId(entryId)) return;
                          final changed = await context.push<bool>('/dmr/entries/$entryId');
                          if (changed == true && mounted) _load();
                        },
                      ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _close, child: const Text('Close order')),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _downloadDocs,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download documents'),
                    ),
                    if (_variancePending) ...[
                      const SizedBox(height: 16),
                      const Text('Variance approval is pending', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: () => _variance('approved'),
                              child: const Text('Approve'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _variance('rejected'),
                              child: const Text('Reject'),
                            ),
                          ),
                        ],
                      ),
                    ] else if ((_doc?['variance_approval'] ?? '').toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Variance: ${_doc?['variance_approval']}'),
                    ],
                    const Divider(height: 32),
                    const Text('Debit notes', style: TextStyle(fontWeight: FontWeight.w700)),
                    if (_debits.isEmpty)
                      const Text('No debit notes')
                    else
                      for (final note in _debits)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(note['debitNoteNumber']?.toString() ?? 'Debit note'),
                          subtitle: Text('${note['status'] ?? 'raised'} · ${note['grandTotal'] ?? note['totalAmount'] ?? ''}'),
                          trailing: IconButton(
                            tooltip: 'Download PDF',
                            onPressed: () {
                              final id = idOf(note);
                              if (!looksLikeObjectId(id)) return;
                              _downloadDebit(id!, note['debitNoteNumber']?.toString() ?? 'debit_note');
                            },
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                          ),
                        ),
                    OutlinedButton(onPressed: _raiseDebit, child: const Text('Raise debit note')),
                    const Divider(height: 32),
                    const Text('Credit notes', style: TextStyle(fontWeight: FontWeight.w700)),
                    if (_credits.isEmpty)
                      const Text('No credit notes')
                    else
                      for (final note in _credits)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(note['creditNoteNumber']?.toString() ?? 'Credit note'),
                          subtitle: Text(
                            '${formatDate(note['creditNoteDate'])} · ${note['creditNoteAmount'] ?? ''}',
                          ),
                        ),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: _addCredit, child: const Text('Add credit note')),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _downloadCreditDocs,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download credit documents'),
                    ),
                  ],
                ),
    );
  }
}

class DmrEntryDetailScreen extends StatefulWidget {
  const DmrEntryDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<DmrEntryDetailScreen> createState() => _DmrEntryDetailScreenState();
}

class _DmrEntryDetailScreenState extends State<DmrEntryDetailScreen> {
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
      final doc = await services.dmr.getEntry(widget.id);
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
    final title = doc?['dmr_no']?.toString() ?? doc?['challan_number']?.toString() ?? 'DMR entry';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: _dmrDetailActions(
          context,
          id: widget.id,
          kind: 'entry',
          reload: _load,
        ),
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
                    StatusChip(status: doc?['status']?.toString()),
                    const SizedBox(height: 8),
                    Text('PO: ${doc?['ro_number'] ?? '—'}'),
                    Text('Site: ${labelOf(doc?['site'])}'),
                    Text('Vendor: ${doc == null ? '—' : (vendorNamesOf(doc).isEmpty ? labelOf(doc['vendor_id'] ?? doc['vendor_detail']) : vendorNamesOf(doc))}'),
                    Text('Date: ${formatDate(doc?['invoice_date'] ?? doc?['challan_date'] ?? doc?['gate_entry_date'])}'),
                    if ((doc?['challan_number'] ?? '').toString().isNotEmpty)
                      Text('Challan: ${doc?['challan_number']}'),
                    if ((doc?['invoice_number'] ?? '').toString().isNotEmpty)
                      Text('Invoice: ${doc?['invoice_number']}'),
                    if ((doc?['gate_register_entry'] ?? '').toString().isNotEmpty)
                      Text('Gate: ${doc?['gate_register_entry']}'),
                    if ((doc?['vehicle_number'] ?? '').toString().isNotEmpty)
                      Text('Vehicle: ${doc?['vehicle_number']}'),
                    if ((doc?['remarks'] ?? '').toString().trim().isNotEmpty)
                      Text('Remarks: ${doc?['remarks']}'),
                    if ((doc?['date_of_doc_submission_to_ho'] ?? '').toString().isNotEmpty)
                      Text('Submitted to HO: ${formatDate(doc?['date_of_doc_submission_to_ho'])}'),
                    if ((doc?['remarks_for_audit'] ?? '').toString().trim().isNotEmpty)
                      Text('Audit remarks: ${doc?['remarks_for_audit']}'),
                    const Divider(height: 32),
                    NamedItemLines(items: lineItemsOf(doc)),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => shareDmrDownload(
                        context,
                        load: () => context.read<AppServices>().dmr.downloadEntryPdf(widget.id),
                        filename: '${title.replaceAll(' ', '_')}.pdf',
                        label: 'DMR entry',
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Download PDF'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () async {
                        await showDocSubmissionSheet(
                          context,
                          recordId: widget.id,
                          imprest: false,
                          existingDate: doc?['date_of_doc_submission_to_ho']?.toString(),
                          existingRemarks: doc?['remarks_for_audit']?.toString(),
                        );
                        if (mounted) _load();
                      },
                      child: const Text('Document submission'),
                    ),
                  ],
                ),
    );
  }
}

class DmrImprestDetailScreen extends StatefulWidget {
  const DmrImprestDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<DmrImprestDetailScreen> createState() => _DmrImprestDetailScreenState();
}

class _DmrImprestDetailScreenState extends State<DmrImprestDetailScreen> {
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
      final doc = await services.dmr.getImprest(widget.id);
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
      appBar: AppBar(
        title: Text(doc?['dmr_no']?.toString() ?? 'Cash purchase'),
        actions: _dmrDetailActions(
          context,
          id: widget.id,
          kind: 'imprest',
          reload: _load,
        ),
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
                    StatusChip(status: doc?['status']?.toString()),
                    const SizedBox(height: 8),
                    Text('Site: ${labelOf(doc?['site'])}'),
                    Text('Date: ${formatDate(doc?['date'] ?? doc?['invoice_date'])}'),
                    Text('Vendor: ${doc == null ? '—' : (vendorNamesOf(doc).isEmpty ? '—' : vendorNamesOf(doc))}'),
                    Text('Invoice: ${doc?['invoice_number'] ?? '—'}'),
                    if ((doc?['gate_register_entry'] ?? '').toString().isNotEmpty)
                      Text('Gate: ${doc?['gate_register_entry']}'),
                    if ((doc?['vehicle_number'] ?? '').toString().isNotEmpty)
                      Text('Vehicle: ${doc?['vehicle_number']}'),
                    if ((doc?['remarks'] ?? '').toString().trim().isNotEmpty)
                      Text('Remarks: ${doc?['remarks']}'),
                    if ((doc?['date_of_doc_submission_to_ho'] ?? '').toString().isNotEmpty)
                      Text('Submitted to HO: ${formatDate(doc?['date_of_doc_submission_to_ho'])}'),
                    if ((doc?['remarks_for_audit'] ?? '').toString().trim().isNotEmpty)
                      Text('Audit remarks: ${doc?['remarks_for_audit']}'),
                    Text('Total: ${doc?['total_amount'] ?? '—'}'),
                    const Divider(height: 32),
                    NamedItemLines(items: lineItemsOf(doc)),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => shareDmrDownload(
                        context,
                        load: () => context.read<AppServices>().dmr.downloadImprestPdf(widget.id),
                        filename: '${(doc?['dmr_no'] ?? 'cash_purchase').toString().replaceAll(' ', '_')}.pdf',
                        label: 'Cash purchase',
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Download PDF'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () async {
                        await showDocSubmissionSheet(
                          context,
                          recordId: widget.id,
                          imprest: true,
                          existingDate: doc?['date_of_doc_submission_to_ho']?.toString(),
                          existingRemarks: doc?['remarks_for_audit']?.toString(),
                        );
                        if (mounted) _load();
                      },
                      child: const Text('Document submission'),
                    ),
                  ],
                ),
    );
  }
}

class DmrCreateScreen extends StatefulWidget {
  const DmrCreateScreen({super.key, this.recordId, this.recordKind});

  final String? recordId;
  final String? recordKind;

  bool get isEdit => recordId != null && recordId!.isNotEmpty;

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
  String _roNumber = '';
  String _poDate = '';
  String _poValidTill = '';
  String _orgName = '';
  String _prType = 'Site Establishment';
  String _orderType = 'Purchase Order';
  bool _cashPurchase = false;
  String _entryType = 'challan';
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _vendors = [];
  List<Map<String, dynamic>> _open = [];
  List<_DmrLine> _lines = [];
  final _dmrNo = TextEditingController();
  final _challan = TextEditingController();
  final _invoice = TextEditingController();
  final _gate = TextEditingController();
  final _gateTime = TextEditingController();
  final _mode = TextEditingController();
  final _vehicle = TextEditingController();
  final _docket = TextEditingController();
  DateTime? _gateDate;
  DateTime? _challanDate;
  DateTime? _invoiceDate;
  DateTime _entryDate = DateTime.now();
  TimeOfDay? _entryTime;
  String _modeValue = 'Vehicle';
  final _otherCharges = TextEditingController(text: '0');
  String _otherGst = '0';
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _uoms = [];
  List<String> _gstRates = ['0'];
  final List<_CashLine> _cashLines = [_CashLine()];
  PendingFile? _document;
  String _existingDoc = '';
  bool _saving = false;
  bool _loadingPo = false;
  bool _loadingRecord = false;
  final _fieldErrors = FieldErrors();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settings = context.read<SettingsApis>();
      final sites = await loadSiteOptions(context);
      if (!mounted) return;
      final vendors = await settings.vendors.listAll({
        'sortBy': 'vendor_name',
        'sortOrder': 'asc',
      });
      final categories = await settings.categories.listAll({
        'sortBy': 'name',
        'sortOrder': 'asc',
      });
      final uoms = await settings.uoms.listAll({
        'sortBy': 'uom_name',
        'sortOrder': 'asc',
      });
      final gsts = await settings.gsts.listAll({
        'sortBy': 'gst_percentage',
        'sortOrder': 'asc',
      });
      if (!mounted) return;
      setState(() {
        _sites = [
          for (final o in sites) o.raw ?? {'_id': o.value, 'site_name': o.label},
        ];
        _vendors = vendors;
        _categories = categories;
        _uoms = uoms;
        final rates = <String>{'0'};
        for (final row in gsts) {
          final rate = asNum(row['gst_percentage']);
          if (rate != null) rates.add(rate.toString());
        }
        _gstRates = rates.toList()..sort((a, b) => (num.tryParse(a) ?? 0).compareTo(num.tryParse(b) ?? 0));
      });
      if (widget.isEdit) await _loadRecord();
    });
  }

  String get _saveLabel => _saving ? 'Saving…' : (widget.isEdit ? 'Save' : 'Create DMR');

  DateTime? _parseDate(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  TimeOfDay? _parseTime(String raw) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$', caseSensitive: false).firstMatch(raw.trim());
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final suffix = match.group(3)?.toUpperCase();
    if (suffix == 'PM' && hour < 12) hour += 12;
    if (suffix == 'AM' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _numText(num value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  Future<void> _loadRecord() async {
    setState(() => _loadingRecord = true);
    try {
      final dmr = context.read<AppServices>().dmr;
      if (widget.recordKind == 'imprest') {
        _applyImprest(await dmr.getImprest(widget.recordId!));
      } else {
        await _applyEntry(await dmr.getEntry(widget.recordId!));
      }
      if (!mounted) return;
      setState(() => _loadingRecord = false);
      if (!_cashPurchase && _siteId != null && _vendorId != null) _loadOpen();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingRecord = false);
      showPmsSnack(context, e.message, error: true);
    }
  }

  void _applyImprest(Map<String, dynamic> doc) {
    final previous = List<_CashLine>.from(_cashLines);
    final next = <_CashLine>[];
    for (final raw in lineItemsOf(doc)) {
      final line = _CashLine();
      line.categoryId = idOf(raw['category_id']);
      final category = labelOf(raw['category_id'], fallback: '');
      line.categoryLabel = category == '—' ? '' : category;
      line.subId = idOf(raw['sub_category_id']);
      final sub = labelOf(raw['sub_category_id'], fallback: '');
      line.subLabel = sub == '—' ? '' : sub;
      line.uom = raw['uom'] is Map ? labelOf(raw['uom'], fallback: '') : _firstText([raw['uom']]);
      final qty = asNum(raw['qty']) ?? 0;
      final amount = asNum(raw['amount']) ?? 0;
      line.qty.text = _numText(qty);
      line.amount.text = _numText(amount);
      line.remark.text = raw['remark']?.toString() ?? '';
      next.add(line);
    }
    final other = doc['other_charges'] is Map ? Map<String, dynamic>.from(doc['other_charges'] as Map) : const {};
    final charges = asNum(other['charges']) ?? 0;
    final gstAmount = asNum(other['charges_gst']) ?? 0;
    final vendor = vendorNamesOf(doc);
    setState(() {
      _cashPurchase = true;
      _siteId = idOf(doc['site']);
      _siteLabel = labelOf(doc['site'], fallback: '');
      if (_siteLabel == '—') _siteLabel = '';
      _vendorId = idOf(doc['vendor_id']);
      _vendorLabel = vendor.isNotEmpty ? vendor : labelOf(doc['vendor_id'], fallback: '');
      if (_vendorLabel == '—') _vendorLabel = doc['vendor_name']?.toString() ?? '';
      _dmrNo.text = doc['dmr_no']?.toString() ?? '';
      _entryDate = _parseDate(doc['date'] ?? doc['invoice_date']) ?? _entryDate;
      _gate.text = doc['gate_register_entry']?.toString() ?? '';
      _gateDate = _parseDate(doc['gate_entry_date']);
      _entryTime = _parseTime(doc['gate_entry_time']?.toString() ?? '');
      final mode = doc['mode']?.toString().trim() ?? '';
      if (const {'Vehicle', 'Courier', 'Rail', 'Air', 'By Hand'}.contains(mode)) _modeValue = mode;
      _vehicle.text = doc['vehicle_number']?.toString() ?? '';
      _invoice.text = doc['invoice_number']?.toString() ?? '';
      _invoiceDate = _parseDate(doc['invoice_date']);
      _otherCharges.text = _numText(charges);
      if (charges > 0) {
        final rate = gstAmount * 100 / charges;
        _otherGst = _numText(rate);
        if (!_gstRates.contains(_otherGst)) _gstRates = [..._gstRates, _otherGst];
      }
      _existingDoc = doc['invoice_or_challan_doc']?.toString() ?? '';
      _cashLines
        ..clear()
        ..addAll(next.isEmpty ? [_CashLine()] : next);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final line in previous) {
        line.dispose();
      }
    });
  }

  Future<void> _applyEntry(Map<String, dynamic> doc) async {
    final previous = List<_DmrLine>.from(_lines);
    final lines = [for (final raw in lineItemsOf(doc)) _DmrLine.fromSaved(raw)];
    final hasInvoice = (doc['invoice_number']?.toString().trim() ?? '').isNotEmpty;
    final vendor = vendorNamesOf(doc);
    var poDate = '';
    var validTill = '';
    var org = '';
    final poId = mongoId(doc['requisition_order_id']);
    if (poId != null) {
      try {
        final po = await context.read<AppServices>().po.getById(poId);
        poDate = _dateLabel(_fromPoOrRevision(po, doc, ['poStartDate', 'po_date']));
        validTill = _dateLabel(_fromPoOrRevision(po, doc, ['due_date', 'due_Date']));
        org = _orgFrom(po);
      } on ApiException {
        // The entry still opens with the fields stored on the DMR.
      }
    }
    if (!mounted) return;
    setState(() {
      _cashPurchase = false;
      _siteId = idOf(doc['site']);
      _siteLabel = labelOf(doc['site'], fallback: '');
      if (_siteLabel == '—') _siteLabel = '';
      _vendorId = idOf(doc['vendor_id']);
      _vendorLabel = vendor.isNotEmpty ? vendor : labelOf(doc['vendor_id'], fallback: '');
      if (_vendorLabel == '—') _vendorLabel = '';
      _roId = idOf(doc['ro_id']);
      _roNumber = doc['ro_number']?.toString() ?? '';
      _roLabel = _roNumber;
      _poDate = poDate;
      _poValidTill = validTill;
      _orgName = org;
      final pr = '${doc['pr_type'] ?? doc['prType'] ?? ''}';
      if (const {'Project BOQ', 'Site Establishment', 'Assets'}.contains(pr)) _prType = pr;
      _orderType = '${doc['order_type']}' == 'Work Order' ? 'Work Order' : 'Purchase Order';
      _dmrNo.text = doc['dmr_no']?.toString() ?? '';
      _gate.text = doc['gate_register_entry']?.toString() ?? '';
      _gateDate = _parseDate(doc['gate_entry_date']);
      _gateTime.text = doc['gate_entry_time']?.toString() ?? '';
      _mode.text = doc['mode']?.toString() ?? '';
      _vehicle.text = doc['vehicle_number']?.toString() ?? '';
      _docket.text = doc['docker_number']?.toString() ?? '';
      _entryType = hasInvoice ? 'invoice' : 'challan';
      _invoice.text = doc['invoice_number']?.toString() ?? '';
      _invoiceDate = _parseDate(doc['invoice_date']);
      _challan.text = doc['challan_number']?.toString() ?? '';
      _challanDate = _parseDate(doc['challan_date']);
      _existingDoc = doc['invoice_or_challan_doc']?.toString() ?? '';
      _lines = lines;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final line in previous) {
        line.dispose();
      }
    });
  }

  @override
  void dispose() {
    _dmrNo.dispose();
    _challan.dispose();
    _invoice.dispose();
    _gate.dispose();
    _gateTime.dispose();
    _mode.dispose();
    _vehicle.dispose();
    _docket.dispose();
    _otherCharges.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    for (final line in _cashLines) {
      line.dispose();
    }
    super.dispose();
  }

  void _clearPo() {
    for (final line in _lines) {
      line.dispose();
    }
    _roId = null;
    _roLabel = '';
    _roNumber = '';
    _poDate = '';
    _poValidTill = '';
    _orgName = '';
    _lines = [];
    _dmrNo.clear();
  }

  Future<void> _loadOpen() async {
    if (_siteId == null || _vendorId == null || _cashPurchase) {
      if (mounted) setState(() => _open = []);
      return;
    }
    try {
      final open = await context.read<AppServices>().dmr.listOpenOrders({
        'site': _siteId,
        'vendor_id': _vendorId,
      });
      if (!mounted) return;
      setState(() => _open = open);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  String _poOptionLabel(Map<String, dynamic> row) {
    final label = _firstText([
      row['ro_number'],
      _asMap(row['requisition_order_id'])['po_number'],
      row['po_number'],
    ]);
    return label.isEmpty ? 'PO' : label;
  }

  String _vendorFrom(Map<String, dynamic> doc) {
    final detail = _asMap(doc['vendor_detail']);
    final named = _firstText([detail['vendor_name']]);
    if (named.isNotEmpty) return named;
    final totals = doc['vendors_total'];
    if (totals is! List) return '';
    Map<String, dynamic>? preferred;
    Map<String, dynamic>? matched;
    for (final row in totals) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      if (mongoId(map['vendor_id']) == _vendorId) matched = map;
      if (map['preferred'] == true) preferred ??= map;
    }
    final chosen = matched ?? preferred;
    if (chosen == null) return '';
    final label = labelOf(chosen['vendor_id'], fallback: '');
    return label == '—' ? '' : label;
  }

  dynamic _fromPoOrRevision(Map<String, dynamic> po, Map<String, dynamic> doc, List<String> keys) {
    final direct = firstNonNull(po, keys);
    if (direct != null && '$direct'.trim().isNotEmpty) return direct;
    final revisions = po['revisions'];
    if (revisions is List) {
      for (final row in revisions.reversed) {
        if (row is! Map) continue;
        final value = firstNonNull(Map<String, dynamic>.from(row), keys);
        if (value != null && '$value'.trim().isNotEmpty) return value;
      }
    }
    return firstNonNull(doc, keys);
  }

  String _orgFrom(Map<String, dynamic> po) {
    final billing = _asMap(po['billing_address']);
    final company = _firstText([billing['companyName'], billing['company_name']]);
    if (company.isNotEmpty) return company;
    final linked = labelOf(po['billing_address_id'], fallback: '');
    return linked == '—' ? '' : linked;
  }

  Future<void> _selectPo() async {
    if (_siteId == null || _vendorId == null) {
      showPmsSnack(context, 'Select vendor first', error: true);
      return;
    }
    if (_open.isEmpty) {
      showPmsSnack(context, 'No open POs for this site and vendor');
      return;
    }
    final picked = await showOptionPicker(
      context,
      title: 'PO number',
      options: mapToOptions(_open, labelOfRow: _poOptionLabel),
      selected: _roId,
    );
    if (picked == null || !mounted) return;
    setState(() => _loadingPo = true);
    try {
      final services = context.read<AppServices>();
      final doc = await services.dmr.getOrder(picked.value);
      if (!mounted) return;
      var po = _asMap(doc['requisition_order_id']);
      final poId = mongoId(doc['requisition_order_id']);
      if (poId != null) {
        try {
          po = await services.po.getById(poId);
        } on ApiException {
          // DMR snapshot is enough when the parent PO cannot be loaded.
        }
      }
      if (!mounted) return;
      final number = _firstText([
        po['po_number'],
        doc['ro_number'],
        _asMap(doc['requisition_order_id'])['po_number'],
        picked.label,
      ]);
      var nextNo = '';
      if (number.isNotEmpty) {
        try {
          final next = await services.dmr.nextEntryNumber({'ro_number': number});
          nextNo = _firstText([next['next_entry_number'], next['dmr_no'], next['number']]);
        } catch (_) {}
      }
      if (!mounted) return;
      final rawItems = asMapList(doc['items'] is List ? doc['items'] : const []);
      final poItems = asMapList(po['items'] is List ? po['items'] : const []);
      final items = rawItems.isNotEmpty ? rawItems : poItems;
      final siteName = labelOf(doc['site'] ?? po['site'], fallback: '');
      final vendorName = _firstText([_vendorFrom(doc), _vendorFrom(po), _vendorLabel]);
      final org = _orgFrom(po);
      for (final line in _lines) {
        line.dispose();
      }
      setState(() {
        _roId = picked.value;
        _roNumber = number;
        _roLabel = number.isEmpty ? picked.label : number;
        _poDate = _dateLabel(_fromPoOrRevision(po, doc, ['poStartDate', 'po_date']));
        _poValidTill = _dateLabel(_fromPoOrRevision(po, doc, ['due_date', 'due_Date']));
        _orgName = org;
        if (siteName.isNotEmpty && siteName != '—') _siteLabel = siteName;
        if (vendorName.isNotEmpty && vendorName != '—') _vendorLabel = vendorName;
        _prType = const {'Project BOQ', 'Site Establishment', 'Assets'}.contains('${doc['prType'] ?? po['prType'] ?? doc['pr_type']}')
            ? '${doc['prType'] ?? po['prType'] ?? doc['pr_type']}'
            : 'Site Establishment';
        _orderType = '${doc['order_type'] ?? po['order_type']}' == 'Work Order' ? 'Work Order' : 'Purchase Order';
        _lines = [for (final row in items) _DmrLine.fromPo(row)];
        if (nextNo.isNotEmpty) _dmrNo.text = nextNo;
        _loadingPo = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingPo = false);
      showPmsSnack(context, e.message, error: true);
    }
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $suffix';
  }

  Future<void> _loadCashNumber() async {
    if (!_cashPurchase || _siteId == null) return;
    try {
      final next = await context.read<AppServices>().dmr.nextImprestNumber({'site_id': _siteId});
      if (!mounted) return;
      final number = _firstText([next['next_imprest_order_number'], next['dmr_no']]);
      if (number.isNotEmpty) setState(() => _dmrNo.text = number);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _pickDate(void Function(DateTime) assign) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => assign(picked));
  }

  List<Map<String, dynamic>> _itemPayload() {
    return [
      for (final line in _lines)
        {
          if (line.itemId != null) 'item_id': line.itemId,
          'item_name': line.name,
          if (line.hsn.isNotEmpty) 'hsn_code': line.hsn,
          if (line.uom.isNotEmpty) 'uom': line.uom,
          'po_qty': line.poQty,
          'received_qty': num.tryParse(line.received.text.trim()) ?? 0,
          'accepted_qty': num.tryParse(line.accepted.text.trim()) ?? 0,
          'rejected_qty': num.tryParse(line.rejected.text.trim()) ?? 0,
          'rate': line.rate,
          'gst': line.gst,
          if (line.remark.text.trim().isNotEmpty) 'remark': line.remark.text.trim(),
        },
    ];
  }

  String? _numberError(
    String raw,
    String label, {
    bool required = true,
    bool positive = false,
    bool integer = false,
  }) {
    final text = raw.trim();
    if (text.isEmpty) return required ? '$label is required' : null;
    final value = num.tryParse(text);
    if (value == null) return '$label must be a number';
    if (integer && value != value.roundToDouble()) return '$label must be a whole number';
    if (value < 0) return '$label cannot be negative';
    if (positive && value <= 0) return '$label must be greater than 0';
    return null;
  }

  bool _validate() {
    _fieldErrors.clear();
    _fieldErrors.set('site', requiredSelection(_siteId, 'Site'));
    _fieldErrors.set('dmrNo', _dmrNo.text.trim().isEmpty ? 'DMR number is required' : null);
    if (_cashPurchase) {
      _fieldErrors.set('entryDate', requiredDate(_entryDate, 'Date'));
      _fieldErrors.set('vendor', requiredSelection(_vendorId, 'Vendor'));
      _fieldErrors.set(
        'gate',
        _numberError(_gate.text, 'Gate register entry no.', positive: true, integer: true),
      );
      _fieldErrors.set('gateDate', requiredDate(_gateDate, 'Gate entry date'));
      _fieldErrors.set('entryTime', _entryTime == null ? 'Entry time is required' : null);
      _fieldErrors.set('vehicle', _vehicle.text.trim().isEmpty ? 'Vehicle number is required' : null);
      _fieldErrors.set('invoice', _invoice.text.trim().isEmpty ? 'Bill / invoice no. is required' : null);
      _fieldErrors.set('invoiceDate', requiredDate(_invoiceDate, 'Bill / invoice date'));
      _fieldErrors.set(
        'document',
        _document == null && _existingDoc.isEmpty ? 'Upload the bill or challan' : null,
      );
      _fieldErrors.set('otherCharges', _numberError(_otherCharges.text, 'Other charges', required: false));
      if (_cashLines.isEmpty) {
        _fieldErrors.set('lines', 'Add at least one item');
      }
      for (var i = 0; i < _cashLines.length; i++) {
        final line = _cashLines[i];
        _fieldErrors.set('line${i}Category', requiredSelection(line.categoryId, 'Category'));
        _fieldErrors.set('line${i}Sub', requiredSelection(line.subId, 'Sub category'));
        _fieldErrors.set('line${i}Uom', line.uom.trim().isEmpty ? 'UOM is required' : null);
        _fieldErrors.set('line${i}Qty', _numberError(line.qty.text, 'Qty', positive: true));
        _fieldErrors.set('line${i}Amount', _numberError(line.amount.text, 'Total amount'));
      }
    } else {
      _fieldErrors.set('vendor', requiredSelection(_vendorId, 'Vendor'));
      if (!widget.isEdit) _fieldErrors.set('po', requiredSelection(_roId, 'PO number'));
      if (_roId != null && _lines.isEmpty) {
        _fieldErrors.set('items', 'This PO has no line items');
      }
      if (_gate.text.trim().isNotEmpty) {
        _fieldErrors.set(
          'gate',
          _numberError(_gate.text, 'Gate register entry no.', positive: true, integer: true, required: false),
        );
      }
      if (_entryType == 'invoice') {
        _fieldErrors.set('invoice', _invoice.text.trim().isEmpty ? 'Bill / invoice no. is required' : null);
        _fieldErrors.set(
          'document',
          _document == null && _existingDoc.isEmpty ? 'Upload the invoice' : null,
        );
      } else {
        _fieldErrors.set('challan', _challan.text.trim().isEmpty ? 'Challan number is required' : null);
      }
      for (var i = 0; i < _lines.length; i++) {
        final line = _lines[i];
        _fieldErrors.set('po${i}Received', _numberError(line.received.text, 'Received qty'));
        _fieldErrors.set('po${i}Accepted', _numberError(line.accepted.text, 'Accepted qty'));
        _fieldErrors.set('po${i}Rejected', _numberError(line.rejected.text, 'Rejected qty', required: false));
      }
    }
    return !_fieldErrors.hasErrors;
  }

  String _dmrFieldKey(String field) {
    const known = {
      'site': 'site',
      'vendor_id': 'vendor',
      'ro_id': 'po',
      'ro_number': 'po',
      'dmr_no': 'dmrNo',
      'gate_register_entry': 'gate',
      'gate_entry_date': 'gateDate',
      'gate_entry_time': 'entryTime',
      'vehicle_number': 'vehicle',
      'invoice_number': 'invoice',
      'invoice_date': 'invoiceDate',
      'date': 'entryDate',
      'challan_number': 'challan',
      'challan_date': 'challanDate',
      'invoice_or_challan_doc': 'document',
      'dmr_items': 'items',
      'other_charges.charges': 'otherCharges',
    };
    final direct = known[field];
    if (direct != null) return direct;
    final line = RegExp(r'^dmr_items\.(\d+)\.(\w+)$').firstMatch(field);
    if (line == null) return field;
    final index = line.group(1);
    return switch (line.group(2)) {
      'category_id' => 'line${index}Category',
      'sub_category_id' => 'line${index}Sub',
      'uom' => 'line${index}Uom',
      'qty' => 'line${index}Qty',
      'received_qty' => 'po${index}Received',
      'accepted_qty' => 'po${index}Accepted',
      'rejected_qty' => 'po${index}Rejected',
      'amount' => 'line${index}Amount',
      _ => 'line$index${line.group(2)}',
    };
  }

  void _applyApiErrors(ApiException error) {
    _fieldErrors.clear();
    for (final entry in apiFieldErrors(error).entries) {
      _fieldErrors.set(_dmrFieldKey(entry.key), entry.value);
    }
  }

  Future<void> _confirmSaved(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.isEdit ? 'DMR updated' : 'DMR created'),
        content: Text(message),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    if (mounted) context.pop(widget.isEdit ? true : null);
  }

  Future<void> _save() async {
    if (!_validate()) {
      setState(() {});
      showPmsSnack(context, _fieldErrors.messages.first, error: true);
      return;
    }
    if (_cashPurchase) {
      final items = <Map<String, dynamic>>[
        for (final line in _cashLines)
          {
            'category_id': line.categoryId,
            'sub_category_id': line.subId,
            'uom': line.uom,
            'qty': num.tryParse(line.qty.text.trim()) ?? 0,
            'amount': num.tryParse(line.amount.text.trim()) ?? 0,
            if (line.remark.text.trim().isNotEmpty) 'remark': line.remark.text.trim(),
          },
      ];
      final charges = num.tryParse(_otherCharges.text.trim()) ?? 0;
      final gstRate = num.tryParse(_otherGst) ?? 0;
      final gstAmount = charges * gstRate / 100;
      final otherTotal = charges + gstAmount;
      final itemsTotal = items.fold<num>(0, (sum, row) => sum + (row['amount'] as num));
      final cashPayload = {
        'site': _siteId,
        'dmr_no': _dmrNo.text.trim(),
        'invoice_number': _invoice.text.trim(),
        'invoice_date': isoDateOnly(_invoiceDate),
        'date': isoDateOnly(_entryDate),
        'vendor_id': _vendorId,
        'vendor_name': _vendorLabel,
        'gate_register_entry': _gate.text.trim(),
        'gate_entry_date': isoDateOnly(_gateDate),
        'gate_entry_time': _formatTime(_entryTime!),
        'mode': _modeValue,
        'vehicle_number': _vehicle.text.trim(),
        'dmr_items': items,
        'other_charges': {
          'charges': charges,
          'charges_gst': gstAmount,
          'total_other_charges': otherTotal,
        },
        'total_amount': itemsTotal + otherTotal,
        if (_document == null && _existingDoc.isNotEmpty) 'invoice_or_challan_doc': _existingDoc,
      };
      setState(() => _saving = true);
      try {
        final dmr = context.read<AppServices>().dmr;
        if (widget.isEdit) {
          await dmr.updateImprest(widget.recordId!, cashPayload, document: _document?.toEntry());
        } else {
          await dmr.createImprest(cashPayload, document: _document!.toEntry());
        }
        if (!mounted) return;
        await _confirmSaved(widget.isEdit ? 'Cash purchase updated' : 'Cash purchase DMR created');
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _applyApiErrors(e));
        showPmsSnack(context, _fieldErrors.hasErrors ? formatApiErrorSummary(e) : e.message, error: true);
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    final isInvoice = _entryType == 'invoice';
    final payload = {
      'site': _siteId,
      'vendor_id': _vendorId,
      'ro_id': _roId,
      'ro_number': _roNumber,
      'pr_type': _prType,
      'order_type': _orderType,
      'dmr_no': _dmrNo.text.trim(),
      if (_gate.text.trim().isNotEmpty) 'gate_register_entry': _gate.text.trim(),
      if (_gateDate != null) 'gate_entry_date': isoDateOnly(_gateDate),
      if (_gateTime.text.trim().isNotEmpty) 'gate_entry_time': _gateTime.text.trim(),
      if (_mode.text.trim().isNotEmpty) 'mode': _mode.text.trim(),
      if (_vehicle.text.trim().isNotEmpty) 'vehicle_number': _vehicle.text.trim(),
      if (_docket.text.trim().isNotEmpty) 'docker_number': _docket.text.trim(),
      'dmr_items': _itemPayload(),
    };

    final entryPayload = {
      ...payload,
      if (isInvoice) 'invoice_number': _invoice.text.trim(),
      if (isInvoice && _invoiceDate != null) 'invoice_date': isoDateOnly(_invoiceDate),
      if (!isInvoice) 'challan_number': _challan.text.trim(),
      if (!isInvoice && _challanDate != null) 'challan_date': isoDateOnly(_challanDate),
      if (_document == null && _existingDoc.isNotEmpty) 'invoice_or_challan_doc': _existingDoc,
    };
    setState(() => _saving = true);
    try {
      final dmr = context.read<AppServices>().dmr;
      if (widget.isEdit) {
        await dmr.updateEntry(widget.recordId!, entryPayload, document: _document?.toEntry());
      } else if (isInvoice) {
        await dmr.createInvoice(entryPayload, document: _document!.toEntry());
      } else {
        await dmr.createChallan(entryPayload, document: _document?.toEntry());
      }
      if (!mounted) return;
      await _confirmSaved(
        widget.isEdit
            ? 'DMR updated'
            : (isInvoice ? 'Invoice DMR created' : 'Challan created'),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _applyApiErrors(e));
      showPmsSnack(context, _fieldErrors.hasErrors ? formatApiErrorSummary(e) : e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _cashPurchaseForm() {
    final charges = num.tryParse(_otherCharges.text.trim()) ?? 0;
    final gstRate = num.tryParse(_otherGst) ?? 0;
    final otherTotal = charges + (charges * gstRate / 100);
    final itemsTotal = _cashLines.fold<num>(
      0,
      (sum, line) => sum + (num.tryParse(line.amount.text.trim()) ?? 0),
    );
    return _DmrCard(
      title: 'Cash purchase — DMR entry',
      child: Column(
        children: [
          _LockedField(label: 'Site', value: _siteLabel),
          const SizedBox(height: 12),
          PickerField(
            label: 'Vendor',
            required: true,
            hint: 'Select vendor',
            valueLabel: _vendorLabel,
            errorText: _fieldErrors['vendor'],
            onTap: () async {
              final picked = await showOptionPicker(
                context,
                title: 'Vendor',
                options: mapToOptions(
                  _vendors,
                  labelOfRow: (r) => r['vendor_name']?.toString() ?? labelOf(r),
                ),
                selected: _vendorId,
                emptyMessage: 'No vendors found',
              );
              if (picked == null) return;
              setState(() {
                _vendorId = picked.value;
                _vendorLabel = picked.label;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dmrNo,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'DMR no *',
              hintText: 'Auto-generated DMR',
              errorText: _fieldErrors['dmrNo'],
            ),
          ),
          const SizedBox(height: 12),
          _DateField(
            label: 'Date *',
            value: _entryDate,
            errorText: _fieldErrors['entryDate'],
            onTap: () => _pickDate((d) => _entryDate = d),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gate,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Gate register entry no. *',
              hintText: 'e.g. 1024',
              errorText: _fieldErrors['gate'],
            ),
          ),
          const SizedBox(height: 12),
          _DateField(
            label: 'Gate entry date *',
            value: _gateDate,
            errorText: _fieldErrors['gateDate'],
            onTap: () => _pickDate((d) => _gateDate = d),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: _entryTime ?? TimeOfDay.now());
              if (picked == null) return;
              setState(() => _entryTime = picked);
            },
            child: InputDecorator(
              isEmpty: _entryTime == null,
              decoration: InputDecoration(
                labelText: 'Entry time *',
                hintText: '--:-- --',
                suffixIcon: const Icon(Icons.access_time),
                errorText: _fieldErrors['entryTime'],
              ),
              child: Text(_entryTime == null ? '' : _formatTime(_entryTime!)),
            ),
          ),
          const SizedBox(height: 12),
          AppDropdownFormField<String>(
            key: ValueKey('mode-$_modeValue'),
            initialValue: _modeValue,
            decoration: const InputDecoration(labelText: 'Mode *'),
            items: const [
              DropdownMenuItem(value: 'Vehicle', child: Text('Vehicle')),
              DropdownMenuItem(value: 'Courier', child: Text('Courier')),
              DropdownMenuItem(value: 'Rail', child: Text('Rail')),
              DropdownMenuItem(value: 'Air', child: Text('Air')),
              DropdownMenuItem(value: 'By Hand', child: Text('By Hand')),
            ],
            onChanged: (v) => setState(() => _modeValue = v ?? _modeValue),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _vehicle,
            decoration: InputDecoration(
              labelText: 'Vehicle number *',
              hintText: 'e.g. DL01CD5678',
              errorText: _fieldErrors['vehicle'],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _invoice,
            decoration: InputDecoration(
              labelText: 'Bill / invoice no. *',
              hintText: 'e.g. INV-2026-1042',
              errorText: _fieldErrors['invoice'],
            ),
          ),
          const SizedBox(height: 12),
          _DateField(
            label: 'Bill / invoice date *',
            value: _invoiceDate,
            errorText: _fieldErrors['invoiceDate'],
            onTap: () => _pickDate((d) => _invoiceDate = d),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final files = await showAttachmentPicker(context, allowMultiple: false);
              if (files.isEmpty) return;
              setState(() => _document = files.first);
            },
            icon: const Icon(Icons.upload_file),
            label: Text(
              _document?.filename ?? (_existingDoc.isNotEmpty ? 'Document attached' : 'Upload invoice/challan'),
            ),
          ),
          if (_fieldErrors['document'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_fieldErrors['document']!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
            ),
          const SizedBox(height: 16),
          for (var i = 0; i < _cashLines.length; i++) ...[
            Row(
              children: [
                Text('Line ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  tooltip: 'Delete line',
                  onPressed: () {
                    final removed = _cashLines.removeAt(i);
                    setState(() {});
                    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
                  },
                  icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                ),
              ],
            ),
            PickerField(
              label: 'Category',
              required: true,
              hint: 'Search material category',
              valueLabel: _cashLines[i].categoryLabel,
              errorText: _fieldErrors['line${i}Category'],
              onTap: () async {
                final picked = await showOptionPicker(
                  context,
                  title: 'Category',
                  options: mapToOptions(_categories, labelOfRow: (r) => r['name']?.toString() ?? labelOf(r)),
                  selected: _cashLines[i].categoryId,
                );
                if (picked == null) return;
                setState(() {
                  _cashLines[i].categoryId = picked.value;
                  _cashLines[i].categoryLabel = picked.label;
                  _cashLines[i].subId = null;
                  _cashLines[i].subLabel = '';
                });
              },
            ),
            const SizedBox(height: 8),
            PickerField(
              label: 'Sub category',
              required: true,
              hint: 'Search material sub-category',
              valueLabel: _cashLines[i].subLabel,
              errorText: _fieldErrors['line${i}Sub'],
              enabled: _cashLines[i].categoryId != null,
              onTap: () async {
                final categoryId = _cashLines[i].categoryId;
                if (categoryId == null) return;
                final rows = await context.read<SettingsApis>().subCategories.listAll({
                  'category': categoryId,
                  'sortBy': 'subcategory_name',
                  'sortOrder': 'asc',
                });
                if (!mounted) return;
                final picked = await showOptionPicker(
                  context,
                  title: 'Sub category',
                  options: mapToOptions(
                    rows,
                    labelOfRow: (r) => r['subcategory_name']?.toString() ?? labelOf(r),
                  ),
                  selected: _cashLines[i].subId,
                  emptyMessage: 'No sub categories for this category',
                );
                if (picked == null) return;
                setState(() {
                  _cashLines[i].subId = picked.value;
                  _cashLines[i].subLabel = picked.label;
                });
              },
            ),
            const SizedBox(height: 8),
            PickerField(
              label: 'UOM',
              valueLabel: _cashLines[i].uom,
              hint: 'UOM',
              errorText: _fieldErrors['line${i}Uom'],
              onTap: () async {
                final picked = await showOptionPicker(
                  context,
                  title: 'UOM',
                  options: mapToOptions(_uoms, labelOfRow: (r) => r['uom_name']?.toString() ?? labelOf(r)),
                );
                if (picked == null) return;
                setState(() => _cashLines[i].uom = picked.label);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cashLines[i].qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Qty *', errorText: _fieldErrors['line${i}Qty']),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cashLines[i].amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Total amount *', errorText: _fieldErrors['line${i}Amount']),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cashLines[i].remark,
              decoration: const InputDecoration(labelText: 'Remarks'),
              maxLines: 2,
            ),
            const Divider(height: 24),
          ],
          if (_fieldErrors['lines'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_fieldErrors['lines']!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _cashLines.add(_CashLine())),
              icon: const Icon(Icons.add),
              label: const Text('Add item'),
            ),
          ),
          TextField(
            controller: _otherCharges,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Other charges (₹)', errorText: _fieldErrors['otherCharges']),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          AppDropdownFormField<String>(
            initialValue: _gstRates.contains(_otherGst) ? _otherGst : _gstRates.first,
            decoration: const InputDecoration(labelText: 'Select other charges GST'),
            items: [
              for (final rate in _gstRates) DropdownMenuItem(value: rate, child: Text(rate)),
            ],
            onChanged: (v) => setState(() => _otherGst = v ?? '0'),
          ),
          const SizedBox(height: 12),
          _LockedField(label: 'Total other charges (₹)', value: otherTotal.toStringAsFixed(2)),
          _LockedField(label: 'Total amount (₹)', value: (itemsTotal + otherTotal).toStringAsFixed(2)),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saveLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final poReady = _siteId != null && _vendorId != null && !_cashPurchase;
    return Scaffold(
      appBar: AppBar(title: Text(widget.isEdit ? 'Edit DMR' : 'Create DMR')),
      body: _loadingRecord
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: AppTheme.formPadding,
        children: [
          if (_fieldErrors.hasErrors) ValidationSummaryBanner(messages: _fieldErrors.messages),
          _DmrCard(
            title: 'Search the PO Number',
            child: Column(
              children: [
                PickerField(
                  label: 'Select Site',
                  required: true,
                  valueLabel: _siteLabel,
                  errorText: _fieldErrors['site'],
                  onTap: () async {
                    final p = await showOptionPicker(
                      context,
                      title: 'Select Site',
                      options: mapSiteRowsToOptions(_sites),
                      selected: _siteId,
                    );
                    if (p == null) return;
                    setState(() {
                      _siteId = p.value;
                      _siteLabel = p.label;
                      _clearPo();
                    });
                    if (_cashPurchase) {
                      if (!widget.isEdit) _loadCashNumber();
                    } else {
                      _loadOpen();
                    }
                  },
                ),
                if (!_cashPurchase) ...[
                  const SizedBox(height: 12),
                  PickerField(
                    label: 'Select Vendor',
                    required: true,
                    valueLabel: _vendorLabel,
                    errorText: _fieldErrors['vendor'],
                    onTap: () async {
                      final p = await showOptionPicker(
                        context,
                        title: 'Select Vendor',
                        options: mapToOptions(
                          _vendors,
                          labelOfRow: (r) => r['vendor_name']?.toString() ?? labelOf(r),
                        ),
                        selected: _vendorId,
                      );
                      if (p == null) return;
                      setState(() {
                        _vendorId = p.value;
                        _vendorLabel = p.label;
                        _clearPo();
                      });
                      _loadOpen();
                    },
                  ),
                  const SizedBox(height: 12),
                  PickerField(
                    label: 'PO Number',
                    required: true,
                    enabled: poReady,
                    hint: poReady ? 'Select…' : 'Select vendor first',
                    valueLabel: poReady ? _roLabel : '',
                    errorText: _fieldErrors['po'],
                    onTap: _selectPo,
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Cash Purchase'),
                  value: _cashPurchase,
                  onChanged: widget.isEdit
                      ? null
                      : (v) {
                          setState(() {
                            _cashPurchase = v ?? false;
                            _clearPo();
                            _open = [];
                          });
                          if (v == true) _loadCashNumber();
                        },
                ),
              ],
            ),
          ),
          if (!_cashPurchase) ...[
            const SizedBox(height: 12),
            _DmrCard(
              title: 'PO Details',
              child: Column(
                children: [
                  _LockedField(label: 'PO Number', value: _roNumber),
                  _LockedField(label: 'PO Date', value: _poDate),
                  _LockedField(label: 'PO Valid till Date', value: _poValidTill),
                  _LockedField(label: 'Name Of Org', value: _orgName),
                  _LockedField(label: 'Site', value: _siteLabel),
                  _LockedField(label: 'Vendor Name', value: _vendorLabel),
                ],
              ),
            ),
          ],
          if (_loadingPo) const LinearProgressIndicator(minHeight: 2),
          if (_cashPurchase && _siteId != null) ...[
            const SizedBox(height: 12),
            _cashPurchaseForm(),
          ],
          if (_roId != null || (widget.isEdit && !_cashPurchase)) ...[
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'challan', label: Text('Challan')),
                ButtonSegment(value: 'invoice', label: Text('Invoice')),
              ],
              selected: {_entryType},
              onSelectionChanged: (s) => setState(() => _entryType = s.first),
            ),
            const SizedBox(height: 12),
            _DmrCard(
              title: 'Gate entry',
              child: Column(
                children: [
                  TextField(
                    controller: _gate,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Gate register entry no.',
                      hintText: 'e.g. 1024',
                      errorText: _fieldErrors['gate'],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DateField(
                    label: 'Gate entry date',
                    value: _gateDate,
                    errorText: _fieldErrors['gateDate'],
                    onTap: () => _pickDate((d) => _gateDate = d),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _vehicle,
                    decoration: InputDecoration(
                      labelText: 'Vehicle number',
                      hintText: 'e.g. DL01CD5678',
                      errorText: _fieldErrors['vehicle'],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _DmrCard(
              title: _entryType == 'invoice' ? 'Invoice' : 'Challan',
              child: Column(
                children: [
                  TextField(
                    controller: _dmrNo,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'DMR no *',
                      hintText: 'Auto-generated DMR',
                      errorText: _fieldErrors['dmrNo'],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_entryType == 'invoice') ...[
                    TextField(
                      controller: _invoice,
                      decoration: InputDecoration(
                        labelText: 'Bill / invoice no. *',
                        hintText: 'e.g. INV-2026-1042',
                        errorText: _fieldErrors['invoice'],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _DateField(
                      label: 'Bill / invoice date',
                      value: _invoiceDate,
                      errorText: _fieldErrors['invoiceDate'],
                      onTap: () => _pickDate((d) => _invoiceDate = d),
                    ),
                  ] else ...[
                    TextField(
                      controller: _challan,
                      decoration: InputDecoration(
                        labelText: 'Challan number *',
                        errorText: _fieldErrors['challan'],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _DateField(
                      label: 'Challan date',
                      value: _challanDate,
                      errorText: _fieldErrors['challanDate'],
                      onTap: () => _pickDate((d) => _challanDate = d),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final files = await showAttachmentPicker(context, allowMultiple: false);
                      if (files.isEmpty) return;
                      setState(() => _document = files.first);
                    },
                    icon: const Icon(Icons.upload_file),
                    label: Text(
              _document?.filename ?? (_existingDoc.isNotEmpty ? 'Document attached' : 'Upload invoice/challan'),
            ),
                  ),
                  if (_fieldErrors['document'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_fieldErrors['document']!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                    ),
                  if (_fieldErrors['items'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_fieldErrors['items']!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                    ),
                ],
              ),
            ),
            if (_lines.isNotEmpty) ...[
              const SizedBox(height: 12),
              _DmrCard(
                title: 'Items',
                child: Column(
                  children: [
                    for (var i = 0; i < _lines.length; i++) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_lines[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                        Text(
                        [
                          if (_lines[i].hsn.isNotEmpty) 'HSN ${_lines[i].hsn}',
                          if (_lines[i].uom.isNotEmpty) 'UOM ${_lines[i].uom}',
                          'PO qty ${_lines[i].poQty}',
                          if (_lines[i].alreadyReceived > 0) 'Already ${_lines[i].alreadyReceived}',
                          'Rate ${_lines[i].rate}',
                          if (_lines[i].gst > 0) 'GST ${_lines[i].gst}',
                        ].join(' · '),
                        style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _lines[i].received,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: 'Received qty *', errorText: _fieldErrors['po${i}Received']),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _lines[i].accepted,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: 'Accepted qty *', errorText: _fieldErrors['po${i}Accepted']),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _lines[i].rejected,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: 'Rejected qty', errorText: _fieldErrors['po${i}Rejected']),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _lines[i].remark,
                        decoration: const InputDecoration(labelText: 'Remark'),
                      ),
                      const Divider(height: 24),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saveLabel),
            ),
          ],
        ],
      ),
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

String _firstText(List<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null' || text == '—') continue;
    return text;
  }
  return '';
}

String _dateLabel(dynamic value) {
  if (value == null) return '';
  final formatted = formatDate(value);
  return formatted == '—' ? '' : formatted;
}

String _uomOf(Map<String, dynamic> row, Map<String, dynamic>? item) {
  for (final value in [row['uom'], row['uom_id'], item?['uom']]) {
    final label = labelOf(value, fallback: '');
    if (label.isNotEmpty && label != '—') return label;
  }
  return '';
}

num? _gstOf(dynamic value) {
  final direct = asNum(value);
  if (direct != null) return direct;
  if (value is Map) return asNum(value['gst_percentage'] ?? value['percentage']);
  return null;
}

class _DmrCard extends StatelessWidget {
  const _DmrCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _LockedField extends StatelessWidget {
  const _LockedField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final empty = value.trim().isEmpty || value == '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: '$label *',
          filled: true,
          hintText: empty ? 'Auto-filled from PO' : null,
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
        isEmpty: empty,
        child: empty
            ? const SizedBox.shrink()
            : Text(value, style: const TextStyle(color: AppTheme.primary)),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap, this.errorText});

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final empty = value == null;
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        isEmpty: empty,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'DD/MM/YYYY',
          suffixIcon: const Icon(Icons.calendar_today_outlined),
          errorText: errorText,
        ),
        child: empty
            ? const SizedBox.shrink()
            : Text(formatDate(value!.toIso8601String())),
      ),
    );
  }
}

class _DmrLine {
  _DmrLine({
    required this.name,
    required this.poQty,
    required num openQty,
    this.itemId,
    this.hsn = '',
    this.uom = '',
    this.rate = 0,
    this.gst = 0,
    this.alreadyReceived = 0,
  })  : received = TextEditingController(text: '$openQty'),
        accepted = TextEditingController(text: '$openQty'),
        rejected = TextEditingController(text: '0');

  factory _DmrLine.fromSaved(Map<String, dynamic> row) {
    final line = _DmrLine.fromPo(row);
    final received = asNum(row['received_qty']);
    final accepted = asNum(row['accepted_qty']);
    final rejected = asNum(row['rejected_qty']);
    if (received != null) {
      line.received.text = received == received.roundToDouble() ? received.toInt().toString() : received.toString();
    }
    if (accepted != null) {
      line.accepted.text = accepted == accepted.roundToDouble() ? accepted.toInt().toString() : accepted.toString();
    }
    if (rejected != null) {
      line.rejected.text = rejected == rejected.roundToDouble() ? rejected.toInt().toString() : rejected.toString();
    }
    line.remark.text = row['remark']?.toString() ?? '';
    return line;
  }

  factory _DmrLine.fromPo(Map<String, dynamic> row) {
    final item = row['item_id'] is Map ? Map<String, dynamic>.from(row['item_id'] as Map) : null;
    final qty = asNum(firstNonNull(row, ['po_qty', 'qty', 'quantity'])) ?? 0;
    final already = asNum(row['received_qty']) ?? 0;
    final open = qty > already ? qty - already : qty;
    return _DmrLine(
      itemId: mongoId(row['item_id'] ?? row['item']),
      name: itemLabel(row),
      hsn: _firstText([row['hsn_code'], row['HSNcode'], item?['HSNcode'], item?['hsn_code']]),
      uom: _uomOf(row, item),
      poQty: qty,
      openQty: open,
      alreadyReceived: already,
      rate: asNum(row['rate']) ?? 0,
      gst: _gstOf(row['gst']) ?? _gstOf(item?['gst']) ?? 0,
    );
  }

  final String? itemId;
  final String name;
  final String hsn;
  final String uom;
  final num poQty;
  final num alreadyReceived;
  final num rate;
  final num gst;
  final TextEditingController received;
  final TextEditingController accepted;
  final TextEditingController rejected;
  final remark = TextEditingController();

  void dispose() {
    received.dispose();
    accepted.dispose();
    rejected.dispose();
    remark.dispose();
  }
}

class _CashLine {
  String? categoryId;
  String categoryLabel = '';
  String? subId;
  String subLabel = '';
  String uom = '';
  final qty = TextEditingController(text: '1');
  final amount = TextEditingController();
  final remark = TextEditingController();

  void dispose() {
    qty.dispose();
    amount.dispose();
    remark.dispose();
  }
}
