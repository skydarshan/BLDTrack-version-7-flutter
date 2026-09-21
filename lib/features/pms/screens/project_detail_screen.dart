import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../services/pms_services.dart';
import '../utils/pms_constants.dart';
import '../widgets/media_widgets.dart';
import '../widgets/pms_widgets.dart';

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _overview;
  Map<String, dynamic>? _project;
  List<Map<String, dynamic>> _tree = [];
  Map<String, dynamic>? _timeline;
  Map<String, dynamic>? _board;
  bool _mediaBusy = false;
  List<PendingFile> _pendingMedia = [];
  Map<String, dynamic>? _importPreview;
  bool _importing = false;
  final _jsonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      _onTab(_tabs.index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCore());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCore() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<PmsServices>();
      final results = await Future.wait([
        api.dashboard.pmsProject(widget.projectId),
        api.projects.getById(widget.projectId),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = results[0];
        _project = results[1];
        _loading = false;
      });
      await _onTab(_tabs.index);
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

  Future<void> _onTab(int index) async {
    final api = context.read<PmsServices>();
    try {
      if (index == 2) {
        final tree = await api.projects.getTaskTree(widget.projectId);
        if (mounted) setState(() => _tree = tree);
      } else if (index == 3) {
        final timeline = await api.projects.getTaskTimeline(widget.projectId);
        if (mounted) setState(() => _timeline = timeline);
      } else if (index == 4) {
        final board = await api.tasks.board(projectId: widget.projectId);
        if (mounted) setState(() => _board = board);
      }
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _uploadMedia() async {
    if (_pendingMedia.isEmpty) {
      showPmsSnack(context, 'Select files to upload', error: true);
      return;
    }
    setState(() => _mediaBusy = true);
    try {
      await context.read<PmsServices>().projects.update(
            widget.projectId,
            {'reason': 'Media upload'},
            files: _pendingMedia.map((f) => f.toEntry()).toList(),
          );
      if (!mounted) return;
      showPmsSnack(context, 'Media uploaded');
      setState(() => _pendingMedia = []);
      final project =
          await context.read<PmsServices>().projects.getById(widget.projectId);
      if (mounted) setState(() => _project = project);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  Future<void> _removeMedia(String type, String url) async {
    setState(() => _mediaBusy = true);
    try {
      await context.read<PmsServices>().projects.removeMedia(
            widget.projectId,
            {'type': type, 'url': url},
          );
      if (!mounted) return;
      showPmsSnack(context, 'Media removed');
      final project =
          await context.read<PmsServices>().projects.getById(widget.projectId);
      if (mounted) setState(() => _project = project);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  Future<File> _writeTempBytes(List<int> bytes, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _exportTasks() async {
    try {
      final bytes =
          await context.read<PmsServices>().projects.exportTasks(widget.projectId);
      final file = await _writeTempBytes(bytes, 'project_tasks_export.xlsx');
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)], text: 'Project tasks export');
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _downloadImportTemplate() async {
    try {
      final bytes = await context
          .read<PmsServices>()
          .projects
          .downloadImportTemplate(widget.projectId);
      final file = await _writeTempBytes(bytes, 'task_import_template.xlsx');
      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)], text: 'Task import template');
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _pickImportFile({required bool dryRun}) async {
    final files = await pickPmsFiles(allowMultiple: false);
    if (files.isEmpty || !mounted) return;
    setState(() => _importing = true);
    try {
      final entry = MultipartFileEntry(
        bytes: files.first.bytes,
        filename: files.first.filename,
        contentType: files.first.contentType,
      );
      final preview = await context.read<PmsServices>().projects.importFile(
            widget.projectId,
            entry,
            dryRun: dryRun,
          );
      if (!mounted) return;
      setState(() => _importPreview = preview);
      showPmsSnack(
        context,
        dryRun ? 'Preview ready — review then commit' : 'Import applied',
      );
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _jsonImportPreview() async {
    try {
      final decoded = jsonDecode(_jsonCtrl.text);
      final payload = decoded is Map<String, dynamic>
          ? decoded
          : decoded is List
              ? {'rows': decoded}
              : <String, dynamic>{};
      setState(() => _importing = true);
      final preview = await context.read<PmsServices>().projects.importJson(
            widget.projectId,
            payload,
            dryRun: true,
          );
      if (!mounted) return;
      setState(() => _importPreview = preview);
      showPmsSnack(context, 'JSON preview ready');
    } on FormatException {
      showPmsSnack(context, 'Invalid JSON', error: true);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _commitImport() async {
    final tree = _importPreview?['tree'];
    if (tree == null) {
      showPmsSnack(context, 'No preview tree to commit', error: true);
      return;
    }
    setState(() => _importing = true);
    try {
      await context.read<PmsServices>().projects.commitImport(
            widget.projectId,
            {'tree': tree, 'dryRun': false},
          );
      if (!mounted) return;
      showPmsSnack(context, 'Tasks imported');
      setState(() => _importPreview = null);
      _tabs.index = 2;
      await _onTab(2);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _saveAsTemplate() async {
    final nameCtrl = TextEditingController(
      text: '${_project?['project_name'] ?? 'Project'} template',
    );
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save as template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Template name *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.length < 2) {
      showPmsSnack(context, 'Template name is required', error: true);
      return;
    }
    try {
      await context.read<PmsServices>().projects.saveAsTemplate(
        widget.projectId,
        {
          'name': name,
          if (descCtrl.text.trim().isNotEmpty) 'description': descCtrl.text.trim(),
          'scope': 'organization',
        },
      );
      if (!mounted) return;
      showPmsSnack(context, 'Template created from project');
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _showAudit() async {
    try {
      final rows = await context
          .read<PmsServices>()
          .projects
          .getAudit(widget.projectId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Audit log',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: rows.isEmpty
                      ? const EmptyState(message: 'No audit entries')
                      : ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final row = rows[i];
                            return ListTile(
                              title: Text(
                                row['action']?.toString() ??
                                    row['event']?.toString() ??
                                    'Change',
                              ),
                              subtitle: Text(
                                [
                                  labelOf(row['actor'] ?? row['user']),
                                  formatDateTime(
                                    row['createdAt'] ?? row['timestamp'],
                                  ),
                                  if (row['reason'] != null) row['reason'].toString(),
                                ].where((s) => s.isNotEmpty && s != '—').join(' · '),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _changeBoardTaskStatus(
    Map<String, dynamic> task,
    String status,
  ) async {
    final id = idOf(task);
    if (id == null) return;
    try {
      await context.read<PmsServices>().tasks.update(id, {'status': status});
      if (!mounted) return;
      showPmsSnack(context, 'Status updated');
      await _onTab(4);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = _project ??
        ((_overview?['project'] is Map)
            ? Map<String, dynamic>.from(_overview!['project'] as Map)
            : null);
    final title = project?['project_name']?.toString() ?? 'Project';
    final topTasks = (_overview?['top_tasks'] is List)
        ? (_overview!['top_tasks'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : ((_overview?['tasks'] is List)
            ? (_overview!['tasks'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : <Map<String, dynamic>>[]);

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () async {
              final updated =
                  await context.push<bool>('/pms/projects/${widget.projectId}/edit');
              if (updated == true && mounted) _loadCore();
            },
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Save as template',
            onPressed: _saveAsTemplate,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Audit',
            onPressed: _showAudit,
            icon: const Icon(Icons.history),
          ),
        ],
        bottom: AppBarTabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Media'),
            Tab(text: 'Hierarchy'),
            Tab(text: 'Timeline'),
            Tab(text: 'Board'),
            Tab(text: 'Import'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: ErrorBanner(message: _error!, onRetry: _loadCore),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _OverviewTab(
                      project: project,
                      overview: _overview,
                      topTasks: topTasks,
                      onOpenTask: (id) => context.push('/pms/tasks/$id'),
                    ),
                    _MediaTab(
                      project: project ?? const {},
                      pending: _pendingMedia,
                      busy: _mediaBusy,
                      onPendingChanged: (v) => setState(() => _pendingMedia = v),
                      onUpload: _uploadMedia,
                      onRemove: _removeMedia,
                    ),
                    _HierarchyTab(
                      nodes: _tree,
                      onOpen: (id) => context.push('/pms/tasks/$id'),
                    ),
                    _TimelineTab(timeline: _timeline),
                    _BoardTab(
                      board: _board,
                      onOpen: (id) => context.push('/pms/tasks/$id'),
                      onChangeStatus: _changeBoardTaskStatus,
                    ),
                    _ImportTab(
                      jsonCtrl: _jsonCtrl,
                      preview: _importPreview,
                      importing: _importing,
                      onPickFile: () => _pickImportFile(dryRun: true),
                      onJsonPreview: _jsonImportPreview,
                      onCommit: _commitImport,
                      onExport: _exportTasks,
                      onTemplate: _downloadImportTemplate,
                    ),
                  ],
                ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.project,
    required this.overview,
    required this.topTasks,
    required this.onOpenTask,
  });

  final Map<String, dynamic>? project;
  final Map<String, dynamic>? overview;
  final List<Map<String, dynamic>> topTasks;
  final ValueChanged<String> onOpenTask;

  @override
  Widget build(BuildContext context) {
    final counts = (overview?['tasks'] is Map)
        ? Map<String, dynamic>.from(overview!['tasks'] as Map)
        : (overview?['task_counts'] is Map)
            ? Map<String, dynamic>.from(overview!['task_counts'] as Map)
            : const <String, dynamic>{};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusChip(status: project?['status']?.toString()),
                    const SizedBox(width: 8),
                    PriorityChip(priority: project?['priority']?.toString()),
                  ],
                ),
                const SizedBox(height: 12),
                Text(project?['description']?.toString() ?? 'No description'),
                const SizedBox(height: 12),
                Text(
                  'Site: ${labelOf(project?['site'])}',
                  style: const TextStyle(color: AppTheme.muted),
                ),
                Text(
                  'Timeline: ${formatDate(project?['timeline']?['start_date'])} → ${formatDate(project?['timeline']?['end_date'])}',
                  style: const TextStyle(color: AppTheme.muted),
                ),
                Text(
                  'Manager: ${labelOf(project?['project_manager'])}',
                  style: const TextStyle(color: AppTheme.muted),
                ),
                if (counts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in counts.entries)
                        if (e.value is! Map)
                          Chip(label: Text('${statusLabel(e.key)}: ${e.value}')),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Top tasks',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (topTasks.isEmpty)
          const EmptyState(message: 'No tasks yet')
        else
          ...topTasks.map((t) {
            final id = idOf(t);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(t['title']?.toString() ?? 'Task'),
                subtitle: Text('${t['current_progress'] ?? 0}%'),
                trailing: StatusChip(status: t['status']?.toString()),
                onTap: id == null ? null : () => onOpenTask(id),
              ),
            );
          }),
      ],
    );
  }
}

class _MediaTab extends StatelessWidget {
  const _MediaTab({
    required this.project,
    required this.pending,
    required this.busy,
    required this.onPendingChanged,
    required this.onUpload,
    required this.onRemove,
  });

  final Map<String, dynamic> project;
  final List<PendingFile> pending;
  final bool busy;
  final ValueChanged<List<PendingFile>> onPendingChanged;
  final VoidCallback onUpload;
  final Future<void> Function(String type, String url) onRemove;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        MediaPickerBar(files: pending, onChanged: onPendingChanged),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: busy ? null : onUpload,
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Upload media'),
        ),
        const SizedBox(height: 16),
        MediaListPanel(entity: project, onRemove: onRemove, busy: busy),
      ],
    );
  }
}

class _HierarchyTab extends StatelessWidget {
  const _HierarchyTab({required this.nodes, required this.onOpen});

  final List<Map<String, dynamic>> nodes;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return const EmptyState(message: 'No task hierarchy');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final n in nodes) _TreeNode(node: n, depth: 0, onOpen: onOpen),
      ],
    );
  }
}

class _TreeNode extends StatefulWidget {
  const _TreeNode({
    required this.node,
    required this.depth,
    required this.onOpen,
  });

  final Map<String, dynamic> node;
  final int depth;
  final ValueChanged<String> onOpen;

  @override
  State<_TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<_TreeNode> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final children = (widget.node['children'] is List)
        ? (widget.node['children'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final id = idOf(widget.node);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(left: widget.depth * 16.0),
          leading: children.isEmpty
              ? const SizedBox(width: 24)
              : IconButton(
                  icon: Icon(_expanded ? Icons.expand_more : Icons.chevron_right),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
          title: Text(widget.node['title']?.toString() ?? 'Task'),
          subtitle: Text('${widget.node['current_progress'] ?? 0}%'),
          trailing: StatusChip(status: widget.node['status']?.toString()),
          onTap: id == null ? null : () => widget.onOpen(id),
        ),
        if (_expanded)
          for (final c in children)
            _TreeNode(node: c, depth: widget.depth + 1, onOpen: widget.onOpen),
      ],
    );
  }
}

class _TimelineTab extends StatelessWidget {
  const _TimelineTab({required this.timeline});

  final Map<String, dynamic>? timeline;

  @override
  Widget build(BuildContext context) {
    final tasks = (timeline?['tasks'] is List)
        ? (timeline!['tasks'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    if (tasks.isEmpty) {
      return const EmptyState(message: 'No timeline data');
    }

    DateTime? min;
    DateTime? max;
    for (final t in tasks) {
      final s = DateTime.tryParse('${t['start_date'] ?? ''}');
      final e = DateTime.tryParse('${t['due_date'] ?? t['end_date'] ?? ''}');
      if (s != null && (min == null || s.isBefore(min))) min = s;
      if (e != null && (max == null || e.isAfter(max))) max = e;
      if (s != null && (max == null || s.isAfter(max))) max = s;
      if (e != null && (min == null || e.isBefore(min))) min = e;
    }
    final span = (min != null && max != null)
        ? max.difference(min).inDays.clamp(1, 36500)
        : 1;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (context, i) {
        final t = tasks[i];
        final start = DateTime.tryParse('${t['start_date'] ?? ''}');
        final end = DateTime.tryParse('${t['due_date'] ?? t['end_date'] ?? ''}');
        double left = 0;
        double width = 1;
        if (min != null && start != null && end != null) {
          left = start.difference(min).inDays / span;
          width = (end.difference(start).inDays / span).clamp(0.02, 1.0);
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t['title']?.toString() ?? 'Task',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${formatDate(t['start_date'])} → ${formatDate(t['due_date'] ?? t['end_date'])}',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              LayoutBuilder(
                builder: (context, constraints) {
                  final barLeft = left * constraints.maxWidth;
                  final barWidth =
                      (width * constraints.maxWidth).clamp(8.0, constraints.maxWidth);
                  return SizedBox(
                    height: 10,
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppTheme.border,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Positioned(
                          left: barLeft.clamp(0.0, constraints.maxWidth - 8),
                          width: barWidth,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BoardTab extends StatelessWidget {
  const _BoardTab({
    required this.board,
    required this.onOpen,
    required this.onChangeStatus,
  });

  final Map<String, dynamic>? board;
  final ValueChanged<String> onOpen;
  final void Function(Map<String, dynamic> task, String status) onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final groups = (board?['groups'] is Map)
        ? Map<String, dynamic>.from(board!['groups'] as Map)
        : <String, dynamic>{};
    return ListView(
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
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final items = (groups[col.$1] is List)
                            ? (groups[col.$1] as List)
                                .whereType<Map>()
                                .map((e) => Map<String, dynamic>.from(e))
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
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                dense: true,
                                title: Text(
                                  task['title']?.toString() ?? 'Task',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text('${task['current_progress'] ?? 0}%'),
                                onTap: id == null ? null : () => onOpen(id),
                                onLongPress: () async {
                                  final picked = await showModalBottomSheet<String>(
                                    context: context,
                                    builder: (ctx) => SafeArea(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          for (final s
                                              in PmsConstants.taskSettableStatuses)
                                            ListTile(
                                              title: Text(s.$2),
                                              onTap: () => Navigator.pop(ctx, s.$1),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                  if (picked != null) {
                                    onChangeStatus(task, picked);
                                  }
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
    );
  }
}

class _ImportTab extends StatelessWidget {
  const _ImportTab({
    required this.jsonCtrl,
    required this.preview,
    required this.importing,
    required this.onPickFile,
    required this.onJsonPreview,
    required this.onCommit,
    required this.onExport,
    required this.onTemplate,
  });

  final TextEditingController jsonCtrl;
  final Map<String, dynamic>? preview;
  final bool importing;
  final VoidCallback onPickFile;
  final VoidCallback onJsonPreview;
  final VoidCallback onCommit;
  final VoidCallback onExport;
  final VoidCallback onTemplate;

  @override
  Widget build(BuildContext context) {
    final errors = (preview?['errors'] is List) ? preview!['errors'] as List : const [];
    final tree = (preview?['tree'] is List) ? preview!['tree'] as List : const [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Upload an .xlsx dry-run preview, then commit. Or paste JSON rows.',
          style: TextStyle(color: AppTheme.muted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: importing ? null : onTemplate,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Import template'),
            ),
            OutlinedButton.icon(
              onPressed: importing ? null : onExport,
              icon: const Icon(Icons.ios_share),
              label: const Text('Export tasks'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: importing ? null : onPickFile,
          icon: const Icon(Icons.upload_file),
          label: const Text('Pick Excel (dry-run)'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: jsonCtrl,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'JSON rows (optional)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: importing ? null : onJsonPreview,
          child: const Text('Preview JSON'),
        ),
        if (importing) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ],
        if (preview != null) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: importing ? null : onCommit,
            child: const Text('Commit import'),
          ),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final e in errors.take(5))
              Text(
                e.toString(),
                style: const TextStyle(color: AppTheme.danger, fontSize: 12),
              ),
          ],
          const SizedBox(height: 12),
          const Text('Preview tree', style: TextStyle(fontWeight: FontWeight.w700)),
          if (tree.isEmpty)
            const Text('No tree in preview', style: TextStyle(color: AppTheme.muted))
          else
            ..._flattenPreview(tree, 0),
        ],
      ],
    );
  }

  List<Widget> _flattenPreview(List nodes, int depth) {
    final out = <Widget>[];
    for (final n in nodes) {
      if (n is! Map) continue;
      out.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 12.0, top: 4),
          child: Text('• ${n['title'] ?? 'Task'}'),
        ),
      );
      if (n['children'] is List) {
        out.addAll(_flattenPreview(n['children'] as List, depth + 1));
      }
    }
    return out;
  }
}
