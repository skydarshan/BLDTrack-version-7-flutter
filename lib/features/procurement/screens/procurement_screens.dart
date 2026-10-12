import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/form_validation_helpers.dart';
import '../../../core/utils/list_query.dart';
import '../../../core/theme/modern_widgets.dart';
import '../../app/app_services.dart';
import '../../app/app_shell.dart';
import '../../pms/widgets/media_widgets.dart';
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
    final remaining = firstMap(_overview, ['remaining_inventory', 'remainingInventory']);
    final sites = firstMap(_overview, ['active_sites', 'activeSites']);
    final pending = firstMap(_overview, [
      'items_yet_to_receive',
      'itemsYetToReceive',
      'itemsYetToBeReceived',
    ]);
    final prs = firstMap(_overview, ['total_purchase_requests', 'totalPurchaseRequests']);

    final pendingPrs = firstNonNull(prs, ['pending_count', 'pendingCount']) ?? 0;
    final pendingLines = firstNonNull(pending, [
      'line_items_count',
      'pendingLineItems',
      'pending_count',
      'count',
    ]);

    return Scaffold(
      extendBody: true,
      appBar: const ModernAppBar(
        title: 'Procurement',
        actions: [WorkspaceSwitcherButton(), UserProfileButton()],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const CenteredScrollLoader()
            : LayoutBuilder(
                builder: (context, constraints) {
                  final padding = AppTheme.pagePadding;
                  final innerHeight = constraints.maxHeight.isFinite
                      ? math.max(0.0, constraints.maxHeight - padding.vertical)
                      : 0.0;
                  final screenH = MediaQuery.sizeOf(context).height;
                  // Stats take most of the leftover height. Actions stay near
                  // their natural row size so they do not turn into tall banners.
                  final statGrowthCap = (screenH * 0.05).clamp(32.0, 56.0);
                  final actionGrowthCap = (screenH * 0.024).clamp(12.0, 22.0);
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: padding,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: innerHeight),
                      child: _ProcurementHomeBalance(
                        statGap: AppTheme.gridGap,
                        actionGap: AppTheme.gridGap,
                        sectionGap: AppTheme.sectionGap,
                        statGrowthCap: statGrowthCap,
                        actionGrowthCap: actionGrowthCap,
                        banner: _error != null
                            ? ErrorBanner(message: _error!, onRetry: _load)
                            : const SizedBox.shrink(),
                        stats: [
                          BentoStatCard(
                            expand: true,
                            badgeSize: 44,
                            glyphSize: 24,
                            label: 'Inventory value',
                            value: '${remaining['valueFormatted'] ?? remaining['value'] ?? 0}',
                            icon: Icons.inventory_2_rounded,
                            color: AppTheme.accent,
                          ),
                          BentoStatCard(
                            expand: true,
                            badgeSize: 44,
                            glyphSize: 24,
                            label: 'Active sites',
                            value: '${sites['count'] ?? 0}',
                            icon: Icons.place_rounded,
                            color: AppTheme.info,
                          ),
                          BentoStatCard(
                            expand: true,
                            badgeSize: 44,
                            glyphSize: 24,
                            label: 'Yet to receive',
                            value: '${pending['valueFormatted'] ?? pending['value'] ?? 0}',
                            hint: pendingLines != null ? '$pendingLines pending lines' : null,
                            icon: Icons.local_shipping_rounded,
                            color: AppTheme.orange,
                            onTap: () => context.go('/dmr/status'),
                          ),
                          BentoStatCard(
                            expand: true,
                            badgeSize: 44,
                            glyphSize: 24,
                            label: 'Purchase requests',
                            value: '${prs['count'] ?? 0}',
                            hint: '$pendingPrs pending',
                            icon: Icons.description_rounded,
                            color: AppTheme.brand,
                            highlight: (pendingPrs is num ? pendingPrs > 0 : '$pendingPrs' != '0'),
                            onTap: () => context.go('/procurement/rr'),
                          ),
                        ],
                        header: const SectionHeader(title: 'Quick actions', color: AppTheme.brand),
                        actions: [
                          ModernListCard(
                            expand: true,
                            title: 'New requisition',
                            subtitle: 'Raise an RR',
                            icon: Icons.add_box_rounded,
                            color: AppTheme.brand,
                            onTap: () => context.push('/procurement/rr/new'),
                          ),
                          ModernListCard(
                            expand: true,
                            title: 'Approvals',
                            subtitle: 'Review pending PRs',
                            icon: Icons.verified_rounded,
                            color: AppTheme.success,
                            onTap: () => context.go('/procurement/approvals'),
                          ),
                          ModernListCard(
                            expand: true,
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
                },
              ),
      ),
    );
  }
}

/// Equal-height stat grid, then comfortable equal-height quick actions.
/// Leftover viewport goes to the stat cards first, then a small amount to
/// the action cards. Nothing is inserted as an empty spacer.
class _ProcurementHomeBalance extends MultiChildRenderObjectWidget {
  _ProcurementHomeBalance({
    required Widget banner,
    required List<Widget> stats,
    required Widget header,
    required List<Widget> actions,
    required this.statGap,
    required this.actionGap,
    required this.sectionGap,
    required this.statGrowthCap,
    required this.actionGrowthCap,
  })  : assert(stats.length == 4),
        super(children: [banner, ...stats, header, ...actions]);

  final double statGap;
  final double actionGap;
  final double sectionGap;
  final double statGrowthCap;
  final double actionGrowthCap;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderProcurementHomeBalance(
      statGap: statGap,
      actionGap: actionGap,
      sectionGap: sectionGap,
      statGrowthCap: statGrowthCap,
      actionGrowthCap: actionGrowthCap,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderProcurementHomeBalance renderObject,
  ) {
    renderObject
      ..statGap = statGap
      ..actionGap = actionGap
      ..sectionGap = sectionGap
      ..statGrowthCap = statGrowthCap
      ..actionGrowthCap = actionGrowthCap;
  }
}

class _HomeParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderProcurementHomeBalance extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HomeParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HomeParentData> {
  _RenderProcurementHomeBalance({
    required double statGap,
    required double actionGap,
    required double sectionGap,
    required double statGrowthCap,
    required double actionGrowthCap,
  })  : _statGap = statGap,
        _actionGap = actionGap,
        _sectionGap = sectionGap,
        _statGrowthCap = statGrowthCap,
        _actionGrowthCap = actionGrowthCap;

  double _statGap;
  double _actionGap;
  double _sectionGap;
  double _statGrowthCap;
  double _actionGrowthCap;

  double get statGap => _statGap;
  set statGap(double value) {
    if (_statGap == value) return;
    _statGap = value;
    markNeedsLayout();
  }

  double get actionGap => _actionGap;
  set actionGap(double value) {
    if (_actionGap == value) return;
    _actionGap = value;
    markNeedsLayout();
  }

  double get sectionGap => _sectionGap;
  set sectionGap(double value) {
    if (_sectionGap == value) return;
    _sectionGap = value;
    markNeedsLayout();
  }

  double get statGrowthCap => _statGrowthCap;
  set statGrowthCap(double value) {
    if (_statGrowthCap == value) return;
    _statGrowthCap = value;
    markNeedsLayout();
  }

  double get actionGrowthCap => _actionGrowthCap;
  set actionGrowthCap(double value) {
    if (_actionGrowthCap == value) return;
    _actionGrowthCap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HomeParentData) {
      child.parentData = _HomeParentData();
    }
  }

  void _place(RenderBox box, Offset offset) {
    (box.parentData! as _HomeParentData).offset = offset;
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final target = constraints.minHeight.isFinite ? constraints.minHeight : 0.0;
    final banner = firstChild;
    if (banner == null || width <= 0) {
      size = constraints.constrain(Size(width, target));
      return;
    }

    final stats = <RenderBox>[];
    var cursor = childAfter(banner);
    for (var i = 0; i < 4 && cursor != null; i++) {
      stats.add(cursor);
      cursor = childAfter(cursor);
    }
    final header = cursor;
    final actions = <RenderBox>[];
    cursor = header == null ? null : childAfter(header);
    while (cursor != null) {
      actions.add(cursor);
      cursor = childAfter(cursor);
    }

    banner.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);

    final statWidth = math.max(0.0, (width - statGap) / 2);
    var naturalStat = 0.0;
    for (final card in stats) {
      card.layout(BoxConstraints(maxWidth: statWidth), parentUsesSize: true);
      naturalStat = math.max(naturalStat, card.size.height);
    }

    if (header != null) {
      header.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    }

    var naturalAction = 0.0;
    for (final card in actions) {
      card.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
      naturalAction = math.max(naturalAction, card.size.height);
    }

    final headerHeight = header?.size.height ?? 0.0;
    final actionGaps = actions.isEmpty ? 0.0 : actionGap * (actions.length - 1);
    final fixed = banner.size.height +
        statGap +
        sectionGap +
        headerHeight +
        actionGaps;
    final base = fixed + (2 * naturalStat) + (actions.length * naturalAction);
    final extra = math.max(0.0, target - base);

    var statAdd = math.min(statGrowthCap, stats.isEmpty ? 0.0 : extra / 2);
    var used = statAdd * 2;
    var actionAdd = 0.0;
    if (actions.isNotEmpty) {
      actionAdd = math.min(actionGrowthCap, (extra - used) / actions.length);
      used += actionAdd * actions.length;
    }
    final statRoom = (statGrowthCap - statAdd) * 2;
    if (statRoom > 0 && extra > used) {
      statAdd += math.min(statGrowthCap - statAdd, (extra - used) / 2);
    }

    final statHeight = naturalStat + statAdd;
    final actionHeight = naturalAction + actionAdd;
    final statConstraints = BoxConstraints.tightFor(width: statWidth, height: statHeight);
    for (final card in stats) {
      card.layout(statConstraints, parentUsesSize: true);
    }
    final actionConstraints = BoxConstraints.tightFor(width: width, height: actionHeight);
    for (final card in actions) {
      card.layout(actionConstraints, parentUsesSize: true);
    }

    var y = 0.0;
    _place(banner, Offset.zero);
    y += banner.size.height;

    final xRight = statWidth + statGap;
    if (stats.length == 4) {
      _place(stats[0], Offset(0, y));
      _place(stats[1], Offset(xRight, y));
      y += statHeight + statGap;
      _place(stats[2], Offset(0, y));
      _place(stats[3], Offset(xRight, y));
      y += statHeight + sectionGap;
    }
    if (header != null) {
      _place(header, Offset(0, y));
      y += headerHeight;
    }
    for (var i = 0; i < actions.length; i++) {
      _place(actions[i], Offset(0, y));
      y += actionHeight;
      if (i != actions.length - 1) y += actionGap;
    }

    size = constraints.constrain(Size(width, math.max(target, y)));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
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
        ...rrSearchQuery(_search),
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
                for (final t in ['all', 'draft', 'pending', 'revise', 'approved', 'revised', 'rejected'])
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
                  ? const CenteredScrollLoader()
                  : _items.isEmpty
                      ? EmptyListBody(
                          message: listEmptyMessage(
                            noun: 'requisitions',
                            search: _search,
                            filterLabel: _tab == 'all' ? null : _tab,
                          ),
                        )
                      : ListView.separated(
                          padding: AppTheme.listPadding,
                          itemCount: _items.length + 1,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            if (i == _items.length) {
                              final pages = paginationTotalPages(_pagination);
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
      final services = context.read<AppServices>();
      final doc = await services.rr.getDetail(widget.id);
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
                    NamedItemLines(items: items),
                    for (final line in items)
                      for (final url in attachmentUrlsOf(line['attachment'] ?? line['attachments']))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.attach_file),
                          title: Text(attachmentName(url), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    await Future.wait([
      _reloadSites(),
      _reloadCategories(),
      _reloadVendors(),
      _reloadItems(),
      _reloadBrands(),
    ]);
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
      options: mapToOptions(_categories, labelOfRow: (r) => r['name']?.toString() ?? labelOf(r)),
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
      final uoms = await context.read<SettingsApis>().getItemUomOptions(picked.value);
      line.uomOptions = mapToOptions(
        uoms,
        labelOfRow: (r) => r['uom_name']?.toString() ?? r['unit']?.toString() ?? labelOf(r),
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
      options: mapToOptions(_sites, labelOfRow: (r) => r['site_name']?.toString() ?? labelOf(r)),
      selected: _siteId,
      emptyMessage: 'No sites found',
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
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _nextNumber = null);
        showPmsSnack(context, e.message, error: true);
      }
    }
  }

  Future<void> _save() async {
    _fieldErrors.clear();
    _fieldErrors.set('category', requiredSelection(_categoryId, 'Request category'));
    _fieldErrors.set('site', requiredSelection(_siteId, 'Site'));
    _fieldErrors.set('pr', _nextNumber == null ? 'PR number is missing — pick the site again' : null);
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
      await context.read<AppServices>().rr.create(
        {
          'title': _categoryLabel.trim(),
          'prType': _prType,
          'date': _date.toIso8601String(),
          'expected_delivery_date': _expected.toIso8601String(),
          'requisition_request_number': _nextNumber,
          'site': _siteId,
          'local_purchase': _localPurchase,
          'status': 'pending',
          'new_request': true,
          'remarks': _remarks.text.trim(),
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
        },
        files: files,
      );
      if (!mounted) return;
      await showSavedConfirmation(context, 'Requisition created');
      if (mounted) context.pop();
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
      setState(() => _saveError = 'Upload failed. Check the connection and tap Retry.');
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
          if (_saveError != null)
            ErrorBanner(message: _saveError!, onRetry: _saving ? null : _save),
          if (_fieldErrors.hasErrors) ValidationSummaryBanner(messages: _fieldErrors.messages),
          AppDropdownFormField<String>(
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
            valueLabel: _siteLabel,
            errorText: _fieldErrors['site'],
            onTap: _pickSite,
          ),
          const SizedBox(height: 12),
          _NextPrNumberCard(number: _nextNumber, siteLabel: _siteLabel),
          if (_fieldErrors['pr'] != null)
            Text(_fieldErrors['pr']!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
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
          AppDropdownFormField<String>(
            initialValue: _localPurchase,
            decoration: const InputDecoration(labelText: 'Local purchase'),
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
          ],
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
          if (_fieldErrors['lines'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_fieldErrors['lines']!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
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
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Delete line',
                          onPressed: () {
                            final removed = _lines.removeAt(i);
                            setState(() {});
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              removed.dispose();
                            });
                          },
                          icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                        ),
                      ],
                    ),
                    PickerField(
                      label: 'Item',
                      valueLabel: _lines[i].itemLabel,
                      enabled: _categoryId != null,
                      onTap: () async {
                        if (_categoryId == null) {
                          showPmsSnack(context, 'Select request category first', error: true);
                          return;
                        }
                        await _reloadItems(categoryId: _categoryId);
                        if (!mounted) return;
                        final picked = await showOptionPicker(
                          context,
                          title: 'Item',
                          options: mapToOptions(
                            _catalogItems,
                            labelOfRow: (r) => r['item_name']?.toString() ?? labelOf(r),
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
                      _ReadOnlyField(label: 'Item code', value: _lines[i].itemCode),
                      _ReadOnlyField(label: 'Specification', value: _lines[i].specification),
                      _ReadOnlyField(label: 'Category', value: _lines[i].categoryLabel),
                      _ReadOnlyField(label: 'Sub category', value: _lines[i].subCategoryLabel),
                      _ReadOnlyField(label: 'HSN code', value: _lines[i].hsn),
                      PickerField(
                        label: 'UOM',
                        valueLabel: _lines[i].uomLabel,
                        onTap: () async {
                          final opts = _lines[i].uomOptions;
                          if (opts.isEmpty) {
                            showPmsSnack(context, 'No UOM options for this item', error: true);
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
                    const SizedBox(height: 8),
                    TextField(
                      controller: _lines[i].freight,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Freight'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _lines[i].remark,
                      decoration: const InputDecoration(labelText: 'Remark'),
                    ),
                    const SizedBox(height: 8),
                    _LineUploadField(
                      files: _lines[i].attachments,
                      onChanged: (files) => setState(() => _lines[i].attachments = files),
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
            title: Text(files[i].filename, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  ? const CenteredScrollLoader()
                  : _items.isEmpty
                      ? EmptyListBody(
                          message: listEmptyMessage(noun: 'pending approvals'),
                        )
                      : ListView.separated(
                          padding: AppTheme.formPadding,
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
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
