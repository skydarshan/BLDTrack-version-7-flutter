import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/modern_widgets.dart';
import '../services/pms_services.dart';
import '../utils/pms_constants.dart';
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
  String? _status;
  String? _projectId;
  String _projectLabel = '';
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _statusCounts = {};
  List<OptionItem> _projects = const [];
  int _page = 1;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _mine = widget.initialMine;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadProjects();
      await _load(reset: true);
    });
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
    if (reset) {
      _page = 1;
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final api = context.read<PmsServices>();
      final listStatus = _mine ? _status : PmsConstants.toListApiStatus(_status);
      final params = <String, dynamic>{
        'page': _page,
        'limit': 20,
        'search': _search,
        'status': listStatus,
        'project': _projectId,
        'sortBy': 'updatedAt',
        'sortOrder': 'desc',
      };

      final results = await Future.wait([
        _mine ? api.tasks.myTasks(params) : api.tasks.list(params),
        api.tasks.statusCounts({
          'project': _projectId,
          if (_mine) 'mine': true,
        }).catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      final list = results[0] as dynamic;
      final counts = results[1] as Map<String, dynamic>;
      final totalPages = list.pagination?['totalPages'];
      setState(() {
        _items = reset ? list.items as List<Map<String, dynamic>> : [
          ..._items,
          ...list.items as List<Map<String, dynamic>>,
        ];
        _statusCounts = counts['counts'] is Map
            ? Map<String, dynamic>.from(counts['counts'] as Map)
            : counts;
        _hasMore = totalPages is num && _page < totalPages;
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

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search = value.trim();
      _load(reset: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final queryMine = GoRouterState.of(context).uri.queryParameters['mine'] == '1';
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
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await context.push<bool>(
            '/pms/tasks/new',
            extra: _projectId,
          );
          if (created == true && mounted) _load(reset: true);
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search tasks…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearch,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: Text(_projectId == null ? 'Project' : _projectLabel),
                  selected: _projectId != null,
                  onSelected: (_) async {
                    final picked = await showOptionPicker(
                      context,
                      title: 'Filter by project',
                      options: [
                        const OptionItem(value: '', label: 'All projects'),
                        ..._projects,
                      ],
                      selected: _projectId ?? '',
                    );
                    if (picked == null) return;
                    setState(() {
                      _projectId = picked.value.isEmpty ? null : picked.value;
                      _projectLabel = picked.label;
                    });
                    await _load(reset: true);
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  selected: _status == null,
                  label: Text('All (${_sumCounts(_statusCounts)})'),
                  onSelected: (_) {
                    setState(() => _status = null);
                    _load(reset: true);
                  },
                ),
                for (final col in PmsConstants.taskBoardFilterStatuses) ...[
                  const SizedBox(width: 8),
                  FilterChip(
                    selected: _status == col.$1,
                    label: Text('${col.$2} (${_statusCounts[col.$1] ?? 0})'),
                    onSelected: (_) {
                      setState(() => _status = col.$1);
                      _load(reset: true);
                    },
                  ),
                ],
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ErrorBanner(message: _error!, onRetry: () => _load(reset: true)),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: _loading && _items.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : _items.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 80),
                            EmptyState(message: 'No tasks found'),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          itemCount: _items.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i >= _items.length) {
                              return TextButton(
                                onPressed: () {
                                  _page += 1;
                                  _load();
                                },
                                child: const Text('Load more'),
                              );
                            }
                            final t = _items[i];
                            final id = idOf(t);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
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
                                trailing: StatusChip(status: t['status']?.toString()),
                                onTap: id == null
                                    ? null
                                    : () => context.push('/pms/tasks/$id'),
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

  int _sumCounts(Map<String, dynamic> counts) {
    var sum = 0;
    for (final v in counts.values) {
      if (v is num) sum += v.toInt();
    }
    return sum;
  }
}
