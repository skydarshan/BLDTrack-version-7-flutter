import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/widgets/sort_menu.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/modern_widgets.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/utils/list_query.dart';
import '../../../core/utils/share_bytes.dart';
import '../../app/app_services.dart';
import '../../app/app_shell.dart';
import '../../pms/utils/site_options.dart';
import '../../pms/widgets/pickers.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../../settings/services/settings_apis.dart';
import 'procurement_screens.dart';

class RcListScreen extends StatefulWidget {
  const RcListScreen({super.key});

  @override
  State<RcListScreen> createState() => _RcListScreenState();
}

class _RcTab {
  const _RcTab(this.label, this.status, this.stage);

  final String label;
  final String status;
  final String stage;
}

final _compactButton = OutlinedButton.styleFrom(
  minimumSize: const Size(0, 34),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.compact,
  padding: const EdgeInsets.symmetric(horizontal: 12),
);

final _compactFilled = FilledButton.styleFrom(
  minimumSize: const Size(0, 34),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.compact,
  padding: const EdgeInsets.symmetric(horizontal: 12),
  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
);

const _rcTabs = [
  _RcTab('Pending Rate Comparatives', 'pending', 'rate_comparative'),
  _RcTab('Draft Rate Comparatives', 'draft', 'rate_comparative'),
  _RcTab('Revise Rate Comparatives', 'revise', 'rate_comparative'),
  _RcTab('Pending Rate Approvals', 'pending', 'rate_approval'),
];

class _RcListScreenState extends State<RcListScreen> {
  bool _loading = true;
  bool _merging = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _pagination;
  int _page = 1;
  String _sortBy = 'requestedOn';
  String _sortOrder = 'desc';
  int _tab = 0;
  String _search = '';
  String? _siteId;
  String _siteLabel = '';
  List<Map<String, dynamic>> _sites = [];
  final List<String> _selected = [];
  int _pendingCount = 0;
  int _draftCount = 0;
  int _reviseCount = 0;
  int _approvalCount = 0;

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

  int _countOf(dynamic bucket, String key) {
    if (bucket is! Map) return 0;
    final value = bucket[key];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rc = context.read<AppServices>().rc;
      final tab = _rcTabs[_tab];
      final res = await rc.list({
        'page': _page,
        'limit': 20,
        'sortBy': _sortBy,
        'sortOrder': _sortOrder,
        'status': tab.status,
        'stage': tab.stage,
        if (_search.isNotEmpty) 'comparative_no': _search,
        if (_siteId != null) 'site': _siteId,
      });
      try {
        final counts = await rc.inboxCounts({
          if (_search.isNotEmpty) 'comparative_no': _search,
          if (_siteId != null) 'site': _siteId,
        });
        _pendingCount = _countOf(counts['rate_comparative'], 'pending');
        _draftCount = _countOf(counts['rate_comparative'], 'draft');
        _reviseCount = _countOf(counts['rate_comparative'], 'revise');
        _approvalCount = _countOf(counts['rate_approval'], 'pending');
      } catch (_) {}
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

  int _tabCount(int index) {
    switch (index) {
      case 0:
        return _pendingCount;
      case 1:
        return _draftCount;
      case 2:
        return _reviseCount;
      default:
        return _approvalCount;
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    final id = idOf(row);
    if (id == null || id.isEmpty) return;
    await context.push('/procurement/rc/$id');
    if (mounted) _load();
  }

  Future<void> _confirmMerge() async {
    if (_tab > 1) {
      showPmsSnack(context, 'Merge pending or draft comparatives', error: true);
      return;
    }
    if (!_merging) {
      setState(() {
        _merging = true;
        _selected.clear();
      });
      return;
    }
    if (_selected.length < 2) {
      showPmsSnack(context, 'Select at least two comparatives', error: true);
      return;
    }
    try {
      await context.read<AppServices>().rc.merge({'rate_comparative_ids': List<String>.from(_selected)});
      if (!mounted) return;
      setState(() {
        _merging = false;
        _selected.clear();
        _page = 1;
      });
      showPmsSnack(context, 'Comparatives merged');
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showPmsSnack(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      showPmsSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _split() async {
    if (_tab > 1) {
      showPmsSnack(context, 'Only pending or draft comparatives can be split', error: true);
      return;
    }
    if (_items.isEmpty) return;
    final picked = await showOptionPicker(
      context,
      title: 'Split Comparative',
      options: [
        for (final row in _items)
          OptionItem(value: idOf(row) ?? '', label: rcHeadline(row)),
      ].where((option) => option.value.isNotEmpty).toList(),
    );
    if (picked == null || !mounted) return;
    try {
      final doc = await context.read<AppServices>().rc.getById(picked.value);
      if (!mounted) return;
      final lines = lineItemsOf(doc);
      final choices = [
        for (final line in lines)
          (
            name: labelOf(line['item_id']),
            qty: (asNum(line['qty']) ?? 1).round(),
          ),
      ];
      if (choices.isEmpty || !mounted) return;
      final qtyToNew = await showDialog<List<int>>(
        context: context,
        builder: (context) => _SplitQtyDialog(lines: choices),
      );
      if (qtyToNew == null || !mounted) return;
      await context.read<AppServices>().rc.split(picked.value, {'qtyToNew': qtyToNew});
      if (!mounted) return;
      showPmsSnack(context, 'Comparative split');
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showPmsSnack(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      showPmsSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _delete(String id, String label) async {
    final ok = await confirmAction(
      context,
      title: 'Delete comparative',
      message: 'Delete $label? This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<AppServices>().rc.delete(id);
      if (!mounted) return;
      showPmsSnack(context, 'Comparative deleted');
      _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showPmsSnack(context, e.toString(), error: true);
    }
  }

  String _actionLabel() {
    switch (_tab) {
      case 0:
        return 'Create Comparative';
      case 1:
        return 'Continue draft';
      case 2:
        return 'Revise';
      default:
        return 'Open';
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = paginationTotalPages(_pagination);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate Comparative'),
        actions: [
          SortMenuButton(
            choices: const [
              SortChoice(by: 'requestedOn', order: 'desc', label: 'Newest'),
              SortChoice(by: 'requestedOn', order: 'asc', label: 'Oldest'),
              SortChoice(by: 'comparative_no', order: 'asc', label: 'Comparative no.'),
              SortChoice(by: 'title', order: 'asc', label: 'Title A–Z'),
            ],
            sortBy: _sortBy,
            sortOrder: _sortOrder,
            onSelected: (by, order) {
              setState(() {
                _sortBy = by;
                _sortOrder = order;
                _page = 1;
              });
              _load();
            },
          ),
          const WorkspaceSwitcherButton(),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Create, split, or merge, then send lines to rate approval.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                OutlinedButton(
                  style: _compactButton,
                  onPressed: _split,
                  child: const Text('Split'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: _compactButton,
                  onPressed: _confirmMerge,
                  child: Text(_merging ? 'Merge (${_selected.length})' : 'Merge'),
                ),
                if (_merging) ...[
                  const SizedBox(width: 4),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => setState(() {
                      _merging = false;
                      _selected.clear();
                    }),
                    child: const Text('Cancel'),
                  ),
                ],
                const Spacer(),
                OutlinedButton.icon(
                  style: _compactButton,
                  onPressed: _pickSite,
                  icon: const Icon(Icons.filter_list, size: 16),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      _siteId == null ? 'Filter' : _siteLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: AppTheme.chipRowPadding,
            child: Row(
              children: [
                for (var i = 0; i < _rcTabs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${_rcTabs[i].label} (${_tabCount(i)})'),
                      selected: _tab == i,
                      onSelected: (_) {
                        setState(() {
                          _tab = i;
                          _page = 1;
                          _merging = false;
                          _selected.clear();
                        });
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: AppTheme.searchPadding,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search comparative no…',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (value) {
                setState(() {
                  _search = value.trim();
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
                              message: listEmptyMessage(
                                noun: 'rate comparatives',
                                search: _search,
                                filterLabel: [
                                  _rcTabs[_tab].label,
                                  if (_siteId != null) 'selected site',
                                ].join(', '),
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
                                final id = idOf(row) ?? '';
                                final rr = row['requisition_request_id'];
                                final rrMap = rr is Map ? Map<String, dynamic>.from(rr) : null;
                                final rrNo = rrMap?['requisition_request_number']?.toString() ?? '';
                                final title = rrMap?['title']?.toString().trim() ?? '';
                                final site = siteNameOf(row);
                                return Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            if (_merging)
                                              Checkbox(
                                                value: _selected.contains(id),
                                                onChanged: id.isEmpty
                                                    ? null
                                                    : (checked) {
                                                        setState(() {
                                                          if (checked == true) {
                                                            _selected.add(id);
                                                          } else {
                                                            _selected.remove(id);
                                                          }
                                                        });
                                                      },
                                              ),
                                            Expanded(
                                              child: Text(
                                                rrNo.isEmpty ? 'RR' : 'RR $rrNo',
                                                style: const TextStyle(fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                            StatusChip(status: row['status']?.toString()),
                                            ListDeleteMenu(
                                              onDelete: id.isEmpty
                                                  ? null
                                                  : () => _delete(
                                                        id,
                                                        row['comparative_no']?.toString().trim().isNotEmpty == true
                                                            ? row['comparative_no'].toString()
                                                            : 'RR $rrNo',
                                                      ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          [
                                            if ((row['comparative_no']?.toString().trim() ?? '').isNotEmpty)
                                              row['comparative_no'].toString(),
                                            formatDate(row['createdAt']),
                                          ].join(' · '),
                                          style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                                        ),
                                        if (title.isNotEmpty || site.isNotEmpty)
                                          Text(
                                            [if (title.isNotEmpty) title, if (site.isNotEmpty) site].join(' · '),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        const SizedBox(height: 6),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: FilledButton(
                                            style: _compactFilled,
                                            onPressed: () => _open(row),
                                            child: Text(_actionLabel()),
                                          ),
                                        ),
                                      ],
                                    ),
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

class _SplitQtyDialog extends StatefulWidget {
  const _SplitQtyDialog({required this.lines});

  final List<({String name, int qty})> lines;

  @override
  State<_SplitQtyDialog> createState() => _SplitQtyDialogState();
}

class _SplitQtyDialogState extends State<_SplitQtyDialog> {
  late final List<TextEditingController> _controllers = [
    for (final _ in widget.lines) TextEditingController(text: '0'),
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Split Comparative'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text('Enter how much of each line moves to the new comparative. 0 keeps the line here.'),
            const SizedBox(height: 12),
            for (var i = 0; i < widget.lines.length; i++) ...[
              Text('${widget.lines[i].name} · qty ${widget.lines[i].qty}'),
              TextField(
                controller: _controllers[i],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Qty to new'),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final qty = <int>[];
            for (var i = 0; i < widget.lines.length; i++) {
              final value = int.tryParse(_controllers[i].text.trim()) ?? 0;
              final max = widget.lines[i].qty;
              if (value < 0 || value > max) {
                showPmsSnack(context, 'Qty for ${widget.lines[i].name} must be 0 to $max', error: true);
                return;
              }
              qty.add(value);
            }
            if (!qty.any((value) => value > 0)) {
              showPmsSnack(context, 'Enter a quantity to move', error: true);
              return;
            }
            Navigator.pop(context, qty);
          },
          child: const Text('Split'),
        ),
      ],
    );
  }
}

class RcDetailScreen extends StatefulWidget {
  const RcDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<RcDetailScreen> createState() => _RcDetailScreenState();
}

class _RcDetailScreenState extends State<RcDetailScreen> {
  bool _loading = true;
  bool _docsBusy = false;
  String? _error;
  Map<String, dynamic>? _doc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final services = context.read<AppServices>();
      final doc = await services.rc.getById(widget.id);
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

  Future<void> _status(String status) async {
    final doc = _doc;
    if (doc == null) return;
    final payload = rcStatusPayload(doc, status);
    final items = payload['items'];
    final vendors = payload['vendors_total'];
    if (items is! List || items.isEmpty) {
      showPmsSnack(context, 'Cannot update status — line items are missing', error: true);
      return;
    }
    if (vendors is! List || vendors.isEmpty) {
      showPmsSnack(context, 'Cannot update status — vendor totals are missing', error: true);
      return;
    }
    if (status == 'approved') {
      final missingQuote = asMapList(vendors).any((v) {
        final quote = v['vendor_quotation']?.toString() ?? '';
        return !(quote.startsWith('https://') ||
            quote.startsWith('http://') ||
            quote.startsWith('s3://'));
      });
      if (missingQuote) {
        showPmsSnack(
          context,
          'Cannot approve — each vendor needs a quotation file URL. Upload quotations on web, then approve.',
          error: true,
        );
        return;
      }
    }
    try {
      await context.read<AppServices>().rc.updateStatus(widget.id, payload);
      if (!mounted) return;
      showPmsSnack(context, 'Updated');
      _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _analyze() async {
    try {
      await context.read<AppServices>().rc.analyze(widget.id);
      showPmsSnack(context, 'AI analysis started / cached');
      _load();
    } on ApiException catch (e) {
      showPmsSnack(context, e.message, error: true);
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
      if (mounted) showPmsSnack(context, 'Could not download $label', error: true);
    } finally {
      if (mounted) setState(() => _docsBusy = false);
    }
  }

  String _fileStem() {
    final number = _doc?['comparative_no']?.toString().trim() ?? '';
    return number.isEmpty ? 'rate-comparative' : number;
  }

  Future<void> _openScorecard() async {
    final doc = _doc;
    if (doc == null) return;
    final vendors = _vendorsOf(doc);
    if (vendors.isEmpty) {
      showPmsSnack(context, 'No vendors on this comparative', error: true);
      return;
    }
    var vendor = vendors.first;
    if (vendors.length > 1) {
      final picked = await showOptionPicker(
        context,
        title: 'Vendor scorecard',
        options: [
          for (final entry in vendors) OptionItem(value: entry.id, label: entry.name),
        ],
      );
      if (picked == null || !mounted) return;
      vendor = vendors.firstWhere((entry) => entry.id == picked.value, orElse: () => vendors.first);
    }
    setState(() => _docsBusy = true);
    try {
      final card = await context.read<AppServices>().rc.vendorScorecard(vendor.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _VendorScorecardSheet(card: card),
      );
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _docsBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      appBar: AppBar(title: Text(doc == null ? 'Rate comparative' : rcHeadline(doc))),
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
                    StatusChip(status: doc?['status']?.toString()),
                    const SizedBox(height: 8),
                    Text(rcHeadline(doc ?? {})),
                    Text(rcSubtitle(doc ?? {})),
                    Text('Category: ${labelOf(doc?['purchase_category'] ?? doc?['category'])}'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _docsBusy
                              ? null
                              : () => _shareFile(
                                    fetch: () => context.read<AppServices>().rc.downloadPdf(widget.id),
                                    filename: '${_fileStem()}.pdf',
                                    label: 'the rate comparative PDF',
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
                                        .rc
                                        .downloadVendorQuotationsZip(widget.id),
                                    filename: '${_fileStem()}-quotations.zip',
                                    label: 'the vendor quotations',
                                  ),
                          icon: const Icon(Icons.folder_zip_outlined),
                          label: const Text('Quotations'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _docsBusy ? null : _openScorecard,
                          icon: const Icon(Icons.insights_outlined),
                          label: const Text('Scorecard'),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    NamedItemLines(items: lineItemsOf(doc)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(onPressed: () => _status('approved'), child: const Text('Approve')),
                        OutlinedButton(onPressed: () => _status('revise'), child: const Text('Revise')),
                        OutlinedButton(onPressed: () => _status('rejected'), child: const Text('Reject')),
                        OutlinedButton(onPressed: _analyze, child: const Text('AI analyze')),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class _VendorRef {
  const _VendorRef({required this.id, required this.name});

  final String id;
  final String name;
}

List<_VendorRef> _vendorsOf(Map<String, dynamic> doc) {
  final out = <_VendorRef>[];
  final seen = <String>{};
  void add(dynamic entry) {
    if (entry is! Map) return;
    final map = Map<String, dynamic>.from(entry);
    final id = mongoId(map['vendor_id'] ?? map['vendor']);
    if (id == null || seen.contains(id)) return;
    seen.add(id);
    final name = labelOf(map['vendor_id'] ?? map['vendor'] ?? map, fallback: 'Vendor');
    out.add(_VendorRef(id: id, name: name));
  }

  final totals = doc['vendors_total'];
  if (totals is List) {
    for (final vendor in totals) {
      add(vendor);
    }
  }
  for (final line in lineItemsOf(doc)) {
    final vendors = line['vendors'];
    if (vendors is List) {
      for (final vendor in vendors) {
        add(vendor);
      }
    }
  }
  return out;
}

String _plainScore(dynamic value) {
  if (value == null) return '—';
  if (value is num) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }
  final text = value.toString().trim();
  return text.isEmpty ? '—' : text;
}

class _VendorScorecardSheet extends StatelessWidget {
  const _VendorScorecardSheet({required this.card});

  final Map<String, dynamic> card;

  @override
  Widget build(BuildContext context) {
    final performance = card['performance'] is Map
        ? Map<String, dynamic>.from(card['performance'] as Map)
        : const <String, dynamic>{};
    final scores = card['scores'] is Map
        ? Map<String, dynamic>.from(card['scores'] as Map)
        : const <String, dynamic>{};
    final contact = card['contact'] is Map
        ? Map<String, dynamic>.from(card['contact'] as Map)
        : const <String, dynamic>{};
    final risks = card['risk_summary'] is List
        ? (card['risk_summary'] as List)
            .map((entry) => entry.toString().trim())
            .where((entry) => entry.isNotEmpty)
            .toList()
        : const <String>[];
    final name = card['vendor_name']?.toString().trim().isNotEmpty == true
        ? card['vendor_name'].toString()
        : 'Vendor';
    final code = card['vendor_code']?.toString().trim() ?? '';
    final type = card['vendor_type']?.toString().trim() ?? '';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.muted,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text(name, style: Theme.of(context).textTheme.titleLarge),
            Text(
              [
                if (code.isNotEmpty) code,
                if (type.isNotEmpty) type,
                if (card['is_msme'] == true) 'MSME',
              ].join(' · '),
              style: const TextStyle(color: AppTheme.muted),
            ),
            if ((card['payment_terms']?.toString().trim() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Payment terms: ${card['payment_terms']}'),
              ),
            if ((contact['contact_person']?.toString().trim() ?? '').isNotEmpty ||
                (contact['email']?.toString().trim() ?? '').isNotEmpty)
              Text(
                [
                  contact['contact_person']?.toString().trim() ?? '',
                  contact['email']?.toString().trim() ?? '',
                ].where((part) => part.isNotEmpty).join(' · '),
              ),
            const SizedBox(height: 16),
            Text('Performance', style: Theme.of(context).textTheme.titleMedium),
            Text('Window: ${performance['data_window'] ?? '12 months'}'),
            Text('Orders: ${_plainScore(performance['total_orders'])}'),
            Text('Completed: ${_plainScore(performance['completed_orders'])}'),
            Text('On time: ${_plainScore(performance['on_time_rate_pct'])}%'),
            Text('Rejection: ${_plainScore(performance['rejection_rate_pct'])}%'),
            Text('Fulfilment: ${_plainScore(performance['fulfilment_rate_pct'])}%'),
            const SizedBox(height: 16),
            Text('Scores', style: Theme.of(context).textTheme.titleMedium),
            Text('Delivery: ${_plainScore(scores['delivery'])}'),
            Text('Quality: ${_plainScore(scores['quality'])}'),
            Text('Payment terms: ${_plainScore(scores['payment_terms'])}'),
            Text('MSME bonus: ${_plainScore(scores['msme_bonus'])}'),
            if (risks.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Risks', style: Theme.of(context).textTheme.titleMedium),
              for (final risk in risks)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('• $risk'),
                ),
            ],
          ],
        );
      },
    );
  }
}

class RateApprovalsScreen extends StatefulWidget {
  const RateApprovalsScreen({super.key});

  @override
  State<RateApprovalsScreen> createState() => _RateApprovalsScreenState();
}

class _RateApprovalsScreenState extends State<RateApprovalsScreen> {
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
    return _hit(row['comparative_no'], query) ||
        _hit(row['remarks'], query) ||
        _hit(labelOf(site, fallback: ''), query) ||
        (site is Map && (_hit(site['site_name'], query) || _hit(site['code'], query) || _hit(site['location'], query)));
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
      final api = context.read<AppServices>().rc;
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

  Future<void> _deleteRate(Map<String, dynamic> row) async {
    final id = idOf(row);
    if (id == null) return;
    final ok = await confirmAction(
      context,
      title: 'Delete comparative',
      message: 'Delete ${rcHeadline(row)}? This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<AppServices>().rc.delete(id);
      if (!mounted) return;
      showPmsSnack(context, 'Comparative deleted');
      _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _items.where(_matches).toList();
    return Scaffold(
      extendBody: true,
      appBar: const ModernAppBar(title: 'Rate approvals'),
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
                        hintText: 'Search number, remarks or site…',
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
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                  ? EntranceItem(
                      index: 0,
                      child: EmptyState(
                        message: _search.trim().isEmpty
                            ? 'No pending rate approvals'
                            : 'No rate approvals match this search',
                      ),
                    )
                  : ListView.separated(
                      padding: AppTheme.formPadding,
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final row = visible[i];
                        return EntranceItem(
                          index: i,
                          child: PressScale(
                            child: Card(
                              child: ListTile(
                                title: Text(rcHeadline(row)),
                                subtitle: Text(rcSubtitle(row)),
                                trailing: ListDeleteMenu(
                                  onDelete: () => _deleteRate(row),
                                ),
                                onTap: () => context.push(
                                  '/procurement/rc/${idOf(row)}',
                                ),
                              ),
                            ),
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

class PoListScreen extends StatefulWidget {
  const PoListScreen({super.key});

  @override
  State<PoListScreen> createState() => _PoListScreenState();
}

class _PoListScreenState extends State<PoListScreen> {
  bool _loading = true;
  bool _merging = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _pagination;
  String _status = '';
  String _search = '';
  String? _siteId;
  String _siteLabel = '';
  List<Map<String, dynamic>> _sites = [];
  int _page = 1;
  String _sortBy = 'createdOn';
  String _sortOrder = 'desc';
  int _motion = 0;
  final List<String> _selected = [];

  bool _canMergeStatus(String? status) =>
      status == 'pending' || status == 'approved' || status == 'revised';

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await context.read<AppServices>().po.list({
        'page': _page,
        'limit': 20,
        'sortBy': _sortBy,
        'sortOrder': _sortOrder,
        if (_status.isNotEmpty) 'status': _status,
        if (_search.isNotEmpty) 'search': _search,
        if (_siteId != null) 'site': _siteId,
      });
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _pagination = res.pagination;
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

  String _poNumber(Map<String, dynamic> row) {
    for (final key in ['po_number', 'ro_number', 'purchase_order_number']) {
      final text = row[key]?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return 'PO';
  }

  Future<void> _confirmMerge() async {
    if (!_merging) {
      setState(() {
        _merging = true;
        _selected.clear();
      });
      return;
    }
    if (_selected.length < 2) {
      showPmsSnack(context, 'Select at least two purchase orders', error: true);
      return;
    }
    try {
      await context.read<AppServices>().po.merge({'po_ids': List<String>.from(_selected)});
      if (!mounted) return;
      setState(() {
        _merging = false;
        _selected.clear();
        _page = 1;
      });
      showPmsSnack(context, 'Purchase orders merged');
      _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showPmsSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = paginationTotalPages(_pagination);
    return Scaffold(
      extendBody: true,
      appBar: ModernAppBar(
        title: 'Purchase orders',
        animateTitle: true,
        actions: [
          PressScale(
            child: SortMenuButton(
              choices: const [
                SortChoice(by: 'createdOn', order: 'desc', label: 'Newest'),
                SortChoice(by: 'createdOn', order: 'asc', label: 'Oldest'),
                SortChoice(by: 'po_number', order: 'asc', label: 'PO number'),
                SortChoice(by: 'vendor', order: 'asc', label: 'Vendor'),
              ],
              sortBy: _sortBy,
              sortOrder: _sortOrder,
              onSelected: (by, order) {
                setState(() {
                  _sortBy = by;
                  _sortOrder = order;
                  _page = 1;
                });
                _load();
              },
            ),
          ),
          const PressScale(child: WorkspaceSwitcherButton()),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StaggeredEntrance(
            maxIndex: 2,
            slide: 18,
            itemMs: 380,
            stepMs: 46,
            scaleFrom: 0.98,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EntranceItem(
                  index: 0,
                  child: Padding(
                    padding: AppTheme.searchPadding,
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search PO, site, vendor, item…',
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
                            avatar: const Icon(Icons.location_on_outlined, size: 18),
                            label: Text(_siteId == null ? 'All sites' : _siteLabel),
                            onPressed: _pickSite,
                          ),
                        ),
                        const SizedBox(width: 8),
                        PressScale(
                          child: OutlinedButton(
                            style: _compactButton,
                            onPressed: _confirmMerge,
                            child: Text(_merging ? 'Merge (${_selected.length})' : 'Merge orders'),
                          ),
                        ),
                        if (_merging)
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 34),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => setState(() {
                              _merging = false;
                              _selected.clear();
                            }),
                            child: const Text('Cancel'),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_merging)
                  const EntranceItem(
                    index: 1,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'Select pending, approved, or revised orders. Only one approved or revised order can be included.',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12),
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
                        for (final s in ['', 'pending', 'approval_pending', 'approved', 'rejected', 'revised'])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: PressScale(
                              child: ChoiceChip(
                                label: Text(s.isEmpty ? 'All' : s),
                                selected: _status == s,
                                onSelected: (_) {
                                  setState(() {
                                    _status = s;
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
          if (_error != null && !_loading)
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
              maxIndex: 6,
              slide: 16,
              itemMs: 380,
              stepMs: 40,
              scaleFrom: 0.97,
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading
                    ? const CenteredScrollLoader()
                    : _error != null
                        ? const SizedBox.shrink()
                        : _items.isEmpty
                            ? EntranceItem(
                                index: 0,
                                child: EmptyListBody(
                                  message: listEmptyMessage(
                                    noun: 'purchase orders',
                                    search: _search,
                                    filterLabel: [
                                      if (_status.isNotEmpty) _status,
                                      if (_siteId != null) 'selected site',
                                    ].join(', '),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: AppTheme.formPadding,
                                itemCount: _items.length + 1,
                                separatorBuilder: (_, _) => const SizedBox(height: 8),
                                itemBuilder: (context, i) {
                                  if (i == _items.length) {
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
                                  final status = row['status']?.toString();
                                  final mergeable = id != null && _canMergeStatus(status);
                                  return EntranceItem(
                                    index: i,
                                    child: PressScale(
                                      enabled: !_merging && id != null,
                                      child: Card(
                                        child: ListTile(
                                          leading: _merging
                                              ? Checkbox(
                                                  value: id != null && _selected.contains(id),
                                                  onChanged: !mergeable
                                                      ? null
                                                      : (checked) {
                                                          final selectedId = id;
                                                          setState(() {
                                                            if (checked == true) {
                                                              _selected.add(selectedId);
                                                            } else {
                                                              _selected.remove(selectedId);
                                                            }
                                                          });
                                                        },
                                                )
                                              : null,
                                          title: Text(_poNumber(row)),
                                          subtitle: Text(() {
                                            final site = siteNameOf(row);
                                            final vendor = vendorNamesOf(row);
                                            final text = [
                                              if (site.isNotEmpty) site,
                                              if (vendor.isNotEmpty) vendor,
                                            ].join(' · ');
                                            return text.isEmpty ? 'Purchase order' : text;
                                          }()),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              StatusChip(status: status),
                                              PopupMenuButton<String>(
                                                tooltip: 'More',
                                                onSelected: (value) {
                                                  if (id == null) return;
                                                  if (value == 'delete') _deletePo(row);
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
                                          onTap: id == null
                                              ? null
                                              : () async {
                                                  await context.push<bool>('/procurement/po/$id');
                                                  if (mounted) _load();
                                                },
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

  Future<void> _deletePo(Map<String, dynamic> row) async {
    final id = idOf(row);
    if (id == null) return;
    final number = row['po_number']?.toString().trim().isNotEmpty == true
        ? row['po_number'].toString()
        : row['ro_number']?.toString() ?? 'this purchase order';
    final ok = await confirmAction(
      context,
      title: 'Delete purchase order?',
      message: '$number cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<AppServices>().po.delete(id);
      if (!mounted) return;
      showPmsSnack(context, 'Purchase order deleted');
      _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }
}

class PoDetailScreen extends StatefulWidget {
  const PoDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<PoDetailScreen> createState() => _PoDetailScreenState();
}

class _PoDetailScreenState extends State<PoDetailScreen> {
  Map<String, dynamic>? _doc;
  bool _loading = true;
  bool _docsBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final services = context.read<AppServices>();
      final doc = await services.po.getById(widget.id);
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
      await context.read<AppServices>().po.approval(widget.id, {'status': 'approved'});
      showPmsSnack(context, 'Approved');
      _load();
    } on ApiException catch (e) {
      showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _reject() async {
    try {
      await context.read<AppServices>().po.reject(widget.id);
      showPmsSnack(context, 'Rejected');
      _load();
    } on ApiException catch (e) {
      showPmsSnack(context, e.message, error: true);
    }
  }

  String _poNumber(Map<String, dynamic>? doc) {
    if (doc == null) return '';
    for (final key in ['po_number', 'ro_number', 'purchase_order_number']) {
      final text = doc[key]?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  Future<void> _downloadPdf() async {
    final doc = _doc;
    if (doc == null) return;
    final revisions = doc['revision'] is List ? asMapList(doc['revision'] as List) : <Map<String, dynamic>>[];
    if (revisions.isEmpty) {
      showPmsSnack(context, 'This purchase order has no PDF yet', error: true);
      return;
    }
    var index = revisions.length - 1;
    if (revisions.length > 1) {
      final picked = await showOptionPicker(
        context,
        title: 'Purchase order PDF',
        options: [
          for (var i = 0; i < revisions.length; i++)
            OptionItem(
              value: '$i',
              label: () {
                final revision = revisions[i];
                final number = revision['po_number']?.toString().trim() ?? '';
                final revisionNo = revision['revisionNo'] ?? i;
                return number.isEmpty ? 'Revision $revisionNo' : number;
              }(),
            ),
        ],
        selected: '$index',
      );
      if (picked == null || !mounted) return;
      index = int.tryParse(picked.value) ?? index;
    }
    setState(() => _docsBusy = true);
    try {
      final bytes = await context.read<AppServices>().po.downloadRo(widget.id, revision: index);
      if (!mounted) return;
      final revisionNo = revisions[index]['revisionNo'] ?? index;
      final number = _poNumber(doc);
      await shareDownloadedBytes(
        bytes: bytes,
        filename: '${number.isEmpty ? 'purchase-order' : number}-R$revisionNo.pdf',
        text: 'Purchase order PDF',
      );
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } catch (_) {
      if (mounted) showPmsSnack(context, 'Could not download the purchase order PDF', error: true);
    } finally {
      if (mounted) setState(() => _docsBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final status = doc?['status']?.toString() ?? '';
    final number = _poNumber(doc);
    final canApprove = status == 'approval_pending';
    final canReject = doc?['_rejectPO'] == true && status != 'rejected';
    final canRevise = doc?['_canRevise'] != false && status.isNotEmpty && status != 'rejected';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase order'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () async {
              final updated = await context.push<bool>('/procurement/po/${widget.id}/edit');
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
                    StatusChip(status: status),
                    const SizedBox(height: 8),
                    Text('PO: ${number.isEmpty ? '—' : number}'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _docsBusy ? null : _downloadPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Download PDF'),
                    ),
                    const SizedBox(height: 12),
                    Text('Vendor: ${doc == null ? '—' : (vendorNamesOf(doc).isEmpty ? '—' : vendorNamesOf(doc))}'),
                    Text('Site: ${doc == null ? '—' : (siteNameOf(doc).isEmpty ? '—' : siteNameOf(doc))}'),
                    const Divider(height: 32),
                    NamedItemLines(items: lineItemsOf(doc)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (canApprove)
                          FilledButton(onPressed: _approve, child: const Text('Approve')),
                        if (canRevise)
                          OutlinedButton(
                            onPressed: () async {
                              final updated = await context.push<bool>(
                                '/procurement/po/${widget.id}/revise',
                              );
                              if (updated == true && mounted) _load();
                            },
                            child: const Text('Revise'),
                          ),
                        if (canReject)
                          OutlinedButton(onPressed: _reject, child: const Text('Reject')),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class _PoLineEdit {
  _PoLineEdit(this.source) {
    qty.text = '${source['qty'] ?? 1}';
    rate.text = '${source['rate'] ?? 0}';
    gst.text = '${source['gst'] ?? 0}';
    amount.text = '${source['amount'] ?? 0}';
    budget.text = '${source['budget'] ?? 0}';
    remark.text = source['remark']?.toString() ?? '';
    procurementRemarks.text = source['procurement_remarks']?.toString() ?? '';
  }

  final Map<String, dynamic> source;
  final qty = TextEditingController();
  final rate = TextEditingController();
  final gst = TextEditingController();
  final amount = TextEditingController();
  final budget = TextEditingController();
  final remark = TextEditingController();
  final procurementRemarks = TextEditingController();

  void dispose() {
    qty.dispose();
    rate.dispose();
    gst.dispose();
    amount.dispose();
    budget.dispose();
    remark.dispose();
    procurementRemarks.dispose();
  }

  Map<String, dynamic> toPayload() {
    final brands = source['brandName'];
    final brandIds = brands is List ? brands.map(mongoId).whereType<String>().toList() : <String>[];
    final uom = mongoId(source['uom']);
    final parsedQty = num.tryParse(qty.text.trim()) ?? 1;
    final parsedRate = num.tryParse(rate.text.trim()) ?? 0;
    final parsedAmount = num.tryParse(amount.text.trim()) ?? (parsedQty * parsedRate);
    return {
      'item_id': mongoId(source['item_id'] ?? source['item']),
      'qty': parsedQty < 1 ? 1 : parsedQty,
      'rate': parsedRate,
      'gst': num.tryParse(gst.text.trim()) ?? 0,
      'amount': parsedAmount < 0 ? 0 : parsedAmount,
      'budget': num.tryParse(budget.text.trim()) ?? 0,
      'remark': remark.text.trim(),
      'procurement_remarks': procurementRemarks.text.trim(),
      'brandName': brandIds,
      if (uom != null) 'uom': uom,
    };
  }
}

class _PoVendorEdit {
  _PoVendorEdit(this.source) {
    subtotal.text = '${source['subtotal'] ?? 0}';
    totalTax.text = '${source['total_tax'] ?? 0}';
    freight.text = '${source['freight_charges'] ?? 0}';
    otherCharges.text = '${source['other_charges'] ?? 0}';
    totalAmount.text = '${source['total_amount'] ?? 0}';
    paymentTerms.text = source['paymentTerms']?.toString() ?? '';
    deliveryTerms.text = source['deliveryTerms']?.toString() ?? '';
    vendorRemark.text = source['vendorRemark']?.toString() ?? '';
  }

  final Map<String, dynamic> source;
  final subtotal = TextEditingController();
  final totalTax = TextEditingController();
  final freight = TextEditingController();
  final otherCharges = TextEditingController();
  final totalAmount = TextEditingController();
  final paymentTerms = TextEditingController();
  final deliveryTerms = TextEditingController();
  final vendorRemark = TextEditingController();

  void dispose() {
    subtotal.dispose();
    totalTax.dispose();
    freight.dispose();
    otherCharges.dispose();
    totalAmount.dispose();
    paymentTerms.dispose();
    deliveryTerms.dispose();
    vendorRemark.dispose();
  }

  Map<String, dynamic>? toPayload() {
    final vendorId = mongoId(source['vendor_id'] ?? source['vendor']);
    if (vendorId == null) return null;
    return {
      'vendor_id': vendorId,
      'subtotal': num.tryParse(subtotal.text.trim()) ?? 0,
      'total_tax': num.tryParse(totalTax.text.trim()) ?? 0,
      'freight_charges': num.tryParse(freight.text.trim()) ?? 0,
      'other_charges': num.tryParse(otherCharges.text.trim()) ?? 0,
      'other_tax': asNum(source['other_tax']) ?? 0,
      'freight_tax': asNum(source['freight_tax']) ?? 0,
      'total_amount': num.tryParse(totalAmount.text.trim()) ?? 0,
      'preferred': source['preferred'] == true,
      'vendor_quotation': source['vendor_quotation']?.toString() ?? '',
      'paymentTerms': paymentTerms.text.trim(),
      'deliveryTerms': deliveryTerms.text.trim(),
      'vendorRemark': vendorRemark.text.trim(),
    };
  }
}

class PoFormScreen extends StatefulWidget {
  const PoFormScreen({super.key, required this.id, this.revise = false});

  final String id;
  final bool revise;

  @override
  State<PoFormScreen> createState() => _PoFormScreenState();
}

class _PoFormScreenState extends State<PoFormScreen> {
  final _poNumber = TextEditingController();
  final _terms = TextEditingController();
  final _revisionRemarks = TextEditingController();
  Map<String, dynamic> _doc = {};
  String _status = '';
  bool _canRevise = true;
  String? _billingId;
  String _billingLabel = '';
  DateTime? _start;
  DateTime? _due;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _companies = [];
  final List<_PoLineEdit> _lines = [];
  final List<_PoVendorEdit> _vendors = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _poNumber.dispose();
    _terms.dispose();
    _revisionRemarks.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    for (final vendor in _vendors) {
      vendor.dispose();
    }
    super.dispose();
  }

  String _textOf(dynamic value) {
    final text = labelOf(value, fallback: '');
    return text == '—' ? '' : text;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await context.read<AppServices>().po.getById(widget.id);
      List<Map<String, dynamic>> companies = [];
      try {
        companies = await context.read<SettingsApis>().companies.listAll();
      } catch (_) {
        companies = [];
      }
      if (!mounted) return;
      for (final line in _lines) {
        line.dispose();
      }
      for (final vendor in _vendors) {
        vendor.dispose();
      }
      _lines.clear();
      _vendors.clear();
      _lines.addAll(lineItemsOf(doc).map(_PoLineEdit.new));
      final vendorRows = doc['vendors_total'];
      if (vendorRows is List) {
        _vendors.addAll(
          vendorRows.whereType<Map>().map((row) => _PoVendorEdit(Map<String, dynamic>.from(row))),
        );
      }
      setState(() {
        _doc = doc;
        _status = doc['status']?.toString() ?? '';
        _canRevise = doc['_canRevise'] != false && _status != 'rejected';
        _poNumber.text = doc['po_number']?.toString() ?? '';
        _terms.text = doc['terms_condition']?.toString() ?? '';
        _billingId = mongoId(doc['billing_address_id']);
        _billingLabel = _textOf(doc['billing_address_id']);
        _start = DateTime.tryParse(doc['poStartDate']?.toString() ?? '');
        _due = DateTime.tryParse(doc['due_date']?.toString() ?? '');
        _companies = companies;
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

  Future<void> _pickDate({required bool start}) async {
    final initial = (start ? _start : _due) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _due = picked;
      }
    });
  }

  Future<void> _save({bool sendForApproval = false}) async {
    setState(() => _saving = true);
    try {
      final api = context.read<AppServices>().po;
      await api.update(widget.id, {
        'po_number': _poNumber.text.trim(),
        if (_billingId != null) 'billing_address_id': _billingId,
        if (_start != null) 'poStartDate': _start!.toIso8601String(),
        if (_due != null) 'due_date': _due!.toIso8601String(),
        'terms_condition': _terms.text,
        'revision_remarks': _revisionRemarks.text.trim(),
        if (sendForApproval) 'status': 'approval_pending',
      });
      if (!sendForApproval && _canRevise) {
        final vendors = _vendors.map((row) => row.toPayload()).whereType<Map<String, dynamic>>().toList();
        await api.revise(widget.id, {
          if (_start != null) 'poStartDate': _start!.toIso8601String(),
          if (_due != null) 'due_date': _due!.toIso8601String(),
          'terms_condition': _terms.text,
          'revisionRemarks': _revisionRemarks.text.trim(),
          'items': _lines.map((line) => line.toPayload()).toList(),
          if (vendors.isNotEmpty) 'vendors_total': vendors,
        });
      }
      if (!mounted) return;
      await showSavedConfirmation(
        context,
        sendForApproval
            ? 'Purchase order sent for approval'
            : widget.revise
                ? 'Purchase order revised'
                : 'Purchase order updated',
      );
      if (mounted) context.pop(true);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.revise ? 'Revise purchase order' : 'Edit purchase order'),
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
                    _PreviousPoCard(doc: _doc),
                    const SizedBox(height: 16),
                    const Text('Update', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _poNumber,
                      decoration: const InputDecoration(labelText: 'PO number'),
                    ),
                    const SizedBox(height: 12),
                    PickerField(
                      label: 'Billing company',
                      valueLabel: _billingLabel,
                      onTap: () async {
                        final picked = await showOptionPicker(
                          context,
                          title: 'Billing company',
                          options: mapToOptions(
                            _companies,
                            labelOfRow: (r) => r['companyName']?.toString() ?? labelOf(r),
                          ),
                          selected: _billingId,
                          emptyMessage: 'No companies found',
                        );
                        if (picked == null) return;
                        setState(() {
                          _billingId = picked.value;
                          _billingLabel = picked.label;
                        });
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Start ${formatDate(_start?.toIso8601String())}'),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () => _pickDate(start: true),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Due ${formatDate(_due?.toIso8601String())}'),
                      trailing: const Icon(Icons.event_outlined),
                      onTap: () => _pickDate(start: false),
                    ),
                    TextField(
                      controller: _terms,
                      decoration: const InputDecoration(labelText: 'Terms and conditions'),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _revisionRemarks,
                      decoration: const InputDecoration(labelText: 'Revision remarks'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    const Text('Items', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if (_lines.isEmpty)
                      const Text('No line items on this purchase order'),
                    for (final line in _lines)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(itemLabel(line.source), style: const TextStyle(fontWeight: FontWeight.w700)),
                              if (_textOf(line.source['uom']).isNotEmpty)
                                Text('UOM: ${_textOf(line.source['uom'])}'),
                              const SizedBox(height: 8),
                              TextField(
                                controller: line.qty,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Qty'),
                              ),
                              TextField(
                                controller: line.rate,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Rate'),
                              ),
                              TextField(
                                controller: line.gst,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'GST'),
                              ),
                              TextField(
                                controller: line.budget,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Budget'),
                              ),
                              TextField(
                                controller: line.amount,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Amount'),
                              ),
                              TextField(
                                controller: line.remark,
                                decoration: const InputDecoration(labelText: 'Remark'),
                              ),
                              TextField(
                                controller: line.procurementRemarks,
                                decoration: const InputDecoration(labelText: 'Procurement remarks'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_vendors.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Vendors', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      for (final vendor in _vendors)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  _textOf(vendor.source['vendor_id'] ?? vendor.source['vendor']).isEmpty
                                      ? 'Vendor'
                                      : _textOf(vendor.source['vendor_id'] ?? vendor.source['vendor']),
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                TextField(
                                  controller: vendor.subtotal,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'Subtotal'),
                                ),
                                TextField(
                                  controller: vendor.totalTax,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'Tax'),
                                ),
                                TextField(
                                  controller: vendor.freight,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'Freight'),
                                ),
                                TextField(
                                  controller: vendor.otherCharges,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'Other charges'),
                                ),
                                TextField(
                                  controller: vendor.totalAmount,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'Total amount'),
                                ),
                                TextField(
                                  controller: vendor.paymentTerms,
                                  decoration: const InputDecoration(labelText: 'Payment terms'),
                                ),
                                TextField(
                                  controller: vendor.deliveryTerms,
                                  decoration: const InputDecoration(labelText: 'Delivery terms'),
                                ),
                                TextField(
                                  controller: vendor.vendorRemark,
                                  decoration: const InputDecoration(labelText: 'Vendor remark'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _saving ? null : () => _save(),
                      child: Text(_saving ? 'Saving…' : 'Update purchase order'),
                    ),
                    if (!widget.revise && _status == 'pending') ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _saving ? null : () => _save(sendForApproval: true),
                        child: const Text('Send for approval'),
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _PreviousPoCard extends StatelessWidget {
  const _PreviousPoCard({required this.doc});

  final Map<String, dynamic> doc;

  String _show(dynamic value) {
    final text = labelOf(value, fallback: '');
    if (text.isEmpty || text == '—') return '';
    return text;
  }

  String _address(dynamic address) {
    if (address is! Map) return '';
    final nested = address['address'] is Map ? Map<String, dynamic>.from(address['address'] as Map) : null;
    return [
      address['site_name'],
      address['location'],
      address['street_address'] ?? nested?['street_address'],
      address['city'] ?? nested?['city'],
      address['state'] ?? nested?['state'],
    ].map((part) => part?.toString().trim() ?? '').where((part) => part.isNotEmpty).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final vendor = vendorNamesOf(doc);
    final rows = <MapEntry<String, String>>[
      MapEntry('Status', doc['status']?.toString() ?? ''),
      MapEntry('PO number', doc['po_number']?.toString() ?? ''),
      MapEntry('Title', doc['title']?.toString() ?? ''),
      MapEntry('PR number', doc['requisition_request_number']?.toString() ?? ''),
      MapEntry('PR type', doc['prType']?.toString() ?? ''),
      MapEntry('Order type', doc['order_type']?.toString() ?? ''),
      MapEntry('Open order', doc['open_order']?.toString() ?? ''),
      MapEntry('Site', siteNameOf(doc)),
      MapEntry('Vendor', vendor),
      MapEntry('Local purchase', doc['local_purchase']?.toString() ?? ''),
      MapEntry('Billing', _show(doc['billing_address_id'])),
      MapEntry('Delivery', _address(doc['delivery_address'])),
      MapEntry('Start', formatDate(doc['poStartDate'])),
      MapEntry('Due', formatDate(doc['due_date'])),
      MapEntry('Remarks', doc['remarks']?.toString() ?? ''),
      MapEntry('Terms', doc['terms_condition']?.toString() ?? ''),
    ].where((row) => row.value.trim().isNotEmpty && row.value.trim() != '—').toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Current details', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(row.key, style: const TextStyle(color: AppTheme.muted)),
                    ),
                    Expanded(child: Text(row.value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String rcHeadline(Map<String, dynamic> row) {
  final no = row['comparative_no']?.toString().trim() ?? '';
  final rr = row['requisition_request_id'];
  final rrMap = rr is Map ? Map<String, dynamic>.from(rr) : null;
  final title = rrMap?['title']?.toString().trim() ?? '';
  final rrNo = rrMap?['requisition_request_number']?.toString().trim() ?? '';
  if (no.isNotEmpty && title.isNotEmpty) return '$no · $title';
  if (no.isNotEmpty) return no;
  if (rrNo.isNotEmpty && title.isNotEmpty) return 'RR $rrNo · $title';
  if (title.isNotEmpty) return title;
  if (rrNo.isNotEmpty) return 'RR $rrNo';
  return 'Rate comparative';
}

String rcSubtitle(Map<String, dynamic> row) {
  final rr = row['requisition_request_id'];
  final rrMap = rr is Map ? Map<String, dynamic>.from(rr) : null;
  final rrNo = rrMap?['requisition_request_number']?.toString().trim() ?? '';
  final site = siteNameOf(row);
  final vendor = vendorNamesOf(row);
  final parts = [
    if (rrNo.isNotEmpty) 'RR $rrNo',
    if (site.isNotEmpty) site,
    if (vendor.isNotEmpty) vendor,
  ];
  return parts.isEmpty ? 'Rate comparative' : parts.join(' · ');
}

class RrStatusScreen extends StatelessWidget {
  const RrStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RrListScreen();
  }
}
