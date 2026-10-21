import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/org/org_modules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/modern_widgets.dart';
import '../../../core/widgets/motion.dart';
import '../../auth/providers/auth_provider.dart';
import '../../org/org_session.dart';
import '../../settings/services/settings_apis.dart';
import '../../settings/utils/permissions.dart';
import '../services/pms_services.dart';
import '../utils/dpr_format.dart';
import '../utils/site_options.dart';
import '../widgets/pickers.dart';
import '../widgets/pms_widgets.dart';

class DprReportsScreen extends StatefulWidget {
  const DprReportsScreen({super.key});

  @override
  State<DprReportsScreen> createState() => _DprReportsScreenState();
}

class _DprReportsScreenState extends State<DprReportsScreen> {
  int _tab = 0;
  bool _bootstrapped = false;
  String? _routeSite;

  List<OptionItem> _sites = const [];
  String? _siteId;
  String _siteLabel = 'All sites';

  String? _projectId;
  String _projectLabel = 'All projects';
  String? _status;
  String? _preparedBy;
  String _preparedByLabel = 'Anyone';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _sortBy = 'report_date';
  String _sortOrder = 'desc';

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  bool _hasMore = false;

  bool _todayLoading = false;
  Map<String, dynamic>? _today;

  bool _missingLoading = false;
  Map<String, dynamic>? _missing;
  DateTime _missingDate = DateTime.now();
  bool _reminding = false;
  String? _openedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final query = GoRouterState.of(context).uri.queryParameters;
    final next = query['site'];
    final site = (next == null || next.isEmpty) ? null : next;
    final open = query['open'];
    if (_bootstrapped && open != null && open.isNotEmpty && open != _openedId) {
      _openedId = open;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openReport(open));
    }
    if (!_bootstrapped || site == _routeSite) return;
    _routeSite = site;
    _applySite(site);
    _reloadCurrent();
  }

  Future<void> _bootstrap() async {
    final query = GoRouterState.of(context).uri.queryParameters;
    final tab = query['tab'];
    if (tab == 'today') _tab = 1;
    if (tab == 'missing' || query['filter'] == 'missing') _tab = 2;
    _routeSite = query['site'];
    _siteId = _routeSite;
    try {
      _sites = await loadSiteOptions(context);
    } catch (_) {}
    if (_sites.length == 1) {
      _siteId = _sites.first.value;
      _siteLabel = _sites.first.label;
    } else {
      _siteLabel = _labelFor(_siteId) ?? 'All sites';
    }
    _bootstrapped = true;
    if (!mounted) return;
    setState(() {});
    await _reloadCurrent();
    final open = query['open'];
    if (open != null && open.isNotEmpty && open != _openedId && mounted) {
      _openedId = open;
      await _openReport(open);
    }
  }

  Future<void> _openReport(String id) async {
    final changed = await context.push('/pms/dpr/$id');
    if (changed == true && mounted) _reloadCurrent();
  }

  String? _labelFor(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final site in _sites) {
      if (site.value == id) return site.label;
    }
    return null;
  }

  void _applySite(String? id) {
    _siteId = id;
    _siteLabel = _labelFor(id) ?? (id == null ? 'All sites' : _siteLabel);
    _projectId = null;
    _projectLabel = 'All projects';
  }

  Future<void> _reloadCurrent() {
    if (_tab == 1) return _loadToday();
    if (_tab == 2) return _loadMissing();
    return _loadHistory(reset: true);
  }

  Future<void> _loadHistory({bool reset = false}) async {
    if (reset) {
      _page = 1;
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await context.read<PmsServices>().dpr.list({
        'page': _page,
        'limit': 20,
        'site': _siteId,
        'project': _projectId,
        'prepared_by': _preparedBy,
        'status': _status,
        'date_from': _dateFrom == null ? null : apiDay(_dateFrom!),
        'date_to': _dateTo == null ? null : apiDay(_dateTo!),
        'sortBy': _sortBy,
        'sortOrder': _sortOrder,
      });
      if (!mounted) return;
      setState(() {
        _items = reset ? res.items : [..._items, ...res.items];
        _hasMore = dprHasNextPage(res.pagination, _page);
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

  Future<void> _loadToday() async {
    if (_siteId == null || _siteId!.isEmpty) {
      setState(() {
        _today = null;
        _todayLoading = false;
      });
      return;
    }
    setState(() => _todayLoading = true);
    try {
      final data = await context.read<PmsServices>().dpr.getForDate(siteId: _siteId!);
      if (!mounted) return;
      setState(() {
        _today = data;
        _todayLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _todayLoading = false);
      showPmsSnack(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _todayLoading = false);
      showPmsSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _loadMissing() async {
    setState(() => _missingLoading = true);
    try {
      final data = await context.read<PmsServices>().dpr.missing(date: apiDay(_missingDate));
      if (!mounted) return;
      setState(() {
        _missing = data;
        _missingLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _missingLoading = false);
      showPmsSnack(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _missingLoading = false);
      showPmsSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _pickSite() async {
    final options = [
      if (_tab == 0) const OptionItem(value: '', label: 'All sites'),
      ..._sites,
    ];
    final picked = await showOptionPicker(
      context,
      title: 'Site',
      options: options,
      selected: _siteId ?? '',
    );
    if (picked == null || !mounted) return;
    setState(() => _applySite(picked.value.isEmpty ? null : picked.value));
    await _reloadCurrent();
  }

  Future<void> _openFilters() async {
    var projectId = _projectId;
    var projectLabel = _projectLabel;
    var status = _status;
    var preparedBy = _preparedBy;
    var preparedLabel = _preparedByLabel;
    var from = _dateFrom;
    var to = _dateTo;
    List<OptionItem> projects = const [];
    if (_siteId != null) {
      try {
        final res = await context.read<PmsServices>().projects.list({
          'site': _siteId,
          'page': 1,
          'limit': 100,
        });
        projects = res.items
            .map((p) => OptionItem(
                  value: idOf(p) ?? '',
                  label: p['project_name']?.toString() ?? labelOf(p),
                ))
            .where((o) => o.value.isNotEmpty)
            .toList();
      } catch (_) {}
    }
    if (!mounted) return;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return Padding(
              padding: AppTheme.sheetPadding(ctx),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Project'),
                    subtitle: Text(projectLabel),
                    enabled: _siteId != null,
                    onTap: () async {
                      final picked = await showOptionPicker(
                        context,
                        title: 'Project',
                        options: [
                          const OptionItem(value: '', label: 'All projects'),
                          ...projects,
                        ],
                        selected: projectId ?? '',
                      );
                      if (picked == null) return;
                      setLocal(() {
                        projectId = picked.value.isEmpty ? null : picked.value;
                        projectLabel = picked.label;
                      });
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Status'),
                    subtitle: Text(status == null ? 'All statuses' : dprStatusLabel(status)),
                    onTap: () async {
                      final picked = await showOptionPicker(
                        context,
                        title: 'Status',
                        options: const [
                          OptionItem(value: '', label: 'All statuses'),
                          OptionItem(value: 'draft', label: 'Draft'),
                          OptionItem(value: 'pending', label: 'Pending'),
                          OptionItem(value: 'revision_requested', label: 'Sent back'),
                          OptionItem(value: 'approved', label: 'Approved'),
                        ],
                        selected: status ?? '',
                      );
                      if (picked == null) return;
                      setLocal(() => status = picked.value.isEmpty ? null : picked.value);
                    },
                  ),
                  if (Permissions(context.read<AuthProvider>().user).can('user', 'read'))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Prepared by'),
                      subtitle: Text(preparedLabel),
                      onTap: () async {
                        final users = await context.read<SettingsApis>().users.list({
                          'page': 1,
                          'limit': 100,
                          'sortBy': 'name',
                          'sortOrder': 'asc',
                        });
                        if (!context.mounted) return;
                        final picked = await showOptionPicker(
                          context,
                          title: 'Prepared by',
                          options: [
                            const OptionItem(value: '', label: 'Anyone'),
                            ...users.items.map(
                              (u) => OptionItem(
                                value: idOf(u) ?? '',
                                label: personName(u),
                              ),
                            ).where((o) => o.value.isNotEmpty),
                          ],
                          selected: preparedBy ?? '',
                        );
                        if (picked == null) return;
                        setLocal(() {
                          preparedBy = picked.value.isEmpty ? null : picked.value;
                          preparedLabel = picked.label;
                        });
                      },
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('From'),
                    subtitle: Text(from == null ? 'Any date' : formatCalendarDate(from!)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDate: from ?? DateTime.now(),
                      );
                      if (picked == null) return;
                      setLocal(() => from = picked);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('To'),
                    subtitle: Text(to == null ? 'Any date' : formatCalendarDate(to!)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDate: to ?? DateTime.now(),
                      );
                      if (picked == null) return;
                      setLocal(() => to = picked);
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Clear'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (!mounted) return;
    if (applied == false) {
      setState(() {
        _projectId = null;
        _projectLabel = 'All projects';
        _status = null;
        _preparedBy = null;
        _preparedByLabel = 'Anyone';
        _dateFrom = null;
        _dateTo = null;
      });
      await _loadHistory(reset: true);
    } else if (applied == true) {
      setState(() {
        _projectId = projectId;
        _projectLabel = projectLabel;
        _status = status;
        _preparedBy = preparedBy;
        _preparedByLabel = preparedLabel;
        _dateFrom = from;
        _dateTo = to;
      });
      await _loadHistory(reset: true);
    }
  }

  Future<void> _startToday() async {
    if (_siteId == null || !canDpr(context, 'create')) return;
    try {
      final created = await context.read<PmsServices>().dpr.create({'site': _siteId});
      if (!mounted) return;
      final id = idOf(created);
      showPmsSnack(context, 'Draft started');
      if (id != null) await context.push('/pms/dpr/$id/edit');
      if (mounted) await _loadToday();
    } on ApiException catch (e) {
      if (e.statusCode == 409 && mounted) {
        await _openExisting(_siteId!, apiDay(DateTime.now()));
        return;
      }
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _openExisting(String siteId, String date) async {
    try {
      final data = await context.read<PmsServices>().dpr.getForDate(siteId: siteId, date: date);
      final report = data['report'];
      final id = report is Map ? idOf(report) : null;
      if (!mounted || id == null) {
        if (mounted) showPmsSnack(context, 'A report already exists for this site and date', error: true);
        return;
      }
      showPmsSnack(context, 'Opening the existing report');
      final status = report['status']?.toString();
      final path = canDpr(context, 'update') && isDprEditable(status)
          ? '/pms/dpr/$id/edit'
          : '/pms/dpr/$id';
      await context.push(path);
      if (mounted) await _reloadCurrent();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _newReport() async {
    String? siteId = _sites.length == 1 ? _sites.first.value : _siteId;
    var date = DateTime.now();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final siteLabel = _sites.where((s) => s.value == siteId).map((s) => s.label).firstOrNull ??
                'Select a site';
            return Padding(
              padding: AppTheme.sheetPadding(ctx),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('New daily report', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Site'),
                    subtitle: Text(siteLabel),
                    onTap: () async {
                      final picked = await showOptionPicker(
                        context,
                        title: 'Site',
                        options: _sites,
                        selected: siteId,
                      );
                      if (picked == null) return;
                      setLocal(() => siteId = picked.value);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Report date'),
                    subtitle: Text(formatDprDate(date)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDate: date,
                      );
                      if (picked == null) return;
                      setLocal(() => date = picked);
                    },
                  ),
                  const Text('Defaults to today. Pick a past date to backfill.', style: TextStyle(color: AppTheme.muted)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: siteId == null ? null : () => Navigator.pop(ctx, true),
                    child: const Text('Create draft'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (ok != true || siteId == null || !mounted) return;
    try {
      final created = await context.read<PmsServices>().dpr.create({
        'site': siteId,
        'report_date': apiDay(date),
      });
      if (!mounted) return;
      final id = idOf(created);
      showPmsSnack(context, 'Draft started');
      if (id != null) await context.push('/pms/dpr/$id/edit');
      if (mounted) await _loadHistory(reset: true);
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        await _openExisting(siteId!, apiDay(date));
        return;
      }
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _remind() async {
    if (!canDpr(context, 'approve')) return;
    setState(() => _reminding = true);
    try {
      final data = await context.read<PmsServices>().dpr.remindMissing(date: apiDay(_missingDate));
      if (!mounted) return;
      final reason = data['skipped_reason']?.toString();
      if (reason == 'no_dpr_create_permission_configured' ||
          reason == 'no_step1_approver_role_configured') {
        showPmsSnack(
          context,
          'No users can create DPRs — no reminders were sent.',
          error: true,
        );
      } else {
        showPmsSnack(context, 'Reminders sent to ${data['reminded_count'] ?? 0} site(s)');
      }
      await _loadMissing();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _reminding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = context.watch<OrgSession>().organization;
    if (!orgHasModule(org, 'project_management', 'dpr')) {
      return const Scaffold(
        appBar: ModernAppBar(title: 'Daily reports'),
        body: StaggeredEntrance(
          maxIndex: 0,
          child: EntranceItem(
            index: 0,
            child: EmptyState(message: 'Daily Progress Report is not enabled for this organization.'),
          ),
        ),
      );
    }
    if (!canDpr(context, 'read')) {
      return const Scaffold(
        appBar: ModernAppBar(title: 'Daily reports'),
        body: StaggeredEntrance(
          maxIndex: 0,
          child: EntranceItem(
            index: 0,
            child: EmptyState(message: 'You do not have permission to view daily reports.'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: ModernAppBar(
        title: 'Daily reports',
        actions: [
          if (_sites.length != 1)
            PressScale(
              child: IconButton(
                tooltip: 'Site',
                onPressed: _pickSite,
                icon: const Icon(Icons.apartment_rounded),
              ),
            ),
          if (_tab == 0)
            PressScale(
              child: IconButton(
                tooltip: 'Filters',
                onPressed: _openFilters,
                icon: const Icon(Icons.tune_rounded),
              ),
            ),
          if (_tab == 0)
            PressScale(
              child: PopupMenuButton<String>(
              onSelected: (value) {
                final parts = value.split(':');
                setState(() {
                  _sortBy = parts[0];
                  _sortOrder = parts[1];
                });
                _loadHistory(reset: true);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'report_date:desc', child: Text('Newest date')),
                PopupMenuItem(value: 'report_date:asc', child: Text('Oldest date')),
                PopupMenuItem(value: 'status:asc', child: Text('Status')),
                PopupMenuItem(value: 'updatedAt:desc', child: Text('Recently updated')),
              ],
            ),
            ),
        ],
      ),
      floatingActionButton: _tab == 0 && canDpr(context, 'create')
          ? PressScale(
              child: FloatingActionButton.extended(
                onPressed: _newReport,
                icon: const Icon(Icons.add),
                label: const Text('New report'),
              ),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StaggeredEntrance(
            maxIndex: 1,
            slide: 18,
            itemMs: 380,
            scaleFrom: 0.98,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EntranceItem(
                  index: 0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: PressScale(
                      child: SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 0, label: Text('History')),
                          ButtonSegment(value: 1, label: Text('Today')),
                          ButtonSegment(value: 2, label: Text('Missing')),
                        ],
                        selected: {_tab},
                        onSelectionChanged: (next) {
                          setState(() => _tab = next.first);
                          _reloadCurrent();
                        },
                      ),
                    ),
                  ),
                ),
                if (_siteId != null)
                  EntranceItem(
                    index: 1,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_siteLabel, style: const TextStyle(color: AppTheme.muted)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StaggeredEntrance(
              active: !_listBusy,
              replayToken: _tab,
              maxIndex: 6,
              slide: 16,
              itemMs: 380,
              stepMs: 40,
              scaleFrom: 0.97,
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  bool get _listBusy {
    if (_tab == 1) return _todayLoading;
    if (_tab == 2) return _missingLoading;
    return _loading;
  }

  Widget _body() {
    if (_tab == 1) return _todayBody();
    if (_tab == 2) return _missingBody();
    return _historyBody();
  }

  Widget _historyBody() {
    return RefreshIndicator(
      onRefresh: () => _loadHistory(reset: true),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: AppTheme.pagePadding,
                  children: [
                    EntranceItem(
                      index: 0,
                      child: ErrorBanner(message: _error!, onRetry: () => _loadHistory(reset: true)),
                    ),
                  ],
                )
              : _items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 48),
                        EntranceItem(
                          index: 0,
                          child: EmptyState(message: 'No reports match these filters'),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: AppTheme.pagePadding,
                      itemCount: _items.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _items.length) {
                          return EntranceItem(
                            index: 6,
                            child: TextButton(
                              onPressed: () {
                                _page += 1;
                                _loadHistory();
                              },
                              child: const Text('Load more'),
                            ),
                          );
                        }
                        final row = _items[index];
                        final id = idOf(row);
                        final files = dprMediaCount(row);
                        return EntranceItem(
                          index: index,
                          child: PressScale(
                            child: ModernListCard(
                          title: dprSiteLabel(row['site']),
                          subtitle: [
                            formatDprDate(row['report_date']),
                            labelOf(row['project'], fallback: 'No project'),
                            personName(row['prepared_by'] ?? row['created_by']),
                            if (files > 0) '$files files',
                            if (row['is_backdated'] == true) 'Backfilled',
                          ].join(' · '),
                          icon: Icons.calendar_month_rounded,
                          color: AppTheme.colorAt(index),
                          trailing: StatusChip(
                            status: row['status']?.toString(),
                            label: dprStatusLabel(row['status']?.toString()),
                          ),
                          onTap: id == null
                              ? null
                              : () async {
                                  final changed = await context.push('/pms/dpr/$id');
                                  if (changed == true && mounted) _loadHistory(reset: true);
                                },
                        ),
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _todayBody() {
    if (_todayLoading) return const Center(child: CircularProgressIndicator());
    if (_siteId == null || _siteId!.isEmpty) {
      return const EntranceItem(
        index: 0,
        child: EmptyState(message: 'Select a site to view today\'s report.'),
      );
    }
    final status = _today?['status']?.toString() ??
        (_today?['exists'] == false ? 'not_started' : '');
    final report = _today?['report'];
    final reportMap = report is Map ? Map<String, dynamic>.from(report) : null;
    final remarks = reportMap?['approval'] is Map
        ? (reportMap!['approval'] as Map)['remarks']?.toString()
        : null;

    return ListView(
      padding: AppTheme.pagePadding,
      children: [
        EntranceItem(
          index: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_siteLabel, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(formatCalendarDate(DateTime.now()), style: const TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusChip(status: status, label: dprStatusLabel(status)),
              ),
              if (approvalStepLabel(reportMap) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(approvalStepLabel(reportMap)!, style: const TextStyle(color: AppTheme.muted)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        EntranceItem(
          index: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
        if (status == 'not_started') ...[
          const Text('No report has been started for this site today.'),
          if (canDpr(context, 'create')) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _startToday,
              icon: const Icon(Icons.add),
              label: const Text('Start today\'s report'),
            ),
          ],
        ],
        if (status == 'draft' && reportMap != null) ...[
          const Text('You have a draft in progress.'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              final id = idOf(reportMap);
              if (id == null) return;
              final path = canDpr(context, 'update') ? '/pms/dpr/$id/edit' : '/pms/dpr/$id';
              await context.push(path);
              if (mounted) _loadToday();
            },
            child: Text(canDpr(context, 'update') ? 'Continue draft' : 'View report'),
          ),
        ],
        if (status == 'revision_requested' && reportMap != null) ...[
          if (remarks != null && remarks.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(remarks),
                ),
              ),
            ),
          FilledButton(
            onPressed: () async {
              final id = idOf(reportMap);
              if (id == null) return;
              final path = canDpr(context, 'update') ? '/pms/dpr/$id/edit' : '/pms/dpr/$id';
              await context.push(path);
              if (mounted) _loadToday();
            },
            child: Text(canDpr(context, 'update') ? 'Fix and resubmit' : 'View report'),
          ),
        ],
        if ((status == 'pending' || status == 'approved') && reportMap != null)
          OutlinedButton(
            onPressed: () async {
              final id = idOf(reportMap);
              if (id == null) return;
              await context.push('/pms/dpr/$id');
              if (mounted) _loadToday();
            },
            child: const Text('View report'),
          ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _missingBody() {
    final submitted = asMapList(_missing?['submitted'] is List ? _missing!['submitted'] as List : const []);
    final missing = asMapList(_missing?['missing'] is List ? _missing!['missing'] as List : const []);
    return RefreshIndicator(
      onRefresh: _loadMissing,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppTheme.pagePadding,
        children: [
          EntranceItem(
            index: 0,
            child: Row(
              children: [
                _countChip('${submitted.length} submitted', AppTheme.success),
                const SizedBox(width: 8),
                _countChip('${missing.length} missing', AppTheme.danger),
              ],
            ),
          ),
          const SizedBox(height: 8),
          EntranceItem(
            index: 1,
            child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Report date'),
            subtitle: Text(formatCalendarDate(_missingDate)),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                initialDate: _missingDate,
              );
              if (picked == null) return;
              setState(() => _missingDate = picked);
              await _loadMissing();
            },
          ),
          ),
          if (canDpr(context, 'approve'))
            EntranceItem(
              index: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: PressScale(
                  child: FilledButton(
                    onPressed: _reminding ? null : _remind,
                    child: Text(_reminding ? 'Sending…' : 'Remind missing sites'),
                  ),
                ),
              ),
            ),
          if (_missingLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            const SizedBox(height: 16),
            EntranceItem(
              index: 3,
              child: const Text('Submitted', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (submitted.isEmpty)
              const EntranceItem(
                index: 4,
                child: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('None yet')),
              )
            else
              ...submitted.indexed.map((entry) => EntranceItem(
                    index: 4 + entry.$1,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_missingSiteName(entry.$2)),
                      dense: true,
                    ),
                  )),
            const SizedBox(height: 8),
            EntranceItem(
              index: 5,
              child: const Text('Missing', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (missing.isEmpty)
              const EntranceItem(
                index: 6,
                child: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('All sites filed')),
              )
            else
              ...missing.indexed.map((entry) => EntranceItem(
                    index: 6,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_missingSiteName(entry.$2)),
                      trailing: entry.$2['status'] == 'draft'
                          ? const StatusChip(status: 'draft', label: 'Draft only')
                          : null,
                      dense: true,
                    ),
                  )),
          ],
        ],
      ),
    );
  }

  String _missingSiteName(Map<String, dynamic> row) {
    final direct = row['site_name']?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;
    return dprSiteLabel(row['site']);
  }
}

Widget _countChip(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
  );
}
