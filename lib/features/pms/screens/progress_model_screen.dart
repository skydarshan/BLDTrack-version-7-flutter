import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../services/pms_services.dart';
import '../utils/progress_model_view.dart';
import '../utils/structure_errors.dart';
import '../widgets/pms_widgets.dart';

/// Read-only Progress Model. Mobile uses the stacked-floors view from the guide.
class ProgressModelView extends StatefulWidget {
  const ProgressModelView({
    super.key,
    required this.projectId,
    this.tabController,
    this.tabIndex,
  });

  final String projectId;
  final TabController? tabController;
  final int? tabIndex;

  @override
  State<ProgressModelView> createState() => _ProgressModelViewState();
}

class _ProgressModelViewState extends State<ProgressModelView>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  bool _loading = true;
  bool _refreshing = false;
  bool _loadedOnce = false;
  bool _noAccess = false;
  String? _error;
  bool _hasStructure = false;
  List<Map<String, dynamic>> _legend = const [];
  Map<String, dynamic> _summary = const {};
  Map<String, dynamic> _coverage = const {};
  Map<String, Map<String, dynamic>> _nodes = const {};
  Map<String, dynamic>? _model;
  int _request = 0;
  bool _wasSelected = false;

  @override
  bool get wantKeepAlive => true;

  bool get _isSelected {
    final controller = widget.tabController;
    final index = widget.tabIndex;
    if (controller == null || index == null) return true;
    return controller.index == index;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.tabController?.addListener(_handleTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isSelected) return;
      _wasSelected = true;
      _load(includeModel: true);
    });
  }

  @override
  void didUpdateWidget(ProgressModelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabController != widget.tabController) {
      oldWidget.tabController?.removeListener(_handleTab);
      widget.tabController?.addListener(_handleTab);
    }
    if (oldWidget.projectId != widget.projectId) {
      _model = null;
      _loadedOnce = false;
      _load(includeModel: true);
    }
  }

  @override
  void dispose() {
    widget.tabController?.removeListener(_handleTab);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _loadedOnce && _isSelected) {
      _load(includeModel: false);
    }
  }

  void _handleTab() {
    final selected = _isSelected;
    if (!selected) {
      _wasSelected = false;
      return;
    }
    if (_wasSelected) return;
    _wasSelected = true;
    if (!_loadedOnce) {
      _load(includeModel: true);
      return;
    }
    _load(includeModel: false);
  }

  Future<void> _load({required bool includeModel}) async {
    final request = ++_request;
    final first = !_loadedOnce;
    if (mounted) {
      setState(() {
        if (first) {
          _loading = true;
          _error = null;
          _noAccess = false;
        } else {
          _refreshing = true;
        }
      });
    }
    try {
      final data = await context.read<PmsServices>().structure.progress(
            widget.projectId,
            includeModel: includeModel,
          );
      if (!mounted || request != _request) return;
      final hasStructure = data['has_structure'] == true;
      final nodes = indexProgressNodes(data['nodes']);
      final model = data['model'] is Map
          ? Map<String, dynamic>.from(data['model'] as Map)
          : (includeModel ? null : _model);
      final needModel = hasStructure &&
          (model == null || !modelCoversProgressNodes(model, nodes.keys));
      if (!includeModel && needModel) {
        await _load(includeModel: true);
        return;
      }
      setState(() {
        _hasStructure = hasStructure;
        _legend = legendItems(data['legend']);
        _summary = data['summary'] is Map
            ? Map<String, dynamic>.from(data['summary'] as Map)
            : const {};
        _coverage = data['coverage'] is Map
            ? Map<String, dynamic>.from(data['coverage'] as Map)
            : const {};
        _nodes = nodes;
        if (model != null) _model = model;
        _loading = false;
        _refreshing = false;
        _loadedOnce = true;
        _noAccess = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted || request != _request) return;
      final error = readStructureError(e);
      if (error.isNoAccess) {
        setState(() {
          _noAccess = true;
          _error = error.message;
          _loading = false;
          _refreshing = false;
          _loadedOnce = true;
        });
        return;
      }
      if (error.isNotFound) {
        setState(() {
          _loading = false;
          _refreshing = false;
          _loadedOnce = false;
          _error = error.notFoundMessage;
        });
        return;
      }
      setState(() {
        _loading = false;
        _refreshing = false;
        if (!_loadedOnce) _error = error.message;
      });
      if (_loadedOnce && mounted) {
        showPmsSnack(context, error.message, error: true);
      }
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        if (!_loadedOnce) _error = e.toString();
      });
    }
  }

  Future<void> _openNode(String nodeId) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _NodeTaskSheet(
        projectId: widget.projectId,
        nodeId: nodeId,
        legend: _legend,
        onOpenTask: (id) => context.push('/pms/tasks/$id'),
        onTasksChanged: () {
          if (mounted) _load(includeModel: false);
        },
      ),
    );
    if (mounted) await _load(includeModel: false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_noAccess) {
      return NoAccessNotice(
        message: _error ?? 'You are not assigned to this project\'s site',
        onRetry: () => _load(includeModel: _model == null),
      );
    }
    if (_error != null && !_loadedOnce) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorBanner(message: _error!, onRetry: () => _load(includeModel: true)),
      );
    }
    if (!_hasStructure) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No structure has been set up for this project yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    final stacked = stackedModelFromGeometry(_model);
    return RefreshIndicator(
      onRefresh: () => _load(includeModel: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(),
            ),
          _SummaryCard(summary: _summary, coverage: _coverage, legend: _legend),
          const SizedBox(height: 12),
          _LegendRow(legend: _legend),
          const SizedBox(height: 16),
          for (final building in stacked.buildings) ...[
            _StructureTree(
              building: building,
              nodes: _nodes,
              legend: _legend,
              onOpen: _openNode,
            ),
            const SizedBox(height: 8),
          ],
          for (final area in stacked.externalAreas)
            _StructureRow(
              cell: area,
              depth: 0,
              node: _nodes[area.nodeId],
              legend: _legend,
              onTap: () => _openNode(area.nodeId),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.summary,
    required this.coverage,
    required this.legend,
  });

  final Map<String, dynamic> summary;
  final Map<String, dynamic> coverage;
  final List<Map<String, dynamic>> legend;

  @override
  Widget build(BuildContext context) {
    final status = legendLabel(legend, summary['status']?.toString());
    final covered = coverage['covered_tasks'];
    final total = coverage['total_tasks'];
    final unassigned = coverage['unassigned_tasks'];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              status.isEmpty ? 'Progress' : status,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text('Progress ${formatProgressPercent(summary['progress'])}'),
            Text('Tasks ${summary['task_count'] ?? 0}'),
            const SizedBox(height: 6),
            Text('Coverage $covered of $total'),
            Text('Unassigned tasks $unassigned'),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.legend});

  final List<Map<String, dynamic>> legend;

  @override
  Widget build(BuildContext context) {
    if (legend.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final item in legend)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _paintColor(item['color']?.toString(), item['key']?.toString(), legend),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: const Color(0xFFD1D5DB)),
                ),
              ),
              const SizedBox(width: 4),
              Text(item['label']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
            ],
          ),
      ],
    );
  }
}

class _StructureTree extends StatelessWidget {
  const _StructureTree({
    required this.building,
    required this.nodes,
    required this.legend,
    required this.onOpen,
  });

  final StackedBuilding building;
  final Map<String, Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> legend;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StructureRow(
          cell: building.node,
          depth: 0,
          node: nodes[building.node.nodeId],
          legend: legend,
          onTap: () => onOpen(building.node.nodeId),
        ),
        for (final floor in building.floors) ...[
          _StructureRow(
            cell: floor.node,
            depth: 1,
            node: nodes[floor.node.nodeId],
            legend: legend,
            onTap: () => onOpen(floor.node.nodeId),
          ),
          for (final child in floor.children)
            _StructureRow(
              cell: child,
              depth: 2,
              node: nodes[child.nodeId],
              legend: legend,
              onTap: () => onOpen(child.nodeId),
            ),
        ],
        for (final core in building.cores)
          _StructureRow(
            cell: core,
            depth: 1,
            node: nodes[core.nodeId],
            legend: legend,
            onTap: () => onOpen(core.nodeId),
          ),
      ],
    );
  }
}

class _StructureRow extends StatelessWidget {
  const _StructureRow({
    required this.cell,
    required this.depth,
    required this.node,
    required this.legend,
    required this.onTap,
  });

  final StackedCell cell;
  final int depth;
  final Map<String, dynamic>? node;
  final List<Map<String, dynamic>> legend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final raw = node?['color']?.toString() ?? legendColor(legend, 'no_tasks');
    var color = _paintColor(raw, node?['status']?.toString(), legend);
    final faded = cell.type == 'core' || node?['status']?.toString() == 'no_tasks';
    if (faded) color = color.withValues(alpha: 0.55);
    final status = legendLabel(legend, node?['status']?.toString());
    final progress = node == null ? '' : formatProgressPercent(node?['progress']);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: depth * 16.0, top: 6, bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 36,
              margin: const EdgeInsets.only(right: 10, top: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cell.name,
                    style: TextStyle(
                      fontWeight: depth == 0 ? FontWeight.w700 : FontWeight.w600,
                      fontSize: depth == 0 ? 16 : 14,
                    ),
                  ),
                  Text(
                    [
                      structureNodeDetail(cell),
                      if (status.isNotEmpty) status,
                      if (progress.isNotEmpty) progress,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _paintColor(String? raw, String? status, List<Map<String, dynamic>> legend) {
  final parsed = colorValueFromHex(raw);
  if (parsed != null) return Color(parsed);
  final fallback = colorValueFromHex(legendColor(legend, status ?? 'no_tasks'));
  if (fallback != null) return Color(fallback);
  return const Color(0xFFE5E7EB);
}

class _NodeTaskSheet extends StatefulWidget {
  const _NodeTaskSheet({
    required this.projectId,
    required this.nodeId,
    required this.legend,
    required this.onOpenTask,
    required this.onTasksChanged,
  });

  final String projectId;
  final String nodeId;
  final List<Map<String, dynamic>> legend;
  final Future<void> Function(String taskId) onOpenTask;
  final VoidCallback onTasksChanged;

  @override
  State<_NodeTaskSheet> createState() => _NodeTaskSheetState();
}

class _NodeTaskSheetState extends State<_NodeTaskSheet> {
  bool _loading = true;
  bool _noAccess = false;
  String? _error;
  Map<String, dynamic>? _node;
  List<Map<String, dynamic>> _tasks = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _noAccess = false;
    });
    try {
      final data = await context.read<PmsServices>().structure.nodeTasks(
            widget.projectId,
            widget.nodeId,
          );
      if (!mounted) return;
      final tasks = data['tasks'];
      setState(() {
        _node = data['node'] is Map ? Map<String, dynamic>.from(data['node'] as Map) : null;
        _tasks = tasks is List
            ? tasks.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : const [];
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      final error = readStructureError(e);
      if (error.isNoAccess) {
        setState(() {
          _noAccess = true;
          _error = error.message;
          _loading = false;
        });
        return;
      }
      if (error.isNotFound) widget.onTasksChanged();
      setState(() {
        _error = error.isNotFound ? error.notFoundMessage : error.message;
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

  Future<void> _openTask(String id) async {
    await widget.onOpenTask(id);
    if (!mounted) return;
    widget.onTasksChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final node = _node;
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return SizedBox(
      height: height,
      child: Padding(
          padding: AppTheme.sheetPadding(context),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _noAccess
                  ? NoAccessNotice(message: _error ?? 'You are not assigned to this project\'s site')
                  : _error != null
                      ? ErrorBanner(message: _error!, onRetry: _load)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              node?['label']?.toString() ?? node?['name']?.toString() ?? 'Node',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              [
                                if ((node?['type']?.toString() ?? '').isNotEmpty)
                                  structureTypeLabel(node!['type'].toString()),
                                if (asNum(node?['level_number']) != null)
                                  'level ${formatLevel(asNum(node?['level_number'])!)}',
                                if (asNum(node?['from_level']) != null && asNum(node?['to_level']) != null)
                                  'levels ${formatLevel(asNum(node?['from_level'])!)} → ${formatLevel(asNum(node?['to_level'])!)}',
                                legendLabel(widget.legend, node?['status']?.toString()),
                                formatProgressPercent(node?['progress']),
                                '${node?['task_count'] ?? _tasks.length} tasks',
                                if (node?['overdue'] == true)
                                  '${node?['overdue_count'] ?? 0} ${legendLabel(widget.legend, 'overdue')}',
                              ].where((part) => part.trim().isNotEmpty).join(' · '),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _tasks.isEmpty
                                  ? const Center(child: Text('No linked tasks'))
                                  : ListView.separated(
                                      itemCount: _tasks.length,
                                      separatorBuilder: (_, _) => const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final task = _tasks[index];
                                        final id = idOf(task);
                                        final path = taskPathLabel(task['path']);
                                        final members = assignedMembersOf(task);
                                        return ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          onTap: id == null ? null : () => _openTask(id),
                                          title: Text(task['title']?.toString() ?? 'Task'),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (path.isNotEmpty)
                                                Text(path, style: const TextStyle(fontSize: 12)),
                                              Text(
                                                [
                                                  legendLabel(
                                                    widget.legend,
                                                    (task['block_status'] ?? task['status'])?.toString(),
                                                  ),
                                                  formatProgressPercent(task['progress']),
                                                  if (task['overdue'] == true)
                                                    legendLabel(widget.legend, 'overdue'),
                                                  if (taskInheritsStructureLink(task)) 'Inherited',
                                                  ...coreFloorLevelNotes(task),
                                                ].where((part) => part.trim().isNotEmpty).join(' · '),
                                              ),
                                              for (final member in members)
                                                Text(
                                                  [
                                                    member['name']?.toString() ?? '',
                                                    member['email']?.toString() ?? '',
                                                  ].where((part) => part.isNotEmpty).join(' · '),
                                                  style: const TextStyle(fontSize: 12),
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
        ),
    );
  }
}
