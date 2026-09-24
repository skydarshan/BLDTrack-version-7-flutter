import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../services/pms_services.dart';
import '../utils/pms_constants.dart';
import '../widgets/media_widgets.dart';
import '../widgets/pickers.dart';
import '../widgets/pms_widgets.dart';

class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});

  final String taskId;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _task;
  List<Map<String, dynamic>> _progress = [];
  List<Map<String, dynamic>> _comments = [];
  final _commentCtrl = TextEditingController();
  bool _mediaBusy = false;
  List<PendingFile> _pendingMedia = [];
  List<OptionItem> _users = const [];

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
      final api = context.read<PmsServices>();
      final results = await Future.wait([
        api.tasks.getById(widget.taskId),
        api.tasks.getProgress(widget.taskId),
        api.masters.listUsers().catchError((_) => <Map<String, dynamic>>[]),
        api.tasks.listComments(widget.taskId).catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      final progress = results[1] as dynamic;
      setState(() {
        _task = results[0] as Map<String, dynamic>;
        _progress = progress.items as List<Map<String, dynamic>>;
        _users = mapToOptions(results[2] as List<Map<String, dynamic>>);
        _comments = results[3] as List<Map<String, dynamic>>;
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

  Future<void> _logProgress() async {
    final valueCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();
    var files = <PendingFile>[];
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: AppTheme.sheetPadding(ctx),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Log progress',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valueCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Progress added % *',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remarksCtrl,
                    decoration: const InputDecoration(labelText: 'Remarks'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  MediaPickerBar(
                    files: files,
                    onChanged: (v) => setModal(() => files = v),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Submit'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    final added = num.tryParse(valueCtrl.text.trim());
    if (added == null || added <= 0) {
      showPmsSnack(context, 'Enter progress greater than 0', error: true);
      return;
    }
    try {
      await context.read<PmsServices>().tasks.submitProgress(
            widget.taskId,
            {
              'progress_added': added,
              if (remarksCtrl.text.trim().isNotEmpty)
                'remarks': remarksCtrl.text.trim(),
            },
            files: files.map((f) => f.toEntry()).toList(),
          );
      if (!mounted) return;
      showPmsSnack(context, 'Progress logged');
      await _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _markComplete() async {
    final remarksCtrl = TextEditingController();
    var files = <PendingFile>[];
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: AppTheme.sheetPadding(ctx),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Mark complete',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remarksCtrl,
                    decoration: const InputDecoration(labelText: 'Remarks'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  MediaPickerBar(
                    files: files,
                    onChanged: (v) => setModal(() => files = v),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Submit'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<PmsServices>().tasks.markComplete(
            widget.taskId,
            data: {
              if (remarksCtrl.text.trim().isNotEmpty)
                'remarks': remarksCtrl.text.trim(),
            },
            files: files.map((f) => f.toEntry()).toList(),
          );
      if (!mounted) return;
      showPmsSnack(context, 'Completion submitted');
      await _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _editAssignment() async {
    final task = _task;
    if (task == null) return;
    var coordinatorId = idOf(task['coordinator']);
    var coordinatorLabel = labelOf(task['coordinator'], fallback: '');
    var memberIds =
        ((task['assignedMembers'] ?? task['assigned_members']) is List)
            ? ((task['assignedMembers'] ?? task['assigned_members']) as List)
                .map(idOf)
                .whereType<String>()
                .toList()
            : <String>[];
    var memberLabels =
        ((task['assignedMembers'] ?? task['assigned_members']) is List)
            ? ((task['assignedMembers'] ?? task['assigned_members']) as List)
                .map((m) => labelOf(m))
                .toList()
            : <String>[];
    final reasonCtrl = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: AppTheme.sheetPadding(ctx),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Update assignment',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  PickerField(
                    label: 'Coordinator',
                    valueLabel: coordinatorLabel,
                    onTap: () async {
                      final picked = await showOptionPicker(
                        context,
                        title: 'Coordinator',
                        options: _users,
                        selected: coordinatorId,
                      );
                      if (picked == null) return;
                      setModal(() {
                        coordinatorId = picked.value;
                        coordinatorLabel = picked.label;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  PickerField(
                    label: 'Add member',
                    valueLabel: memberLabels.join(', '),
                    onTap: () async {
                      final picked = await showOptionPicker(
                        context,
                        title: 'Member',
                        options: _users,
                      );
                      if (picked == null) return;
                      if (memberIds.contains(picked.value)) return;
                      setModal(() {
                        memberIds = [...memberIds, picked.value];
                        memberLabels = [...memberLabels, picked.label];
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(labelText: 'Reason'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<PmsServices>().tasks.updateAssignment(
        widget.taskId,
        {
          'coordinator': coordinatorId,
          'assignedMembers': memberIds,
          if (reasonCtrl.text.trim().isNotEmpty)
            'reason': reasonCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      showPmsSnack(context, 'Assignment updated');
      await _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _changeStatus() async {
    final picked = await showOptionPicker(
      context,
      title: 'Set status',
      options: [
        for (final s in PmsConstants.taskSettableStatuses)
          OptionItem(value: s.$1, label: s.$2),
      ],
      selected: _task?['status']?.toString(),
    );
    if (picked == null || !mounted) return;
    try {
      await context
          .read<PmsServices>()
          .tasks
          .update(widget.taskId, {'status': picked.value});
      if (!mounted) return;
      showPmsSnack(context, 'Status updated');
      await _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _uploadMedia() async {
    if (_pendingMedia.isEmpty) {
      showPmsSnack(context, 'Select files first', error: true);
      return;
    }
    setState(() => _mediaBusy = true);
    try {
      await context.read<PmsServices>().tasks.addMedia(
            widget.taskId,
            files: _pendingMedia.map((f) => f.toEntry()).toList(),
          );
      if (!mounted) return;
      showPmsSnack(context, 'Media uploaded');
      setState(() => _pendingMedia = []);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  Future<void> _removeMedia(String type, String url) async {
    setState(() => _mediaBusy = true);
    try {
      await context.read<PmsServices>().tasks.removeMedia(
            widget.taskId,
            {'type': type, 'url': url},
          );
      if (!mounted) return;
      showPmsSnack(context, 'Media removed');
      await _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final progress = _asNum(task?['current_progress'] ?? 0);
    final at100 = progress >= 100;
    final canComplete = at100 &&
        task?['status']?.toString() != 'completed' &&
        task?['completion']?['status']?.toString() != 'pending';

    final completion = task?['completion'] is Map
        ? Map<String, dynamic>.from(task!['completion'] as Map)
        : <String, dynamic>{};
    final isStep1Revise = completion['status']?.toString() == 'revise' &&
        ((completion['current_level'] as num?)?.toInt() ?? 0) < 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          task?['title']?.toString() ?? 'Task',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () async {
              final updated =
                  await context.push<bool>('/pms/tasks/${widget.taskId}/edit');
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
                  padding: const EdgeInsets.all(16),
                  child: ErrorBanner(message: _error!, onRetry: _load),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: AppTheme.formPadding,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  StatusChip(status: task?['status']?.toString()),
                                  const SizedBox(width: 8),
                                  PriorityChip(
                                    priority: task?['priority']?.toString(),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '$progress%',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(task?['description']?.toString() ?? ''),
                              const SizedBox(height: 12),
                              Text(
                                'Project: ${labelOf(task?['project'])}',
                                style: const TextStyle(color: AppTheme.muted),
                              ),
                              Text(
                                'Start: ${formatDate(task?['start_date'])} · Due: ${formatDate(task?['due_date'])}',
                                style: const TextStyle(color: AppTheme.muted),
                              ),
                              Text(
                                'Coordinator: ${labelOf(task?['coordinator'])}',
                                style: const TextStyle(color: AppTheme.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (completion['status']?.toString() == 'revise') ...[
                        const SizedBox(height: 12),
                        Card(
                          color: Colors.orange.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sent back for revision',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                if (completion['remarks'] != null &&
                                    completion['remarks'].toString().trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(completion['remarks'].toString()),
                                  ),
                                if (completion['revised_at'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Revised ${formatDateTime(completion['revised_at'])}',
                                      style: const TextStyle(
                                        color: AppTheme.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: _logProgress,
                            child: const Text('Log progress'),
                          ),
                          if (canComplete)
                            FilledButton(
                              onPressed: _markComplete,
                              child: const Text('Mark complete'),
                            ),
                          if (isStep1Revise)
                            FilledButton(
                              onPressed: () async {
                                try {
                                  await context.read<PmsServices>().tasks.resubmitCompletion(
                                        widget.taskId,
                                        data: const {},
                                      );
                                  if (!mounted) return;
                                  showPmsSnack(context, 'Resubmitted for approval');
                                  await _load();
                                } on ApiException catch (e) {
                                  if (mounted) showPmsSnack(context, e.message, error: true);
                                }
                              },
                              child: const Text('Resubmit'),
                            ),
                          OutlinedButton(
                            onPressed: _editAssignment,
                            child: const Text('Assignment'),
                          ),
                          OutlinedButton(
                            onPressed: _changeStatus,
                            child: const Text('Edit status'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Progress history',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_progress.isEmpty)
                        const Text(
                          'No progress entries yet',
                          style: TextStyle(color: AppTheme.muted),
                        )
                      else
                        ..._progress.map(
                          (row) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(
                                '+${row['progress_added'] ?? row['progress'] ?? 0}%',
                              ),
                              subtitle: Text(
                                [
                                  labelOf(row['created_by'] ?? row['user']),
                                  formatDateTime(
                                    row['createdAt'] ?? row['created_at'],
                                  ),
                                  if (row['remarks'] != null)
                                    row['remarks'].toString(),
                                ].where((s) => s.isNotEmpty && s != '—').join(' · '),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Comments',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_comments.isEmpty)
                        const Text('No comments yet', style: TextStyle(color: AppTheme.muted))
                      else
                        ..._comments.map(
                          (row) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(row['body']?.toString() ?? row['comment']?.toString() ?? row['text']?.toString() ?? ''),
                            subtitle: Text(
                              '${labelOf(row['created_by'] ?? row['user'])} · ${formatDateTime(row['createdAt'])}',
                            ),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _commentCtrl,
                              decoration: const InputDecoration(hintText: 'Add a comment'),
                            ),
                          ),
                          IconButton(
                            onPressed: () async {
                              final text = _commentCtrl.text.trim();
                              if (text.isEmpty) return;
                              try {
                                await context.read<PmsServices>().tasks.addComment(
                                  widget.taskId,
                                  {'body': text},
                                );
                                _commentCtrl.clear();
                                _load();
                              } on ApiException catch (e) {
                                showPmsSnack(context, e.message, error: true);
                              }
                            },
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Media',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      MediaPickerBar(
                        files: _pendingMedia,
                        onChanged: (v) => setState(() => _pendingMedia = v),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _mediaBusy ? null : _uploadMedia,
                        child: const Text('Upload media'),
                      ),
                      MediaListPanel(
                        entity: task ?? const {},
                        onRemove: _removeMedia,
                        busy: _mediaBusy,
                      ),
                    ],
                  ),
                ),
    );
  }
}

num _asNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse('$value') ?? 0;
}
