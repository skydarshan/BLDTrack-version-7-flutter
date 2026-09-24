import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/modern_widgets.dart';
import '../services/pms_services.dart';
import '../widgets/pms_widgets.dart';

class TaskApprovalsScreen extends StatefulWidget {
  const TaskApprovalsScreen({super.key});

  @override
  State<TaskApprovalsScreen> createState() => _TaskApprovalsScreenState();
}

class _TaskApprovalsScreenState extends State<TaskApprovalsScreen> {
  int _tabIndex = 0;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _readyItems = [];
  List<Map<String, dynamic>> _pendingItems = [];
  int _readyPage = 1;
  int _pendingPage = 1;
  bool _readyHasMore = false;
  bool _pendingHasMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  void _switchTab(int index) {
    if (_tabIndex == index) return;
    setState(() => _tabIndex = index);
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _readyPage = 1;
      _pendingPage = 1;
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final api = context.read<PmsServices>().tasks;
      if (_tabIndex == 0) {
        final res = await api.readyForCompletion({'page': _readyPage, 'limit': 20});
        if (!mounted) return;
        setState(() {
          _readyItems = reset ? res.items : [..._readyItems, ...res.items];
          _readyHasMore = res.items.length >= 20;
          _loading = false;
        });
      } else {
        final rows = await api.pendingApprovals({'page': _pendingPage, 'limit': 20});
        if (!mounted) return;
        setState(() {
          _pendingItems = reset ? rows : [..._pendingItems, ...rows];
          _pendingHasMore = rows.length >= 20;
          _loading = false;
        });
      }
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

  Future<void> _openRemarksSheet({
    required String title,
    required bool required,
    required Future<void> Function(String remarks) onSubmit,
  }) async {
    final remarksCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: AppTheme.sheetPadding(ctx),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: remarksCtrl,
                decoration: InputDecoration(
                  labelText: required ? 'Remarks *' : 'Remarks (optional)',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true || !mounted) {
      remarksCtrl.dispose();
      return;
    }
    final remarks = remarksCtrl.text.trim();
    remarksCtrl.dispose();
    if (required && remarks.isEmpty) {
      showPmsSnack(context, 'A remark is required', error: true);
      return;
    }
    try {
      await onSubmit(remarks);
      if (!mounted) return;
      showPmsSnack(context, 'Updated');
      await _load(reset: true);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Widget _taskCard(
    Map<String, dynamic> task, {
    required List<Widget> actions,
    required Color accent,
  }) {
    final id = idOf(task);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: AppIconBadge(
                          icon: Icons.task_alt_rounded,
                          color: accent,
                          size: 40,
                          iconSize: 20,
                        ),
                        title: Text(
                          task['title']?.toString() ?? 'Task',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            labelOf(task['project']),
                            '${task['current_progress'] ?? 0}%',
                            formatDate(task['completion']?['requested_at']),
                          ].where((e) => e.isNotEmpty).join(' · '),
                        ),
                        trailing: StatusChip(status: task['status']?.toString()),
                        onTap: id == null ? null : () => context.push('/pms/tasks/$id'),
                      ),
                      if (task['completion']?['remarks'] != null &&
                          task['completion']['remarks'].toString().trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Remarks: ${task['completion']['remarks']}',
                            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                          ),
                        ),
                      Row(children: actions),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _tabIndex == 0;
    final items = isReady ? _readyItems : _pendingItems;
    final hasMore = isReady ? _readyHasMore : _pendingHasMore;
    final stepColor = isReady ? AppTheme.success : AppTheme.accent;

    return Scaffold(
      extendBody: true,
      backgroundColor: AppTheme.surface,
      appBar: const ModernAppBar(title: 'Task approvals'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSegmentTabs(
            index: _tabIndex,
            onChanged: _switchTab,
            colors: const [AppTheme.success, AppTheme.accent],
            tabs: const [
              'Step 1 — Ready',
              'Step 2 — Pending',
            ],
          ),
          Padding(
            padding: AppTheme.chipRowPadding,
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: stepColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isReady
                        ? 'Tasks ready for coordinator completion (Step 1)'
                        : 'Tasks awaiting final approval (Step 2)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: stepColor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.softBg(stepColor),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${items.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: stepColor,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: _loading && items.isEmpty
                  ? const CenteredScrollLoader()
                  : ListView(
                      padding: AppTheme.formPadding,
                      children: [
                        if (_error != null) ...[
                          ErrorBanner(message: _error!, onRetry: () => _load(reset: true)),
                          const SizedBox(height: 12),
                        ],
                        if (items.isEmpty)
                          EmptyState(
                            message: isReady
                                ? 'No tasks ready for completion'
                                : 'No tasks pending approval',
                            icon: isReady
                                ? Icons.check_circle_outline_rounded
                                : Icons.hourglass_empty_rounded,
                          )
                        else if (isReady)
                          ...items.map((task) {
                            final id = idOf(task);
                            if (id == null) return const SizedBox.shrink();
                            return _taskCard(
                              task,
                              accent: AppTheme.success,
                              actions: [
                                Expanded(
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.success,
                                    ),
                                    onPressed: () => _openRemarksSheet(
                                      title: 'Mark complete',
                                      required: false,
                                      onSubmit: (remarks) => context
                                          .read<PmsServices>()
                                          .tasks
                                          .markComplete(
                                            id,
                                            data: {
                                              if (remarks.isNotEmpty) 'remarks': remarks
                                            },
                                          ),
                                    ),
                                    child: const Text('Complete'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.warning,
                                      side: const BorderSide(color: AppTheme.warning),
                                    ),
                                    onPressed: () => _openRemarksSheet(
                                      title: 'Revise (Step 1)',
                                      required: true,
                                      onSubmit: (remarks) => context
                                          .read<PmsServices>()
                                          .tasks
                                          .reviseReadyCompletion(
                                            id,
                                            data: {'remarks': remarks},
                                          ),
                                    ),
                                    child: const Text('Revise'),
                                  ),
                                ),
                              ],
                            );
                          })
                        else
                          ...items.map((task) {
                            final id = idOf(task);
                            if (id == null) return const SizedBox.shrink();
                            return _taskCard(
                              task,
                              accent: AppTheme.accent,
                              actions: [
                                Expanded(
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.accent,
                                    ),
                                    onPressed: () => _openRemarksSheet(
                                      title: 'Approve completion',
                                      required: false,
                                      onSubmit: (remarks) => context
                                          .read<PmsServices>()
                                          .tasks
                                          .approveCompletion(
                                            id,
                                            data: {
                                              if (remarks.isNotEmpty) 'remarks': remarks
                                            },
                                          ),
                                    ),
                                    child: const Text('Approve'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.danger,
                                      side: const BorderSide(color: AppTheme.danger),
                                    ),
                                    onPressed: () => _openRemarksSheet(
                                      title: 'Revise (Step 2)',
                                      required: true,
                                      onSubmit: (remarks) => context
                                          .read<PmsServices>()
                                          .tasks
                                          .reviseCompletion(
                                            id,
                                            data: {'remarks': remarks},
                                          ),
                                    ),
                                    child: const Text('Revise'),
                                  ),
                                ),
                              ],
                            );
                          }),
                        if (hasMore)
                          TextButton(
                            onPressed: () {
                              if (isReady) {
                                _readyPage += 1;
                              } else {
                                _pendingPage += 1;
                              }
                              _load();
                            },
                            child: const Text('Load more'),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
