import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/modern_widgets.dart';
import '../../../core/utils/list_query.dart';
import '../services/pms_services.dart';
import '../widgets/pms_widgets.dart';

class TaskApprovalsScreen extends StatefulWidget {
  const TaskApprovalsScreen({super.key});

  @override
  State<TaskApprovalsScreen> createState() => _TaskApprovalsScreenState();
}

class _TaskApprovalsScreenState extends State<TaskApprovalsScreen> {
  int _tabIndex = 0;

  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _search = '';

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _readyItems = [];
  List<Map<String, dynamic>> _pendingItems = [];
  int _readyPage = 1;
  int _pendingPage = 1;
  bool _readyHasMore = false;
  bool _pendingHasMore = false;

  int get _pageLimit => _search.trim().isEmpty ? 20 : 100;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    final next = value.trim();
    setState(() => _search = next);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _load(reset: true);
    });
  }

  bool _matches(Map<String, dynamic> task) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    bool hit(dynamic value) {
      final text = value?.toString().trim().toLowerCase() ?? '';
      return text.isNotEmpty && !looksLikeObjectId(text) && text.contains(q);
    }

    final project = task['project'];
    final site = task['site'];
    return hit(task['title']) ||
        hit(labelOf(project, fallback: '')) ||
        (project is Map && (hit(project['code']) || hit(project['project_name']))) ||
        hit(labelOf(site, fallback: '')) ||
        (site is Map && (hit(site['code']) || hit(site['site_name']) || hit(site['location'])));
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
      final query = _search.trim();
      final limit = _pageLimit;
      if (_tabIndex == 0) {
        final res = await api.readyForCompletion({
          'page': _readyPage,
          'limit': limit,
          if (query.isNotEmpty) 'search': query,
        });
        if (!mounted || _search.trim() != query) return;
        setState(() {
          _readyItems = reset ? res.items : [..._readyItems, ...res.items];
          _readyHasMore = res.items.length >= limit;
          _loading = false;
        });
      } else {
        final rows = await api.pendingApprovals({
          'page': _pendingPage,
          'limit': limit,
          if (query.isNotEmpty) 'search': query,
        });
        if (!mounted || _search.trim() != query) return;
        setState(() {
          _pendingItems = reset ? rows : [..._pendingItems, ...rows];
          _pendingHasMore = rows.length >= limit;
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
    String? remarkError;
    ModalRoute<dynamic>? sheetRoute;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        sheetRoute ??= ModalRoute.of(ctx);
        return StatefulBuilder(
          builder: (context, setLocal) {
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
                      errorText: remarkError,
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      if (required && remarksCtrl.text.trim().isEmpty) {
                        setLocal(() => remarkError = 'A remark is required');
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
                    child: const Text('Confirm'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    final remarks = remarksCtrl.text.trim();
    // The sheet route finishes disposing while the remark field can still be
    // attached. Drop the controller on the next frame so Flutter does not
    // throw '_dependents.isEmpty'.
    final close = sheetRoute?.completed ?? Future<void>.value();
    close.whenComplete(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        remarksCtrl.dispose();
      });
    });
    if (ok != true || !mounted) return;
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
    final items = (isReady ? _readyItems : _pendingItems).where(_matches).toList();
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
            padding: AppTheme.searchPadding,
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search title, project or site…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearch,
              onSubmitted: _onSearch,
            ),
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
                            message: _search.trim().isEmpty
                                ? (isReady
                                    ? 'No tasks ready for completion'
                                    : 'No tasks pending approval')
                                : listEmptyMessage(
                                    noun: isReady
                                        ? 'tasks ready for completion'
                                        : 'tasks pending approval',
                                    search: _search,
                                  ),
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
