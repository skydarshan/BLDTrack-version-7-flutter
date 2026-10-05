import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/list_query.dart';
import '../../app/app_services.dart';
import '../../app/app_shell.dart';
import '../../pms/widgets/pms_widgets.dart';
import 'procurement_screens.dart';

class RcListScreen extends StatefulWidget {
  const RcListScreen({super.key});

  @override
  State<RcListScreen> createState() => _RcListScreenState();
}

class _RcListScreenState extends State<RcListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _pagination;
  int _page = 1;
  String _search = '';

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
      final res = await context.read<AppServices>().rc.list({
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
      appBar: AppBar(
        title: const Text('Rate comparatives'),
        actions: const [WorkspaceSwitcherButton()],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppTheme.searchPadding,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search number / remarks…',
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
                              message: listEmptyMessage(
                                noun: 'rate comparatives',
                                search: _search,
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
                                return Card(
                                  child: ListTile(
                                    title: Text(rcHeadline(row)),
                                    subtitle: Text(rcSubtitle(row)),
                                    trailing: StatusChip(status: row['status']?.toString()),
                                    onTap: () => context.push('/procurement/rc/${idOf(row)}'),
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

class RcDetailScreen extends StatefulWidget {
  const RcDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<RcDetailScreen> createState() => _RcDetailScreenState();
}

class _RcDetailScreenState extends State<RcDetailScreen> {
  bool _loading = true;
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
                    StatusChip(status: doc?['status']?.toString()),
                    const SizedBox(height: 8),
                    Text(rcHeadline(doc ?? {})),
                    Text(rcSubtitle(doc ?? {})),
                    Text('Category: ${labelOf(doc?['purchase_category'] ?? doc?['category'])}'),
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

class RateApprovalsScreen extends StatefulWidget {
  const RateApprovalsScreen({super.key});

  @override
  State<RateApprovalsScreen> createState() => _RateApprovalsScreenState();
}

class _RateApprovalsScreenState extends State<RateApprovalsScreen> {
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
      final api = context.read<AppServices>().rc;
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
      appBar: AppBar(title: const Text('Rate approvals')),
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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const EmptyState(message: 'No pending rate approvals')
                    : ListView.separated(
                        padding: AppTheme.formPadding,
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final row = _items[i];
                          return Card(
                            child: ListTile(
                              title: Text(rcHeadline(row)),
                              subtitle: Text(rcSubtitle(row)),
                              onTap: () => context.push('/procurement/rc/${idOf(row)}'),
                            ),
                          );
                        },
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
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _pagination;
  String _status = '';
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
      final services = context.read<AppServices>();
      final q = _search.trim();
      if (q.isEmpty) {
        final res = await services.po.list({
          'page': _page,
          'limit': 20,
          if (_status.isNotEmpty) 'status': _status,
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

      final parts = await Future.wait([
        services.po.list({
          'page': 1,
          'limit': 50,
          'po_number': q,
          if (_status.isNotEmpty) 'status': _status,
        }),
        for (final id in itemIds)
          services.po.list({
            'page': 1,
            'limit': 50,
            'item_id': id,
            if (_status.isNotEmpty) 'status': _status,
          }),
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

  @override
  Widget build(BuildContext context) {
    final pages = paginationTotalPages(_pagination);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase orders'),
        actions: const [WorkspaceSwitcherButton()],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppTheme.searchPadding,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search PO number / item…',
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
                for (final s in ['', 'pending', 'approval_pending', 'approved', 'rejected', 'revised'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
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
                                noun: 'purchase orders',
                                search: _search,
                                filterLabel: _status.isEmpty ? null : _status,
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
                                return Card(
                                  child: ListTile(
                                    title: Text(
                                      row['po_number']?.toString() ??
                                          row['ro_number']?.toString() ??
                                          row['purchase_order_number']?.toString() ??
                                          'PO',
                                    ),
                                    subtitle: Text(labelOf(row['vendor'] ?? row['site'])),
                                    trailing: StatusChip(status: row['status']?.toString()),
                                    onTap: () => context.push('/procurement/po/${idOf(row)}'),
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

class PoDetailScreen extends StatefulWidget {
  const PoDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<PoDetailScreen> createState() => _PoDetailScreenState();
}

class _PoDetailScreenState extends State<PoDetailScreen> {
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

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      appBar: AppBar(title: const Text('Purchase order')),
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
                    Text('PO: ${doc?['po_number'] ?? doc?['ro_number'] ?? doc?['purchase_order_number'] ?? '—'}'),
                    Text('Vendor: ${labelOf(doc?['vendor'])}'),
                    Text('Site: ${labelOf(doc?['site'])}'),
                    const Divider(height: 32),
                    NamedItemLines(items: lineItemsOf(doc)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(onPressed: _approve, child: const Text('Approve')),
                        OutlinedButton(onPressed: _reject, child: const Text('Reject')),
                      ],
                    ),
                  ],
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
  final site = labelOf(row['site'], fallback: '');
  final parts = [
    if (rrNo.isNotEmpty) 'RR $rrNo',
    if (site.isNotEmpty) site,
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
