import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sort_menu.dart';
import '../../../core/theme/modern_widgets.dart';
import '../../../core/widgets/motion.dart';
import '../services/pms_services.dart';
import '../utils/pms_constants.dart';
import '../utils/site_options.dart';
import '../widgets/pickers.dart';
import '../widgets/pms_widgets.dart';

class TasksListScreen extends StatefulWidget {
  const TasksListScreen({super.key, this.initialMine = false});

  final bool initialMine;

  @override
  State<TasksListScreen> createState() => _TasksListScreenState();
}

class _TasksListScreenState extends State<TasksListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _loading = true;
  String? _error;
  bool _mine = false;
  String _search = '';
  int _loadGen = 0;
  String? _status;
  String? _projectId;
  String _projectLabel = '';
  String? _siteId;
  String _siteLabel = '';
  String? _routeSite;
  bool _bootstrapped = false;
  List<OptionItem> _sites = const [];
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _statusCounts = {};
  List<OptionItem> _projects = const [];
  int _page = 1;
  bool _hasMore = false;
  bool _boardView = false;
  Map<String, dynamic>? _board;
  String _sortBy = 'updatedAt';
  String _sortOrder = 'desc';
  int _motion = 0;

  static const _sortChoices = [
    SortChoice(by: 'updatedAt', order: 'desc', label: 'Recently updated'),
    SortChoice(by: 'updatedAt', order: 'asc', label: 'Least recently updated'),
    SortChoice(by: 'title', order: 'asc', label: 'Title A–Z'),
    SortChoice(by: 'title', order: 'desc', label: 'Title Z–A'),
    SortChoice(by: 'due_date', order: 'asc', label: 'Due date'),
    SortChoice(by: 'priority', order: 'desc', label: 'Priority'),
  ];

  @override
  void initState() {
    super.initState();
    _mine = widget.initialMine;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _siteFromRoute();
    if (!_bootstrapped || next == _routeSite) return;
    _routeSite = next;
    _siteId = next;
    _siteLabel = _labelForSite(next);
    _load(reset: true);
  }

  String? _siteFromRoute() {
    final site = GoRouterState.of(context).uri.queryParameters['site'];
    if (site == null || site.isEmpty) return null;
    return site;
  }

  String _labelForSite(String? id) {
    if (id == null || id.isEmpty) return '';
    for (final site in _sites) {
      if (site.value == id) return site.label;
    }
    return _siteLabel;
  }

  Future<void> _bootstrap() async {
    final routeSite = _siteFromRoute();
    _routeSite = routeSite;
    _siteId = routeSite;
    await _loadProjects();
    if (!mounted) return;
    try {
      final sites = await loadSiteOptions(context);
      if (!mounted) return;
      setState(() {
        _sites = sites;
        _siteLabel = _labelForSite(_siteId);
      });
    } catch (_) {}
    _bootstrapped = true;
    await _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    try {
      final res = await context.read<PmsServices>().projects.list({
        'page': 1,
        'limit': 100,
        'sortBy': 'project_name',
        'sortOrder': 'asc',
      });
      if (!mounted) return;
      setState(() {
        _projects = res.items
            .map(
              (p) => OptionItem(
                value: idOf(p) ?? '',
                label: p['project_name']?.toString() ?? labelOf(p),
                raw: p,
              ),
            )
            .where((o) => o.value.isNotEmpty)
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _load({bool reset = false}) async {
    final gen = ++_loadGen;
    final search = _search.trim();
    if (reset) {
      _page = 1;
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final api = context.read<PmsServices>();
      if (_boardView) {
        if (_projectId == null || _projectId!.isEmpty) {
          if (!mounted || gen != _loadGen) return;
          setState(() {
            _board = null;
            _loading = false;
            _error = null;
            if (reset) _motion++;
          });
          return;
        }
        final board = await api.tasks.board(projectId: _projectId!);
        if (!mounted || gen != _loadGen) return;
        setState(() {
          _board = board;
          _loading = false;
          if (reset) _motion++;
        });
        return;
      }
      final listStatus = _mine
          ? _status
          : PmsConstants.toListApiStatus(_status);
      final params = <String, dynamic>{
        'page': _page,
        'limit': 20,
        if (search.isNotEmpty) 'search': search,
        'status': listStatus,
        'project': _projectId,
        if (_siteId != null) 'site': _siteId,
        'sortBy': _sortBy,
        'sortOrder': _sortOrder,
      };

      final results = await Future.wait([
        _mine ? api.tasks.myTasks(params) : api.tasks.list(params),
        api.tasks
            .statusCounts({
              'project': _projectId,
              if (_siteId != null) 'site': _siteId,
            })
            .catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted || gen != _loadGen) return;
      final list = results[0] as dynamic;
      final counts = results[1] as Map<String, dynamic>;
      final totalPages = list.pagination?['totalPages'];
      setState(() {
        _items = reset
            ? list.items as List<Map<String, dynamic>>
            : [..._items, ...list.items as List<Map<String, dynamic>>];
        _statusCounts = counts['counts'] is Map
            ? Map<String, dynamic>.from(counts['counts'] as Map)
            : counts;
        _hasMore = totalPages is num && _page < totalPages;
        _loading = false;
        if (reset) _motion++;
      });
    } on ApiException catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    final id = idOf(task);
    if (id == null) return;
    final title = task['title']?.toString().trim();
    final ok = await confirmAction(
      context,
      title: 'Delete task?',
      message:
          '${title == null || title.isEmpty ? 'This task' : title} cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<PmsServices>().tasks.delete(id);
      if (!mounted) return;
      showPmsSnack(context, 'Task deleted');
      _load(reset: true);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search = value.trim();
      _load(reset: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final queryMine =
        GoRouterState.of(context).uri.queryParameters['mine'] == '1';
    if (queryMine && !_mine) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_mine) {
          setState(() => _mine = true);
          _load(reset: true);
        }
      });
    }

    return Scaffold(
      extendBody: true,
      appBar: ModernAppBar(
        title: 'Tasks',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PressScale(
              child: SegmentedButton<bool>(
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white.withValues(alpha: 0.25);
                    }
                    return Colors.white.withValues(alpha: 0.12);
                  }),
                  foregroundColor: const WidgetStatePropertyAll(Colors.white),
                ),
                segments: const [
                  ButtonSegment(value: false, label: Text('All')),
                  ButtonSegment(value: true, label: Text('Mine')),
                ],
                selected: {_mine},
                onSelectionChanged: (s) {
                  setState(() => _mine = s.first);
                  _load(reset: true);
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: PressScale(
        child: FloatingActionButton(
          onPressed: () async {
            final created = await context.push<bool>(
              '/pms/tasks/new',
              extra: _projectId,
            );
            if (created == true && mounted) _load(reset: true);
          },
          child: const Icon(Icons.add),
        ),
      ),
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
                    padding: AppTheme.searchPadding,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Search title, project or site…',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: _onSearch,
                    ),
                  ),
                ),
                EntranceItem(
                  index: 1,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: AppTheme.chipRowPadding,
                    child: Row(
                      children: [
                        PressScale(
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('List')),
                              ButtonSegment(value: true, label: Text('Board')),
                            ],
                            selected: {_boardView},
                            onSelectionChanged: (selected) {
                              setState(() => _boardView = selected.first);
                              _load(reset: true);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        PressScale(
                          child: SortMenuButton(
                            choices: _sortChoices,
                            sortBy: _sortBy,
                            sortOrder: _sortOrder,
                            onSelected: (by, order) {
                              setState(() {
                                _sortBy = by;
                                _sortOrder = order;
                              });
                              _load(reset: true);
                            },
                          ),
                        ),
                        PressScale(
                          child: FilterChip(
                            label: Text(_siteId == null ? 'Site' : _siteLabel),
                            selected: _siteId != null,
                            onSelected: (_) async {
                              final picked = await showOptionPicker(
                                context,
                                title: 'Site',
                                options: [
                                  const OptionItem(
                                    value: '',
                                    label: 'All sites',
                                  ),
                                  ..._sites,
                                ],
                                selected: _siteId ?? '',
                              );
                              if (picked == null || !mounted) return;
                              setState(() {
                                _siteId = picked.value.isEmpty
                                    ? null
                                    : picked.value;
                                _siteLabel = picked.value.isEmpty
                                    ? ''
                                    : picked.label;
                              });
                              await _load(reset: true);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        PressScale(
                          child: FilterChip(
                            label: Text(
                              _projectId == null ? 'Project' : _projectLabel,
                            ),
                            selected: _projectId != null,
                            onSelected: (_) async {
                              final picked = await showOptionPicker(
                                context,
                                title: 'Filter by project',
                                options: [
                                  const OptionItem(
                                    value: '',
                                    label: 'All projects',
                                  ),
                                  ..._projects,
                                ],
                                selected: _projectId ?? '',
                              );
                              if (picked == null) return;
                              setState(() {
                                _projectId = picked.value.isEmpty
                                    ? null
                                    : picked.value;
                                _projectLabel = picked.label;
                              });
                              await _load(reset: true);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        PressScale(
                          child: FilterChip(
                            selected: _status == null,
                            label: Text('All (${_sumCounts(_statusCounts)})'),
                            onSelected: (_) {
                              setState(() => _status = null);
                              _load(reset: true);
                            },
                          ),
                        ),
                        for (final col
                            in PmsConstants.taskBoardFilterStatuses) ...[
                          const SizedBox(width: 8),
                          PressScale(
                            child: FilterChip(
                              selected: _status == col.$1,
                              label: Text(
                                '${col.$2} (${_statusCounts[col.$1] ?? 0})',
                              ),
                              onSelected: (_) {
                                setState(() => _status = col.$1);
                                _load(reset: true);
                              },
                            ),
                          ),
                        ],
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
                child: ErrorBanner(
                  message: _error!,
                  onRetry: () => _load(reset: true),
                ),
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
                onRefresh: () => _load(reset: true),
                child:
                    _loading && (_boardView ? _board == null : _items.isEmpty)
                    ? const CenteredScrollLoader()
                    : _boardView
                    ? _projectId == null
                          ? const EntranceItem(
                              index: 0,
                              child: EmptyListBody(
                                message:
                                    'Select a project to open the task board',
                              ),
                            )
                          : EntranceItem(
                              index: 0,
                              child: _StandaloneTaskBoard(
                                board: _board,
                                onOpen: (id) => context.push('/pms/tasks/$id'),
                                onChangeStatus: _changeBoardStatus,
                              ),
                            )
                    : _items.isEmpty
                    ? EntranceItem(
                        index: 0,
                        child: EmptyListBody(
                          message: _search.trim().isEmpty && _siteId == null
                              ? 'No tasks found'
                              : 'No tasks match this search',
                        ),
                      )
                    : ListView.builder(
                        padding: AppTheme.listPadding,
                        itemCount: _items.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= _items.length) {
                            return EntranceItem(
                              index: 6,
                              child: TextButton(
                                onPressed: () {
                                  _page += 1;
                                  _load();
                                },
                                child: const Text('Load more'),
                              ),
                            );
                          }
                          final t = _items[i];
                          final id = idOf(t);
                          return EntranceItem(
                            index: i,
                            child: PressScale(
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  color: Colors.white,
                                  boxShadow: AppTheme.cardShadow,
                                ),
                                child: ListTile(
                                  title: Text(
                                    t['title']?.toString() ?? 'Task',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    [
                                      labelOf(t['project']),
                                      '${t['current_progress'] ?? 0}%',
                                      PmsConstants.labelFor(
                                        PmsConstants.priorities,
                                        t['priority']?.toString(),
                                      ),
                                    ].join(' · '),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      StatusChip(
                                        status: t['status']?.toString(),
                                      ),
                                      ListDeleteMenu(
                                        onDelete: id == null
                                            ? null
                                            : () => _deleteTask(t),
                                      ),
                                    ],
                                  ),
                                  onTap: id == null
                                      ? null
                                      : () => context.push('/pms/tasks/$id'),
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

  Future<void> _changeBoardStatus(
    Map<String, dynamic> task,
    String status,
  ) async {
    final id = idOf(task);
    if (id == null) return;
    try {
      await context.read<PmsServices>().tasks.update(id, {'status': status});
      if (!mounted) return;
      showPmsSnack(context, 'Status updated');
      await _load(reset: true);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  int _sumCounts(Map<String, dynamic> counts) {
    var sum = 0;
    for (final v in counts.values) {
      if (v is num) sum += v.toInt();
    }
    return sum;
  }
}

class _StandaloneTaskBoard extends StatelessWidget {
  const _StandaloneTaskBoard({
    required this.board,
    required this.onOpen,
    required this.onChangeStatus,
  });

  final Map<String, dynamic>? board;
  final ValueChanged<String> onOpen;
  final void Function(Map<String, dynamic> task, String status) onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final groups = board?['groups'] is Map
        ? Map<String, dynamic>.from(board!['groups'] as Map)
        : <String, dynamic>{};
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                children: [
                  for (final col in PmsConstants.boardColumns)
                    SizedBox(
                      width: 260,
                      child: Card(
                        margin: const EdgeInsets.only(right: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                col.$2,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final items = groups[col.$1] is List
                                      ? (groups[col.$1] as List)
                                            .whereType<Map>()
                                            .map(
                                              (e) =>
                                                  Map<String, dynamic>.from(e),
                                            )
                                            .toList()
                                      : <Map<String, dynamic>>[];
                                  if (items.isEmpty) {
                                    return const Center(
                                      child: Text(
                                        'Empty',
                                        style: TextStyle(color: AppTheme.muted),
                                      ),
                                    );
                                  }
                                  return ListView.builder(
                                    padding: const EdgeInsets.all(8),
                                    itemCount: items.length,
                                    itemBuilder: (context, i) {
                                      final task = items[i];
                                      final id = idOf(task);
                                      return Card(
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: ListTile(
                                          dense: true,
                                          title: Text(
                                            task['title']?.toString() ?? 'Task',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          subtitle: Text(
                                            '${task['current_progress'] ?? 0}%',
                                          ),
                                          onTap: id == null
                                              ? null
                                              : () => onOpen(id),
                                          onLongPress: () async {
                                            final picked =
                                                await showModalBottomSheet<
                                                  String
                                                >(
                                                  context: context,
                                                  builder: (ctx) => SafeArea(
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        for (final status
                                                            in PmsConstants
                                                                .taskSettableStatuses)
                                                          ListTile(
                                                            title: Text(
                                                              status.$2,
                                                            ),
                                                            onTap: () =>
                                                                Navigator.pop(
                                                                  ctx,
                                                                  status.$1,
                                                                ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                            if (picked != null)
                                              onChangeStatus(task, picked);
                                          },
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
