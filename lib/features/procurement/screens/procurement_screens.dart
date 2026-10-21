import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/utils/form_validation_helpers.dart';
import '../../../core/utils/list_query.dart';
import '../../../core/utils/share_bytes.dart';
import '../../../core/theme/modern_widgets.dart';
import '../../app/app_services.dart';
import '../../app/app_shell.dart';
import '../../pms/utils/site_options.dart';
import '../../pms/widgets/media_widgets.dart';
import '../../pms/widgets/pickers.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../../settings/services/settings_apis.dart';

export 'procurement_home_screen.dart';

class _RrRowActions extends StatelessWidget {
  const _RrRowActions({required this.status, required this.onDelete});

  final String? status;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusChip(status: status),
        if (onDelete != null)
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'delete') onDelete?.call();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: AppTheme.danger)),
              ),
            ],
          ),
      ],
    );
  }
}

const _rrPrTypes = ['Project BOQ', 'Site Establishment', 'Assets'];

const _rrSortOptions = <({String by, String order, String label})>[
  (by: 'createdAt', order: 'desc', label: 'Newest'),
  (by: 'createdAt', order: 'asc', label: 'Oldest'),
  (
    by: 'requisition_request_number',
    order: 'desc',
    label: 'PR number high–low',
  ),
  (by: 'requisition_request_number', order: 'asc', label: 'PR number low–high'),
  (by: 'title', order: 'asc', label: 'Title A–Z'),
  (by: 'title', order: 'desc', label: 'Title Z–A'),
  (by: 'prType', order: 'asc', label: 'PR type'),
  (by: 'site', order: 'asc', label: 'Site'),
  (by: 'date', order: 'desc', label: 'Date newest'),
  (by: 'date', order: 'asc', label: 'Date oldest'),
  (by: 'expected_delivery_date', order: 'asc', label: 'Expected delivery'),
];

class RrListScreen extends StatefulWidget {
  const RrListScreen({super.key, this.status});
  final String? status;

  @override
  State<RrListScreen> createState() => _RrListScreenState();
}

class _RrListScreenState extends State<RrListScreen> {
  String _tab = 'all';
  String _search = '';
  String? _siteId;
  String _siteLabel = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String? _prType;
  String? _itemId;
  String _itemLabel = '';
  String _sortBy = 'createdAt';
  String _sortOrder = 'desc';
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _catalogItems = [];
  int _page = 1;
  int _motion = 0;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _pagination;
  Map<String, dynamic> _counts = {};

  String get _sortLabel {
    for (final option in _rrSortOptions) {
      if (option.by == _sortBy && option.order == _sortOrder)
        return option.label;
    }
    return 'Sort';
  }

  String get _dateLabel {
    if (_dateFrom == null && _dateTo == null) return 'Date range';
    final from = _dateFrom == null ? '…' : formatDate(_dateFrom);
    final to = _dateTo == null ? '…' : formatDate(_dateTo);
    return '$from – $to';
  }

  Map<String, dynamic> _query({required bool paged}) {
    return {
      if (paged) 'page': _page,
      if (paged) 'limit': 20,
      ...rrSearchQuery(_search),
      if (_siteId != null) 'site': _siteId,
      if (_prType != null) 'prType': _prType,
      if (_itemId != null) 'item_id': _itemId,
      if (_dateFrom != null) 'dateFrom': isoDateOnly(_dateFrom),
      if (_dateTo != null) 'dateTo': isoDateOnly(_dateTo),
      if (paged && _tab != 'all') 'status': _tab,
      if (paged) 'sortBy': _sortBy,
      if (paged) 'sortOrder': _sortOrder,
    };
  }

  @override
  void initState() {
    super.initState();
    _tab = widget.status ?? 'all';
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final sites = await loadSiteOptions(context);
        if (!mounted) return;
        setState(() {
          _sites = [
            for (final o in sites)
              o.raw ?? {'_id': o.value, 'site_name': o.label},
          ];
        });
      } catch (_) {}
      if (mounted) _load();
    });
  }

  Future<void> _pickSite() async {
    final picked = await showOptionPicker(
      context,
      title: 'Site',
      options: [
        const OptionItem(value: '', label: 'All sites'),
        ...mapSiteRowsToOptions(_sites),
      ],
      selected: _siteId ?? '',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _siteId = picked.value.isEmpty ? null : picked.value;
      _siteLabel = picked.value.isEmpty ? '' : picked.label;
      _page = 1;
    });
    _load();
  }

  Future<void> _pickDates() async {
    final result = await showDialog<({DateTime? from, DateTime? to})>(
      context: context,
      builder: (context) => _DateRangeDialog(from: _dateFrom, to: _dateTo),
    );
    if (result == null || !mounted) return;
    setState(() {
      _dateFrom = result.from;
      _dateTo = result.to;
      _page = 1;
    });
    _load();
  }

  Future<void> _pickPrType() async {
    final picked = await showOptionPicker(
      context,
      title: 'PR type',
      options: [
        const OptionItem(value: '', label: 'All types'),
        for (final type in _rrPrTypes) OptionItem(value: type, label: type),
      ],
      selected: _prType ?? '',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _prType = picked.value.isEmpty ? null : picked.value;
      _page = 1;
    });
    _load();
  }

  Future<void> _pickItem() async {
    if (_catalogItems.isEmpty) {
      try {
        _catalogItems = await context.read<SettingsApis>().items.listAll(const {
          'sortBy': 'item_name',
          'sortOrder': 'asc',
        });
      } on ApiException catch (e) {
        if (mounted) showPmsSnack(context, e.message, error: true);
        return;
      }
    }
    if (!mounted) return;
    final picked = await showOptionPicker(
      context,
      title: 'Item',
      options: [
        const OptionItem(value: '', label: 'All items'),
        ...mapToOptions(
          _catalogItems,
          labelOfRow: (row) => row['item_name']?.toString() ?? labelOf(row),
        ),
      ],
      selected: _itemId ?? '',
      emptyMessage: 'No items found',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _itemId = picked.value.isEmpty ? null : picked.value;
      _itemLabel = picked.value.isEmpty ? '' : picked.label;
      _page = 1;
    });
    _load();
  }

  Future<void> _pickSort() async {
    final picked = await showOptionPicker(
      context,
      title: 'Sort',
      options: [
        for (final option in _rrSortOptions)
          OptionItem(
            value: '${option.by}|${option.order}',
            label: option.label,
          ),
      ],
      selected: '$_sortBy|$_sortOrder',
    );
    if (picked == null || !mounted) return;
    final parts = picked.value.split('|');
    if (parts.length != 2) return;
    setState(() {
      _sortBy = parts[0];
      _sortOrder = parts[1];
      _page = 1;
    });
    _load();
  }

  Future<void> _deleteRequisition(String id) async {
    final ok = await confirmAction(
      context,
      title: 'Delete requisition',
      message: 'Delete this requisition? This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<AppServices>().rr.delete(id);
      if (!mounted) return;
      showPmsSnack(context, 'Requisition deleted');
      _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AppServices>().rr;
      final results = await Future.wait([
        api.list(_query(paged: true)),
        api.statusCounts(_query(paged: false)),
      ]);
      if (!mounted) return;
      final list = results[0] as PaginatedResult;
      setState(() {
        _items = list.items;
        _pagination = list.pagination;
        _counts = results[1] as Map<String, dynamic>;
        _loading = false;
        _motion += 1;
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
    final counts = _counts['statusCounts'] is Map
        ? Map<String, dynamic>.from(_counts['statusCounts'] as Map)
        : _counts;
    return Scaffold(
      appBar: AppBar(
        title: const StaggeredEntrance(
          maxIndex: 0,
          slide: 12,
          child: EntranceItem(index: 0, child: Text('Requisitions')),
        ),
        actions: const [PressScale(child: WorkspaceSwitcherButton())],
      ),
      floatingActionButton: PressScale(
        child: FloatingActionButton(
          onPressed: () async {
            final created = await context.push<bool>('/procurement/rr/new');
            if (created == true && mounted) _load();
          },
          child: const Icon(Icons.add),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StaggeredEntrance(
            maxIndex: 2,
            slide: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EntranceItem(
                  index: 0,
                  child: Padding(
                    padding: AppTheme.searchPadding,
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search PR number, title or site…',
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
                ),
                EntranceItem(
                  index: 1,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        PressScale(
                          child: ActionChip(
                            avatar: const Icon(
                              Icons.location_on_outlined,
                              size: 18,
                            ),
                            label: Text(
                              _siteId == null ? 'All sites' : _siteLabel,
                            ),
                            onPressed: _pickSite,
                          ),
                        ),
                        const SizedBox(width: 8),
                        PressScale(
                          child: ActionChip(
                            avatar: const Icon(
                              Icons.date_range_outlined,
                              size: 18,
                            ),
                            label: Text(_dateLabel),
                            onPressed: _pickDates,
                          ),
                        ),
                        const SizedBox(width: 8),
                        PressScale(
                          child: ActionChip(
                            avatar: const Icon(
                              Icons.category_outlined,
                              size: 18,
                            ),
                            label: Text(_prType ?? 'PR type'),
                            onPressed: _pickPrType,
                          ),
                        ),
                        const SizedBox(width: 8),
                        PressScale(
                          child: ActionChip(
                            avatar: const Icon(
                              Icons.inventory_2_outlined,
                              size: 18,
                            ),
                            label: Text(_itemId == null ? 'Item' : _itemLabel),
                            onPressed: _pickItem,
                          ),
                        ),
                        const SizedBox(width: 8),
                        PressScale(
                          child: ActionChip(
                            avatar: const Icon(Icons.sort, size: 18),
                            label: Text(_sortLabel),
                            onPressed: _pickSort,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                EntranceItem(
                  index: 2,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: AppTheme.chipRowPadding,
                    child: Row(
                      children: [
                        for (final t in [
                          'all',
                          'draft',
                          'pending',
                          'revise',
                          'approved',
                          'revised',
                          'rejected',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: PressScale(
                              child: ChoiceChip(
                                label: Text(
                                  t == 'all'
                                      ? 'All (${_counts['total'] ?? ''})'
                                      : '$t (${counts[t] ?? ''})',
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
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SoftAppear(
                child: ErrorBanner(message: _error!, onRetry: _load),
              ),
            ),
          Expanded(
            child: StaggeredEntrance(
              active: !_loading,
              replayToken: _motion,
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading
                    ? const CenteredScrollLoader()
                    : _items.isEmpty
                    ? EntranceItem(
                        index: 0,
                        child: EmptyListBody(
                          message: listEmptyMessage(
                            noun: 'requisitions',
                            search: _search,
                            filterLabel: [
                              if (_tab != 'all') _tab,
                              if (_siteId != null) 'selected site',
                              if (_prType != null) _prType,
                              if (_itemId != null) 'selected item',
                              if (_dateFrom != null || _dateTo != null)
                                'date range',
                            ].whereType<String>().join(', '),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: AppTheme.listPadding,
                        itemCount: _items.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          if (i == _items.length) {
                            final pages = paginationTotalPages(_pagination);
                            return EntranceItem(
                              index: 6,
                              child: ListPaginationRow(
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
                              ),
                            );
                          }
                          final row = _items[i];
                          final id = idOf(row);
                          final number =
                              row['requisition_request_number']
                                  ?.toString()
                                  .trim() ??
                              '';
                          final title = row['title']?.toString().trim() ?? '';
                          final headline = [
                            if (number.isNotEmpty) number,
                            if (title.isNotEmpty) title,
                          ].join(' · ');
                          final site = siteNameOf(row);
                          final status = row['status']?.toString();
                          return EntranceItem(
                            index: i,
                            child: PressScale(
                              enabled: id != null,
                              child: Card(
                                child: ListTile(
                                  title: Text(
                                    headline.isEmpty ? 'RR' : headline,
                                  ),
                                  subtitle: Text(
                                    site.isEmpty ? 'Requisition' : site,
                                  ),
                                  trailing: _RrRowActions(
                                    status: status,
                                    onDelete: id == null
                                        ? null
                                        : () => _deleteRequisition(id),
                                  ),
                                  onTap: id == null
                                      ? null
                                      : () =>
                                            context.push('/procurement/rr/$id'),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
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
  bool _docsBusy = false;
  String? _error;
  String? _historyError;
  Map<String, dynamic>? _doc;
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _fileHistory = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _historyError = null;
    });
    try {
      final services = context.read<AppServices>();
      final doc = await services.rr.getDetail(widget.id);
      if (!mounted) return;
      await resolveDocItemNames(doc, services.settings.items.getById);
      if (!mounted) return;
      var history = <Map<String, dynamic>>[];
      var files = <Map<String, dynamic>>[];
      String? historyError;
      try {
        final log = await services.rr.getHistory(widget.id);
        history = log.histories.reversed.toList();
        files = log.fileHistories.reversed.toList();
      } on ApiException catch (e) {
        historyError = e.message;
      }
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _history = history;
        _fileHistory = files;
        _historyError = historyError;
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

  Future<void> _shareFile({
    required Future<List<int>> Function() fetch,
    required String filename,
    required String label,
  }) async {
    setState(() => _docsBusy = true);
    try {
      final bytes = await fetch();
      if (!mounted) return;
      await shareDownloadedBytes(bytes: bytes, filename: filename, text: label);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } catch (_) {
      if (mounted)
        showPmsSnack(context, 'Could not download $label', error: true);
    } finally {
      if (mounted) setState(() => _docsBusy = false);
    }
  }

  String _fileStem() {
    final number = _doc?['requisition_request_number']?.toString().trim() ?? '';
    return number.isEmpty ? 'requisition' : 'RR-$number';
  }

  Future<void> _setStatus(String status) async {
    try {
      await context.read<AppServices>().rr.updateStatus(widget.id, {
        'status': status,
      });
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
        ? (doc!['items'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(doc?['title']?.toString() ?? 'Requisition'),
        actions: [
          if (doc != null)
            IconButton(
              tooltip: 'Edit',
              onPressed: () async {
                final updated = await context.push<bool>(
                  '/procurement/rr/${widget.id}/edit',
                );
                if (updated == true && mounted) _load();
              },
              icon: const Icon(Icons.edit_outlined),
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
                if (_docsBusy) const LinearProgressIndicator(),
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
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _docsBusy
                          ? null
                          : () => _shareFile(
                              fetch: () => context
                                  .read<AppServices>()
                                  .rr
                                  .downloadPdf(widget.id),
                              filename: '${_fileStem()}.pdf',
                              label: 'the requisition PDF',
                            ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('PDF'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _docsBusy
                          ? null
                          : () => _shareFile(
                              fetch: () => context
                                  .read<AppServices>()
                                  .rr
                                  .downloadDocumentsZip(widget.id),
                              filename: '${_fileStem()}-documents.zip',
                              label: 'the documents zip',
                            ),
                      icon: const Icon(Icons.folder_zip_outlined),
                      label: const Text('Documents'),
                    ),
                  ],
                ),
                const Divider(height: 32),
                NamedItemLines(items: items),
                for (final line in items)
                  for (final url in attachmentUrlsOf(
                    line['attachment'] ?? line['attachments'],
                  ))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.attach_file),
                      title: Text(
                        attachmentName(url),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(itemLabel(line)),
                      onTap: () => openAttachment(context, url),
                    ),
                const SizedBox(height: 16),
                if (['pending', 'revised'].contains(doc?['status']?.toString()))
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
                const SizedBox(height: 24),
                Text(
                  'Approval history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_historyError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ErrorBanner(message: _historyError!, onRetry: _load),
                  )
                else if (_history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'No approval history yet',
                      style: TextStyle(color: AppTheme.muted),
                    ),
                  )
                else
                  for (final row in _history) _HistoryTile(row: row),
                if (_fileHistory.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'File activity',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final row in _fileHistory) _HistoryTile(row: row),
                ],
              ],
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final action = row['action']?.toString().trim() ?? '';
    final by = row['actionBy'];
    var actor = '';
    if (by is Map) {
      final name = by['name']?.toString().trim() ?? '';
      final email = by['email']?.toString().trim() ?? '';
      if (name.isNotEmpty && !looksLikeObjectId(name)) {
        actor = name;
      } else if (email.isNotEmpty) {
        actor = email;
      }
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(action.isEmpty ? 'Update' : action),
      subtitle: Text(
        [
          if (actor.isNotEmpty) actor,
          formatDateTime(row['createdAt']),
        ].join(' · '),
      ),
    );
  }
}

class _DateRangeDialog extends StatefulWidget {
  const _DateRangeDialog({this.from, this.to});

  final DateTime? from;
  final DateTime? to;

  @override
  State<_DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<_DateRangeDialog> {
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _from = widget.from;
    _to = widget.to;
  }

  Future<void> _pick(bool start) async {
    final initial = (start ? _from : _to) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Date range'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('From'),
            subtitle: Text(_from == null ? 'Any date' : formatDate(_from)),
            onTap: () => _pick(true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('To'),
            subtitle: Text(_to == null ? 'Any date' : formatDate(_to)),
            onTap: () => _pick(false),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, (from: null, to: null)),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            var from = _from;
            var to = _to;
            if (from != null && to != null && from.isAfter(to)) {
              final swap = from;
              from = to;
              to = swap;
            }
            Navigator.pop(context, (from: from, to: to));
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class RrCreateScreen extends StatefulWidget {
  const RrCreateScreen({super.key, this.id});

  final String? id;

  bool get isEdit => id != null && id!.isNotEmpty;

  @override
  State<RrCreateScreen> createState() => _RrCreateScreenState();
}

class _RrCreateScreenState extends State<RrCreateScreen> {
  final _remarks = TextEditingController();
  String _prType = 'Project BOQ';
  String? _siteId;
  String _siteLabel = '';
  String? _categoryId;
  String _categoryLabel = '';
  String _localPurchase = 'no';
  String? _vendorId;
  String _vendorLabel = '';
  DateTime _date = DateTime.now();
  DateTime _expected = DateTime.now().add(const Duration(days: 7));
  int? _nextNumber;
  String _status = 'draft';
  bool _firstApproval = false;
  bool _secondApproval = false;
  bool _loadingDoc = false;
  bool _saving = false;
  String? _saveError;
  List<Map<String, dynamic>> _sites = [];
  List<Map<String, dynamic>> _vendors = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _catalogItems = [];
  List<Map<String, dynamic>> _brands = [];
  final List<_RrLine> _lines = [_RrLine()];
  final _fieldErrors = FieldErrors();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _remarks.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (widget.isEdit) setState(() => _loadingDoc = true);
    await Future.wait([
      _reloadSites(),
      _reloadCategories(),
      _reloadVendors(),
      _reloadItems(),
      _reloadBrands(),
    ]);
    if (widget.isEdit) {
      await _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    try {
      final doc = await context.read<AppServices>().rr.getById(widget.id!);
      if (!mounted) return;
      final title = doc['title']?.toString().trim() ?? '';
      String? categoryId;
      for (final row in _categories) {
        final name = row['name']?.toString().trim() ?? '';
        if (name.isNotEmpty && name.toLowerCase() == title.toLowerCase()) {
          categoryId = mongoId(row);
          break;
        }
      }
      final rawItems = doc['items'];
      final lines = rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((e) => _RrLine.fromMap(Map<String, dynamic>.from(e)))
                .toList()
          : <_RrLine>[];
      for (final line in lines) {
        line.brandOptions = _makeOptions();
        if (line.itemId == null) continue;
        try {
          final uoms = await context.read<SettingsApis>().getItemUomOptions(
            line.itemId!,
          );
          line.uomOptions = mapToOptions(
            uoms,
            labelOfRow: (r) =>
                r['uom_name']?.toString() ??
                r['unit']?.toString() ??
                labelOf(r),
          );
        } on ApiException {
          line.uomOptions = const [];
        }
      }
      if (!mounted) return;
      for (final old in _lines) {
        old.dispose();
      }
      _lines
        ..clear()
        ..addAll(lines.isEmpty ? [_RrLine()] : lines);
      final parsedDate = DateTime.tryParse(doc['date']?.toString() ?? '');
      final parsedExpected = DateTime.tryParse(
        doc['expected_delivery_date']?.toString() ?? '',
      );
      setState(() {
        _status = doc['status']?.toString() ?? 'draft';
        _prType = doc['prType']?.toString() ?? _prType;
        _categoryId = categoryId;
        _categoryLabel = title;
        _siteId = mongoId(doc['site']);
        _siteLabel = labelOf(doc['site'], fallback: siteNameOf(doc));
        if (_siteLabel == '—') _siteLabel = '';
        _localPurchase = doc['local_purchase']?.toString() == 'yes'
            ? 'yes'
            : 'no';
        _vendorId = mongoId(doc['vendor']);
        _vendorLabel = labelOf(doc['vendor'], fallback: '');
        if (_vendorLabel == '—') _vendorLabel = '';
        _nextNumber = asNum(doc['requisition_request_number'])?.toInt();
        if (parsedDate != null) _date = parsedDate;
        if (parsedExpected != null) _expected = parsedExpected;
        _remarks.text = doc['remarks']?.toString() ?? '';
        _firstApproval = doc['first_approval'] == true;
        _secondApproval = doc['second_approval'] == true;
        _loadingDoc = false;
      });
      if (categoryId != null) {
        await _reloadItems(categoryId: categoryId);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDoc = false;
        _saveError = e.message;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _safeListAll(
    MasterResourceApi api, {
    Map<String, dynamic>? params,
  }) async {
    try {
      return await api.listAll(params);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
      return const [];
    }
  }

  Future<void> _reloadSites() async {
    final rows = await _safeListAll(
      context.read<SettingsApis>().sites,
      params: const {'sortBy': 'site_name', 'sortOrder': 'asc'},
    );
    if (!mounted) return;
    setState(() => _sites = rows);
  }

  Future<void> _reloadCategories() async {
    final rows = await _safeListAll(
      context.read<SettingsApis>().categories,
      params: const {'sortBy': 'name', 'sortOrder': 'asc'},
    );
    if (!mounted) return;
    setState(() => _categories = rows);
  }

  Future<void> _reloadBrands() async {
    final rows = await _safeListAll(
      context.read<SettingsApis>().brands,
      params: const {'sortBy': 'brand_name', 'sortOrder': 'asc'},
    );
    if (!mounted) return;
    setState(() => _brands = rows);
  }

  List<OptionItem> _makeOptions() {
    return mapToOptions(
      _brands,
      labelOfRow: (r) => r['brand_name']?.toString() ?? labelOf(r),
    );
  }

  String _makeLabel(List<String> ids) {
    if (ids.isEmpty) return '';
    final opts = _makeOptions();
    final names = <String>[];
    for (final id in ids) {
      final match = opts.where((o) => o.value == id);
      names.add(match.isEmpty ? id : match.first.label);
    }
    return names.join(', ');
  }

  Future<void> _reloadVendors() async {
    final rows = await _safeListAll(
      context.read<SettingsApis>().vendors,
      params: const {'sortBy': 'vendor_name', 'sortOrder': 'asc'},
    );
    if (!mounted) return;
    setState(() => _vendors = rows);
  }

  Future<void> _reloadItems({String? categoryId}) async {
    final rows = await _safeListAll(
      context.read<SettingsApis>().items,
      params: {
        'sortBy': 'item_name',
        'sortOrder': 'asc',
        if (categoryId != null) 'category': categoryId,
      },
    );
    if (!mounted) return;
    setState(() => _catalogItems = rows);
  }

  Future<void> _pickCategory() async {
    await _reloadCategories();
    if (!mounted) return;
    final picked = await showOptionPicker(
      context,
      title: 'Request category',
      options: mapToOptions(
        _categories,
        labelOfRow: (r) => r['name']?.toString() ?? labelOf(r),
      ),
      selected: _categoryId,
      emptyMessage: 'No categories found',
    );
    if (picked == null) return;
    setState(() {
      _categoryId = picked.value;
      _categoryLabel = picked.label;
      for (final line in _lines) {
        line.clearItem();
      }
    });
    await _reloadItems(categoryId: picked.value);
  }

  Future<void> _applyItemToLine(int index, OptionItem picked) async {
    final line = _lines[index];
    line.itemId = picked.value;
    line.itemLabel = picked.label;
    var item = Map<String, dynamic>.from(picked.raw ?? {});
    try {
      item = await context.read<SettingsApis>().items.getById(picked.value);
    } on ApiException {
      // Use list row if detail fetch fails.
    }
    line.itemCode = item['item_code']?.toString() ?? '';
    line.specification = item['specification']?.toString() ?? '';
    line.categoryLabel = labelOf(item['category'], fallback: '');
    line.subCategoryLabel = labelOf(item['sub_category'], fallback: '');
    line.hsn = (item['HSNcode'] ?? item['HSNCode'])?.toString() ?? '';
    line.uomId = mongoId(item['uom']);
    line.uomLabel = labelOf(item['uom'], fallback: '');
    line.brandIds = [];
    if (_brands.isEmpty) {
      await _reloadBrands();
    }
    line.brandOptions = _makeOptions();
    try {
      final uoms = await context.read<SettingsApis>().getItemUomOptions(
        picked.value,
      );
      line.uomOptions = mapToOptions(
        uoms,
        labelOfRow: (r) =>
            r['uom_name']?.toString() ?? r['unit']?.toString() ?? labelOf(r),
      );
      if (line.uomId != null) {
        for (final opt in line.uomOptions) {
          if (opt.value == line.uomId) {
            line.uomLabel = opt.label;
            break;
          }
        }
      }
    } on ApiException {
      line.uomOptions = const [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickSite() async {
    await _reloadSites();
    if (!mounted) return;
    final picked = await showOptionPicker(
      context,
      title: 'Site',
      options: mapToOptions(
        _sites,
        labelOfRow: (r) => r['site_name']?.toString() ?? labelOf(r),
      ),
      selected: _siteId,
      emptyMessage: 'No sites found',
    );
    if (picked == null) return;
    setState(() {
      _siteId = picked.value;
      _siteLabel = picked.label;
    });
    try {
      final n = await context.read<AppServices>().rr.getNextNumber(
        picked.value,
      );
      if (!mounted) return;
      setState(() => _nextNumber = n);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _nextNumber = null);
        showPmsSnack(context, e.message, error: true);
      }
    }
  }

  Future<void> _save({bool submit = false}) async {
    _fieldErrors.clear();
    _fieldErrors.set(
      'category',
      _categoryLabel.trim().isEmpty ? 'Request category is required' : null,
    );
    _fieldErrors.set('site', requiredSelection(_siteId, 'Site'));
    if (!widget.isEdit) {
      _fieldErrors.set(
        'pr',
        _nextNumber == null
            ? 'PR number is missing — pick the site again'
            : null,
      );
    }
    if (_localPurchase == 'yes') {
      _fieldErrors.set('vendor', requiredSelection(_vendorId, 'Vendor'));
    }
    final used = <_RrLine>[];
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      if (line.itemId == null) continue;
      used.add(line);
      final rawQty = line.qty.text.trim();
      final qty = num.tryParse(rawQty);
      if (rawQty.isEmpty || qty == null || qty <= 0) {
        _fieldErrors.set('line${i}Qty', 'Qty must be greater than 0');
      }
      if (line.brandIds.isEmpty) {
        _fieldErrors.set('line${i}Make', 'Make list is required');
      }
    }
    if (used.isEmpty) {
      _fieldErrors.set('lines', 'Add at least one line item');
    }
    if (_fieldErrors.hasErrors) {
      setState(() => _saveError = null);
      showPmsSnack(context, _fieldErrors.messages.first, error: true);
      return;
    }
    setState(() => _saveError = null);
    final items = used
        .map(
          (l) => {
            'item_id': l.itemId,
            'qty': num.tryParse(l.qty.text) ?? 1,
            'rate': num.tryParse(l.rate.text) ?? 0,
            'gst': num.tryParse(l.gst.text) ?? 0,
            'freight': num.tryParse(l.freight.text) ?? 0,
            'remark': l.remark.text.trim(),
            'brandName': l.brandIds,
            if (l.uomId != null) 'uom': l.uomId,
          },
        )
        .toList();
    final files = <MapEntry<String, MultipartFileEntry>>[];
    for (var i = 0; i < used.length; i++) {
      for (final file in used[i].attachments) {
        files.add(MapEntry('item_${i}_attachment', file.toEntry()));
      }
    }
    setState(() => _saving = true);
    try {
      final services = context.read<AppServices>().rr;
      final payload = <String, dynamic>{
        'title': _categoryLabel.trim(),
        'prType': _prType,
        'date': _date.toIso8601String(),
        'expected_delivery_date': _expected.toIso8601String(),
        'local_purchase': _localPurchase,
        'remarks': _remarks.text.trim(),
        'first_approval': _firstApproval,
        'second_approval': _secondApproval,
        'items': items,
        if (_localPurchase == 'yes') 'vendor': _vendorId,
        if (_localPurchase == 'yes')
          'vendors_total': [
            {
              'vendor_id': _vendorId,
              'subtotal': 0,
              'total_tax': 0,
              'total_amount': 0,
              'preferred': true,
            },
          ],
      };
      final savingDraft = !widget.isEdit || _status == 'draft';
      if (!widget.isEdit) {
        await services.create({
          ...payload,
          'requisition_request_number': _nextNumber,
          'site': _siteId,
          'status': submit ? 'pending' : 'draft',
          'new_request': true,
        }, files: files);
      } else if (_status == 'draft') {
        await services.update(widget.id!, {
          ...payload,
          'status': submit ? 'pending' : 'draft',
        }, files: files);
      } else if (_status == 'revise') {
        await services.update(widget.id!, payload, files: files);
      } else {
        await services.superEdit(widget.id!, {
          ...payload,
          'status': _status,
        }, files: files);
      }
      if (!mounted) return;
      await showSavedConfirmation(
        context,
        savingDraft
            ? (submit ? 'Requisition submitted' : 'Draft saved')
            : 'Requisition updated',
      );
      if (mounted) context.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      final message = formatApiErrorSummary(e);
      setState(() {
        _saveError = message;
        for (final entry in apiFieldErrors(e).entries) {
          _fieldErrors.set(entry.key, entry.value);
        }
      });
      showPmsSnack(context, message, error: true);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _saveError = 'Upload failed. Check the connection and tap Retry.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = !widget.isEdit
        ? 'New requisition'
        : _status == 'revise'
        ? 'Revise requisition'
        : 'Edit requisition';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _loadingDoc
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: AppTheme.formPadding,
              children: [
                if (_saveError != null)
                  ErrorBanner(
                    message: _saveError!,
                    onRetry: _saving ? null : () => _save(),
                  ),
                if (_fieldErrors.hasErrors)
                  ValidationSummaryBanner(messages: _fieldErrors.messages),
                AppDropdownFormField<String>(
                  initialValue: _prType,
                  decoration: const InputDecoration(labelText: 'PR type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'Project BOQ',
                      child: Text('Project BOQ'),
                    ),
                    DropdownMenuItem(
                      value: 'Site Establishment',
                      child: Text('Site Establishment'),
                    ),
                    DropdownMenuItem(value: 'Assets', child: Text('Assets')),
                  ],
                  onChanged: (v) => setState(() => _prType = v ?? _prType),
                ),
                const SizedBox(height: 12),
                PickerField(
                  label: 'Request category',
                  required: true,
                  valueLabel: _categoryLabel,
                  errorText: _fieldErrors['category'],
                  onTap: _pickCategory,
                ),
                const SizedBox(height: 12),
                PickerField(
                  label: 'Site',
                  required: true,
                  enabled: !widget.isEdit,
                  valueLabel: _siteLabel,
                  errorText: _fieldErrors['site'],
                  onTap: _pickSite,
                ),
                const SizedBox(height: 12),
                _NextPrNumberCard(number: _nextNumber, siteLabel: _siteLabel),
                if (_fieldErrors['pr'] != null)
                  Text(
                    _fieldErrors['pr']!,
                    style: const TextStyle(
                      color: AppTheme.danger,
                      fontSize: 12,
                    ),
                  ),
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
                  title: Text(
                    'Expected ${formatDate(_expected.toIso8601String())}',
                  ),
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
                AppDropdownFormField<String>(
                  initialValue: _localPurchase,
                  decoration: const InputDecoration(
                    labelText: 'Local purchase',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'no', child: Text('No')),
                    DropdownMenuItem(value: 'yes', child: Text('Yes')),
                  ],
                  onChanged: (v) => setState(() => _localPurchase = v ?? 'no'),
                ),
                if (_localPurchase == 'yes') ...[
                  const SizedBox(height: 12),
                  PickerField(
                    label: 'Vendor',
                    required: true,
                    valueLabel: _vendorLabel,
                    errorText: _fieldErrors['vendor'],
                    onTap: () async {
                      await _reloadVendors();
                      if (!mounted) return;
                      final picked = await showOptionPicker(
                        context,
                        title: 'Vendor',
                        options: mapToOptions(
                          _vendors,
                          labelOfRow: (r) =>
                              r['vendor_name']?.toString() ?? labelOf(r),
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
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _remarks,
                  decoration: const InputDecoration(labelText: 'Remarks'),
                  maxLines: 2,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('First approval'),
                  value: _firstApproval,
                  onChanged: (value) => setState(() => _firstApproval = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Second approval'),
                  value: _secondApproval,
                  onChanged: (value) => setState(() => _secondApproval = value),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Items',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() => _lines.add(_RrLine())),
                      child: const Text('Add line'),
                    ),
                  ],
                ),
                if (_fieldErrors['lines'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _fieldErrors['lines']!,
                      style: const TextStyle(
                        color: AppTheme.danger,
                        fontSize: 12,
                      ),
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
                              Text(
                                'Line ${i + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Delete line',
                                onPressed: () {
                                  final removed = _lines.removeAt(i);
                                  setState(() {});
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    removed.dispose();
                                  });
                                },
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppTheme.danger,
                                ),
                              ),
                            ],
                          ),
                          PickerField(
                            label: 'Item',
                            valueLabel: _lines[i].itemLabel,
                            enabled: _categoryId != null,
                            onTap: () async {
                              if (_categoryId == null) {
                                showPmsSnack(
                                  context,
                                  'Select request category first',
                                  error: true,
                                );
                                return;
                              }
                              await _reloadItems(categoryId: _categoryId);
                              if (!mounted) return;
                              final picked = await showOptionPicker(
                                context,
                                title: 'Item',
                                options: mapToOptions(
                                  _catalogItems,
                                  labelOfRow: (r) =>
                                      r['item_name']?.toString() ?? labelOf(r),
                                ),
                                selected: _lines[i].itemId,
                                emptyMessage: 'Select material category first',
                              );
                              if (picked == null) return;
                              await _applyItemToLine(i, picked);
                            },
                          ),
                          if (_lines[i].itemId != null) ...[
                            const SizedBox(height: 8),
                            _ReadOnlyField(
                              label: 'Item code',
                              value: _lines[i].itemCode,
                            ),
                            _ReadOnlyField(
                              label: 'Specification',
                              value: _lines[i].specification,
                            ),
                            _ReadOnlyField(
                              label: 'Category',
                              value: _lines[i].categoryLabel,
                            ),
                            _ReadOnlyField(
                              label: 'Sub category',
                              value: _lines[i].subCategoryLabel,
                            ),
                            _ReadOnlyField(
                              label: 'HSN code',
                              value: _lines[i].hsn,
                            ),
                            PickerField(
                              label: 'UOM',
                              valueLabel: _lines[i].uomLabel,
                              onTap: () async {
                                final opts = _lines[i].uomOptions;
                                if (opts.isEmpty) {
                                  showPmsSnack(
                                    context,
                                    'No UOM options for this item',
                                    error: true,
                                  );
                                  return;
                                }
                                final picked = await showOptionPicker(
                                  context,
                                  title: 'UOM',
                                  options: opts,
                                  selected: _lines[i].uomId,
                                );
                                if (picked == null) return;
                                setState(() {
                                  _lines[i].uomId = picked.value;
                                  _lines[i].uomLabel = picked.label;
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            PickerField(
                              label: 'Make list',
                              required: true,
                              valueLabel: _makeLabel(_lines[i].brandIds),
                              errorText: _fieldErrors['line${i}Make'],
                              onTap: () async {
                                await _reloadBrands();
                                if (!mounted) return;
                                final picked = await showMultiOptionPicker(
                                  context,
                                  title: 'Make list',
                                  options: _makeOptions(),
                                  selected: _lines[i].brandIds,
                                  emptyMessage: 'No makes found',
                                );
                                if (picked == null) return;
                                setState(() => _lines[i].brandIds = picked);
                              },
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _lines[i].qty,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Qty *',
                                    errorText: _fieldErrors['line${i}Qty'],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _lines[i].rate,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Rate',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _lines[i].gst,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'GST',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _lines[i].freight,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Freight',
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _lines[i].remark,
                            decoration: const InputDecoration(
                              labelText: 'Remark',
                            ),
                          ),
                          const SizedBox(height: 8),
                          _LineUploadField(
                            files: _lines[i].attachments,
                            onChanged: (files) =>
                                setState(() => _lines[i].attachments = files),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (!widget.isEdit || _status == 'draft') ...[
                  FilledButton(
                    onPressed: _saving ? null : () => _save(submit: true),
                    child: Text(_saving ? 'Saving…' : 'Submit requisition'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _saving ? null : () => _save(),
                    child: const Text('Save draft'),
                  ),
                ] else
                  FilledButton(
                    onPressed: _saving ? null : () => _save(),
                    child: Text(
                      _saving
                          ? 'Saving…'
                          : widget.isEdit
                          ? (_status == 'revise'
                                ? 'Save revision'
                                : 'Save changes')
                          : 'Create requisition',
                    ),
                  ),
              ],
            ),
    );
  }
}

class _NextPrNumberCard extends StatelessWidget {
  const _NextPrNumberCard({required this.number, required this.siteLabel});

  final int? number;
  final String siteLabel;

  @override
  Widget build(BuildContext context) {
    final hasNumber = number != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.brandLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.brand.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.tag_rounded, color: AppTheme.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Next PR number',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasNumber ? 'PR $number' : 'Select a site to generate',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: hasNumber ? AppTheme.primary : AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hasNumber
                      ? 'Next requisition request number: $number'
                      : 'Next requisition request number: —',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.muted,
                  ),
                ),
                if (siteLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    siteLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _requisitionItemName(Map<String, dynamic> line) {
  final item = line['item_id'];
  if (item is Map) {
    final name =
        item['item_name']?.toString().trim() ??
        item['name']?.toString().trim() ??
        '';
    if (name.isNotEmpty) return name;
  }
  final direct = line['item_name']?.toString().trim() ?? '';
  return direct;
}

class _RrLine {
  String? itemId;
  String itemLabel = '';
  String itemCode = '';
  String specification = '';
  String categoryLabel = '';
  String subCategoryLabel = '';
  String hsn = '';
  String? uomId;
  String uomLabel = '';
  List<String> brandIds = [];
  List<OptionItem> uomOptions = const [];
  List<OptionItem> brandOptions = const [];
  List<PendingFile> attachments = [];
  final qty = TextEditingController(text: '1');
  final rate = TextEditingController(text: '0');
  final gst = TextEditingController(text: '0');
  final freight = TextEditingController(text: '0');
  final remark = TextEditingController();

  _RrLine();

  factory _RrLine.fromMap(Map<String, dynamic> line) {
    final row = _RrLine();
    final item = line['item_id'];
    row.itemId = mongoId(item);
    row.itemLabel = _requisitionItemName(line);
    if (row.itemLabel == '—') row.itemLabel = '';
    if (item is Map) {
      row.itemCode = item['item_code']?.toString() ?? '';
      row.specification = item['specification']?.toString() ?? '';
      row.categoryLabel = labelOf(item['category'], fallback: '');
      row.subCategoryLabel = labelOf(item['sub_category'], fallback: '');
      row.hsn = (item['HSNcode'] ?? item['HSNCode'])?.toString() ?? '';
      if (row.categoryLabel == '—') row.categoryLabel = '';
      if (row.subCategoryLabel == '—') row.subCategoryLabel = '';
    }
    row.uomId = mongoId(line['uom']);
    row.uomLabel = labelOf(line['uom'], fallback: '');
    if (row.uomLabel == '—') row.uomLabel = '';
    final brands = line['brandName'];
    if (brands is List) {
      row.brandIds = brands.map(mongoId).whereType<String>().toList();
    }
    row.qty.text = '${line['qty'] ?? 1}';
    row.rate.text = '${line['rate'] ?? 0}';
    row.gst.text = '${line['gst'] ?? 0}';
    row.freight.text = '${line['freight'] ?? 0}';
    row.remark.text = line['remark']?.toString() ?? '';
    return row;
  }

  void dispose() {
    qty.dispose();
    rate.dispose();
    gst.dispose();
    freight.dispose();
    remark.dispose();
  }

  void clearItem() {
    itemId = null;
    itemLabel = '';
    itemCode = '';
    specification = '';
    categoryLabel = '';
    subCategoryLabel = '';
    hsn = '';
    uomId = null;
    uomLabel = '';
    brandIds = [];
    uomOptions = const [];
    brandOptions = const [];
    attachments = [];
  }
}

class _LineUploadField extends StatelessWidget {
  const _LineUploadField({required this.files, required this.onChanged});

  final List<PendingFile> files;
  final ValueChanged<List<PendingFile>> onChanged;

  Future<void> _pick(BuildContext context) async {
    final picked = await showAttachmentPicker(context);
    if (picked.isEmpty) return;
    onChanged([...files, ...picked]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () => _pick(context),
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(files.isEmpty ? 'Upload' : 'Add files (${files.length})'),
        ),
        for (var i = 0; i < files.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(
              files[i].filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                final next = [...files]..removeAt(i);
                onChanged(next);
              },
            ),
          ),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
        child: Text(
          value.isEmpty ? '—' : value,
          style: const TextStyle(color: AppTheme.primary),
        ),
      ),
    );
  }
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
  String _search = '';
  List<Map<String, dynamic>> _items = [];

  bool _hit(dynamic value, String query) {
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text.isNotEmpty && !looksLikeObjectId(text) && text.contains(query);
  }

  bool _matches(Map<String, dynamic> row) {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return true;
    final site = row['site'];
    return _hit(row['requisition_request_number'], query) ||
        _hit(row['title'], query) ||
        _hit(labelOf(site, fallback: ''), query) ||
        (site is Map &&
            (_hit(site['site_name'], query) ||
                _hit(site['code'], query) ||
                _hit(site['location'], query)));
  }

  Future<void> _deleteRequisition(String id) async {
    final ok = await confirmAction(
      context,
      title: 'Delete requisition',
      message: 'Delete this requisition? This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<AppServices>().rr.delete(id);
      if (!mounted) return;
      showPmsSnack(context, 'Requisition deleted');
      _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

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
      final res = _step == 1
          ? await api.pendingFirst({'limit': 100})
          : await api.pendingSecond({'limit': 100});
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
    final visible = _items.where(_matches).toList();
    return Scaffold(
      extendBody: true,
      appBar: const ModernAppBar(
        title: 'RR Approvals',
        actions: [PressScale(child: WorkspaceSwitcherButton())],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StaggeredEntrance(
            active: !_loading,
            maxIndex: 1,
            slide: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EntranceItem(
                  index: 0,
                  child: Padding(
                    padding: AppTheme.filterPadding,
                    child: PressScale(
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
                  ),
                ),
                EntranceItem(
                  index: 1,
                  child: Padding(
                    padding: AppTheme.searchPadding,
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search number, title or site…',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => setState(() => _search = v.trim()),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SoftAppear(
                child: ErrorBanner(message: _error!, onRetry: _load),
              ),
            ),
          Expanded(
            child: StaggeredEntrance(
              active: !_loading,
              replayToken: _step,
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading
                    ? const CenteredScrollLoader()
                    : visible.isEmpty
                    ? EntranceItem(
                        index: 0,
                        child: EmptyListBody(
                          message: listEmptyMessage(
                            noun: 'pending approvals',
                            search: _search,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: AppTheme.formPadding,
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final row = visible[i];
                          final id = idOf(row);
                          final status = row['status']?.toString();
                          return EntranceItem(
                            index: i,
                            child: PressScale(
                              child: Card(
                                child: ListTile(
                                  title: Text(row['title']?.toString() ?? 'RR'),
                                  subtitle: Text(
                                    '${row['requisition_request_number'] ?? ''}',
                                  ),
                                  trailing: _RrRowActions(
                                    status: status,
                                    onDelete:
                                        id == null ||
                                            !(status == 'draft' ||
                                                status == 'revise' ||
                                                status == 'rejected')
                                        ? null
                                        : () => _deleteRequisition(id),
                                  ),
                                  onTap: id == null
                                      ? null
                                      : () => context.push('/procurement/rr/$id'),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
