import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../utils/structure_errors.dart';
import '../utils/structure_from_tasks.dart';
import '../widgets/pms_widgets.dart';

/// Preview, then build buildings and floors from task titles.
///
/// Preview (`preview: true`) is loaded on open. Build (`preview: false`) writes
/// only what the preview said was missing.
class StructureFromTasksScreen extends StatefulWidget {
  const StructureFromTasksScreen({
    super.key,
    required this.onPreview,
    required this.onCommit,
  });

  /// Preview. A [StructureApiError] stays on screen unless the user has no
  /// access or the project is gone.
  final Future<Object?> Function() onPreview;

  /// Commit. A map is the written plan, including `created_nodes` and
  /// `linked_tasks`.
  final Future<Object?> Function() onCommit;

  @override
  State<StructureFromTasksScreen> createState() => _StructureFromTasksScreenState();
}

class _StructureFromTasksScreenState extends State<StructureFromTasksScreen> {
  bool _loading = true;
  bool _busy = false;
  int _request = 0;
  String? _error;
  FromTasksPlan? _plan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_busy) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.onPreview();
    if (!mounted || request != _request) return;
    if (result is StructureApiError) {
      if (result.isNoAccess || result.isNotFound) {
        Navigator.pop(context, result);
        return;
      }
      setState(() {
        _loading = false;
        _error = result.message;
        _plan = null;
      });
      return;
    }
    final data = result is Map ? Map<String, dynamic>.from(result) : const <String, dynamic>{};
    final plan = readFromTasksPlan(data);
    setState(() {
      _loading = false;
      _plan = plan;
      _error = plan == null ? 'Preview did not return a plan.' : null;
    });
  }

  Future<void> _commit() async {
    final plan = _plan;
    if (plan == null || !plan.canCommit || _busy) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.onCommit();
    if (!mounted || request != _request) return;
    if (result is StructureApiError) {
      if (result.isNoAccess || result.isNotFound) {
        Navigator.pop(context, result);
        return;
      }
      setState(() {
        _busy = false;
        _error = result.message;
      });
      return;
    }
    if (result == null || result is Map) {
      final data = result is Map ? Map<String, dynamic>.from(result) : const <String, dynamic>{};
      Navigator.pop(context, data);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Build from tasks'),
        leading: IconButton(
          tooltip: 'Close',
          onPressed: _busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: Column(
        children: [
          if (_loading || _busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: AppTheme.formPadding,
              children: [
                Text(fromTasksHelp, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                if (_error != null)
                  ErrorBanner(
                    message: _error!,
                    onRetry: _busy ? null : _load,
                  ),
                if (_loading && plan == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (plan != null) ...[
                  Text(
                    fromTasksSummary(plan),
                    key: const Key('from-tasks-summary'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (plan.warnings.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _WarningBox(lines: plan.warnings),
                  ],
                  if (plan.buildings.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text('No buildings or floors were found in task titles.'),
                    )
                  else ...[
                    const SizedBox(height: 12),
                    for (final building in plan.buildings) ...[
                      _BuildingCard(building: building),
                      const SizedBox(height: 12),
                    ],
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: plan == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      plan.canCommit
                          ? 'Nothing is saved until you build the structure.'
                          : 'Nothing new to add. Tasks that already have a link are left unchanged.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.muted),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      key: const Key('from-tasks-build'),
                      onPressed: _busy || !plan.canCommit ? null : _commit,
                      child: Text(_busy ? 'Working…' : 'Build'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _BuildingCard extends StatelessWidget {
  const _BuildingCard({required this.building});

  final FromTasksBuildingPlan building;

  @override
  Widget build(BuildContext context) {
    final name = building.name.isEmpty ? 'Building' : building.name;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                _ExistsChip(exists: building.exists),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Building',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.muted),
            ),
            _TaskList(tasks: building.tasksToLink),
            for (final floor in building.floors) _FloorBlock(floor: floor),
          ],
        ),
      ),
    );
  }
}

class _FloorBlock extends StatelessWidget {
  const _FloorBlock({required this.floor});

  final FromTasksFloorPlan floor;

  @override
  Widget build(BuildContext context) {
    final name = floor.name.isEmpty ? 'Floor' : floor.name;
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
              _ExistsChip(exists: floor.exists),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            fromTasksFloorSubtitle(floor),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.muted),
          ),
          _TaskList(tasks: floor.tasksToLink),
        ],
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({required this.tasks});

  final List<FromTasksLink> tasks;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tasks to link',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.muted),
          ),
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(task.title.isEmpty ? 'Task' : task.title),
            ),
        ],
      ),
    );
  }
}

class _ExistsChip extends StatelessWidget {
  const _ExistsChip({required this.exists});

  final bool exists;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: exists ? AppTheme.border : AppTheme.brandLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        exists ? 'Existing' : 'New',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.warning, size: 20),
              SizedBox(width: 8),
              Text(
                'Warnings',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.warning),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(left: 28, bottom: 4),
              child: Text(line, style: const TextStyle(height: 1.35)),
            ),
        ],
      ),
    );
  }
}
