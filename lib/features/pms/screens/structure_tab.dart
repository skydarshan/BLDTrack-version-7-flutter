import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/form_validation_helpers.dart';
import '../../auth/providers/auth_provider.dart';
import '../../settings/utils/permissions.dart';
import '../services/pms_services.dart';
import '../utils/structure_access.dart';
import '../utils/structure_errors.dart';
import '../utils/structure_from_tasks.dart';
import '../utils/structure_nodes.dart';
import '../utils/tower_generate.dart';
import '../widgets/pms_widgets.dart';
import 'structure_from_tasks_screen.dart';
import 'tower_generate_screen.dart';

class StructureTab extends StatefulWidget {
  const StructureTab({super.key, required this.projectId});

  final String projectId;

  @override
  State<StructureTab> createState() => _StructureTabState();
}

class _StructureTabState extends State<StructureTab> {
  bool _loading = true;
  bool _reordering = false;
  bool _noAccess = false;
  String? _error;
  List<Map<String, dynamic>> _roots = [];
  Map<String, dynamic> _summary = const {};
  final Set<String> _openIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
        _noAccess = false;
      });
    }
    try {
      final data = await context.read<PmsServices>().structure.tree(widget.projectId);
      if (!mounted) return;
      setState(() {
        _roots = structureTreeRoots(data);
        _summary = data['summary'] is Map
            ? Map<String, dynamic>.from(data['summary'] as Map)
            : const {};
        _loading = false;
        _reordering = false;
        _error = null;
        _noAccess = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      final error = readStructureError(e);
      setState(() {
        _noAccess = error.isNoAccess;
        _error = error.isNotFound ? error.notFoundMessage : error.message;
        _loading = false;
        _reordering = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _reordering = false;
      });
    }
  }

  Future<void> _editNode({Map<String, dynamic>? existing, String? parentId}) async {
    final perms = Permissions(context.read<AuthProvider>().user);
    final creating = existing == null;
    if (creating && !canStructureAction(perms, 'create')) return;
    if (!creating && !canStructureAction(perms, 'update')) return;

    final flat = flattenStructureNodes(_roots);
    final result = await showDialog<Object?>(
      context: context,
      builder: (ctx) => _NodeDialog(
        existing: existing,
        parentId: parentId ?? idOf(existing?['parent']),
        nodes: flat,
        onSave: (payload) async {
          if (!mounted) return null;
          try {
            final api = context.read<PmsServices>().structure;
            if (creating) {
              await api.createNode(widget.projectId, payload);
            } else {
              final id = idOf(existing);
              if (id == null || id.isEmpty) {
                return readStructureError(
                  ApiException(statusCode: 404, message: 'Not found'),
                );
              }
              await api.updateNode(widget.projectId, id, payload);
            }
            return null;
          } on ApiException catch (e) {
            return readStructureError(e);
          }
        },
      ),
    );
    if (!mounted || result == null) return;
    if (result is StructureApiError) {
      if (result.isNoAccess) {
        setState(() {
          _noAccess = true;
          _error = result.message;
        });
        return;
      }
      if (result.isNotFound) {
        showPmsSnack(context, result.notFoundMessage, error: true);
        await _load(silent: true);
      }
      return;
    }
    if (creating && parentId != null && parentId.isNotEmpty) {
      _openIds.add(parentId);
    }
    await _load(silent: true);
    if (!mounted) return;
    showPmsSnack(context, creating ? 'Node added.' : 'Node updated.');
  }

  void _toggleOpen(String id) {
    setState(() {
      if (!_openIds.remove(id)) _openIds.add(id);
    });
  }

  Future<void> _deleteNode(Map<String, dynamic> node) async {
    final perms = Permissions(context.read<AuthProvider>().user);
    if (!canStructureAction(perms, 'delete')) return;
    final id = idOf(node);
    if (id == null || id.isEmpty) return;
    final ok = await confirmAction(
      context,
      title: 'Delete node?',
      message: structureDeleteMessage(node),
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    await _deleteWithConflicts(id);
  }

  /// 409 delete: confirm `cascade`, then `unlink_tasks`, and retry with those flags.
  Future<void> _deleteWithConflicts(String id) async {
    if (!mounted) return;
    final api = context.read<PmsServices>().structure;
    var cascade = false;
    var unlinkTasks = false;
    while (mounted) {
      try {
        final result = await api.deleteNode(
              widget.projectId,
              id,
              cascade: cascade,
              unlinkTasks: unlinkTasks,
            );
        if (!mounted) return;
        final deleted = asNum(result['deleted_nodes'])?.toInt() ?? 0;
        final unlinked = asNum(result['unlinked_tasks'])?.toInt() ?? 0;
        if (deleted > 0 || unlinked > 0) {
          final taskNote = unlinked > 0 ? ' Unlinked $unlinked task(s).' : '';
          showPmsSnack(context, 'Removed $deleted node(s).$taskNote');
        }
        await _load(silent: true);
        return;
      } on ApiException catch (e) {
        if (!mounted) return;
        final error = readStructureError(e);
        if (error.isNoAccess) {
          setState(() {
            _noAccess = true;
            _error = error.message;
          });
          return;
        }
        if (error.isNotFound) {
          showPmsSnack(context, error.notFoundMessage, error: true);
          await _load(silent: true);
          return;
        }
        if (error.needsCascade && !cascade) {
          final confirmed = await confirmAction(
            context,
            title: 'Delete child nodes?',
            message: error.messageFor('cascade'),
            confirmLabel: 'Delete',
          );
          if (!confirmed || !mounted) return;
          cascade = true;
          continue;
        }
        if (error.needsUnlinkTasks && !unlinkTasks) {
          final confirmed = await confirmAction(
            context,
            title: 'Unlink tasks?',
            message: error.messageFor('unlink_tasks'),
            confirmLabel: 'Unlink',
          );
          if (!confirmed || !mounted) return;
          unlinkTasks = true;
          continue;
        }
        showPmsSnack(context, error.message, error: true);
        return;
      }
    }
  }

  Future<Object?> _previewFromTasks() async {
    final api = context.read<PmsServices>();
    try {
      final tasks = await api.projects.getTaskTree(widget.projectId);
      final tree = await api.structure.tree(widget.projectId, flat: true);
      final preview = planStructureFromTasks(
        tasks: tasks,
        nodes: readStructureNodeList(tree),
      );
      if (preview == null) {
        return readStructureError(
          ApiException(
            statusCode: 400,
            message: 'Nothing was detected in the task titles',
          ),
        );
      }
      return preview;
    } on ApiException catch (e) {
      return readStructureError(e);
    }
  }

  Future<Object?> _commitFromTasks() async {
    final api = context.read<PmsServices>();
    try {
      final tasks = await api.projects.getTaskTree(widget.projectId);
      final tree = await api.structure.tree(widget.projectId, flat: true);
      final preview = planStructureFromTasks(
        tasks: tasks,
        nodes: readStructureNodeList(tree),
      );
      if (preview == null) {
        return readStructureError(
          ApiException(
            statusCode: 400,
            message: 'Nothing was detected in the task titles',
          ),
        );
      }
      return await commitPlannedStructureFromTasks(
        preview: preview,
        createNode: (body) => api.structure.createNode(widget.projectId, body),
        linkTask: (taskId, nodeId) async {
          await api.tasks.update(taskId, {
            'structure_nodes': [nodeId],
          });
        },
      );
    } on ApiException catch (e) {
      return readStructureError(e);
    }
  }

  Future<Object?> _previewTower(Map<String, dynamic> payload) async {
    final api = context.read<PmsServices>();
    try {
      final remote = await api.structure.generateTower(widget.projectId, payload);
      if (towerSpecPreview(remote)) return remote;
    } on ApiException catch (e) {
      final error = readStructureError(e);
      if (error.isNoAccess || error.isNotFound || error.statusCode == 409) return error;
    } catch (_) {}
    try {
      final tree = await api.structure.tree(widget.projectId, flat: true);
      return planTowerGenerate(
        payload,
        existing: readStructureNodeList(tree),
      ).preview;
    } on ApiException catch (e) {
      return readStructureError(e);
    }
  }

  Future<Object?> _commitTower(Map<String, dynamic> payload) async {
    final api = context.read<PmsServices>();
    try {
      final remote = await api.structure.generateTower(
        widget.projectId,
        payload,
        preview: false,
      );
      if (towerSpecCommit(remote)) return remote;
    } on ApiException catch (e) {
      final error = readStructureError(e);
      if (error.isNoAccess || error.isNotFound || error.statusCode == 409) return error;
    } catch (_) {}
    try {
      final tree = await api.structure.tree(widget.projectId, flat: true);
      return await commitPlannedTower(
        payload: payload,
        existing: readStructureNodeList(tree),
        createNode: (body) => api.structure.createNode(widget.projectId, body),
      );
    } on ApiException catch (e) {
      return readStructureError(e);
    }
  }

  Future<void> _fromTasks() async {
    final result = await showDialog<Object?>(
      context: context,
      useSafeArea: false,
      builder: (ctx) => Dialog.fullscreen(
        child: StructureFromTasksScreen(
          onPreview: _previewFromTasks,
          onCommit: _commitFromTasks,
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result is StructureApiError) {
      if (result.isNoAccess) {
        setState(() {
          _noAccess = true;
          _error = result.message;
        });
      } else if (result.isNotFound) {
        showPmsSnack(context, result.notFoundMessage, error: true);
        await _load(silent: true);
      }
      return;
    }
    final data = result is Map ? Map<String, dynamic>.from(result) : const <String, dynamic>{};
    final created = asNum(data['created_nodes'])?.toInt() ?? 0;
    final linked = asNum(data['linked_tasks'])?.toInt() ?? 0;
    showPmsSnack(
      context,
      fromTasksResultMessage(createdNodes: created, linkedTasks: linked),
    );
    await _load(silent: true);
  }

  Future<void> _generate() async {
    final result = await showDialog<Object?>(
      context: context,
      useSafeArea: false,
      builder: (ctx) => Dialog.fullscreen(
        child: TowerGenerateScreen(
          onPreview: _previewTower,
          onCreate: _commitTower,
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result is StructureApiError) {
      if (result.isNoAccess) {
        setState(() {
          _noAccess = true;
          _error = result.message;
        });
      } else if (result.isNotFound) {
        showPmsSnack(context, result.notFoundMessage, error: true);
        await _load(silent: true);
      }
      return;
    }
    showPmsSnack(context, 'Tower added.');
    await _load(silent: true);
  }

  Future<void> _reorder(
    String? parentId,
    List<Map<String, dynamic>> siblings,
    int oldIndex,
    int newIndex,
  ) async {
    if (_reordering) return;
    if (oldIndex == newIndex) return;
    final next = [...siblings];
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    final ids = <String>[];
    for (final node in next) {
      final id = idOf(node);
      if (id == null || id.isEmpty) return;
      ids.add(id);
    }
    setState(() {
      _roots = reorderStructureSiblings(_roots, parentId, ids);
      _reordering = true;
    });
    try {
      await context.read<PmsServices>().structure.reorder(
            widget.projectId,
            parentId: parentId,
            nodeIds: ids,
          );
      if (!mounted) return;
      await _load(silent: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      final error = readStructureError(e);
      if (error.isNoAccess) {
        setState(() {
          _noAccess = true;
          _error = error.message;
          _reordering = false;
        });
        return;
      }
      showPmsSnack(
        context,
        error.isNotFound ? error.notFoundMessage : error.message,
        error: true,
      );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      showPmsSnack(context, e.toString(), error: true);
      setState(() => _reordering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = Permissions(context.watch<AuthProvider>().user);
    final canCreate = canStructureAction(perms, 'create');
    final canUpdate = canStructureAction(perms, 'update');
    final canDelete = canStructureAction(perms, 'delete');

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_noAccess) {
      return NoAccessNotice(
        message: _error ?? 'You are not assigned to this project\'s site',
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorBanner(message: _error!, onRetry: _load),
      );
    }

    final actions = canCreate
        ? <Widget>[
            if (_summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _summary.entries
                      .where((entry) => (asNum(entry.value) ?? 0) > 0)
                      .map((entry) => '${entry.value} ${entry.key}')
                      .join(' · '),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: _fromTasks,
                  child: const Text('From tasks'),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: _generate,
                  child: const Text('Generate tower'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => _editNode(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ]
        : const <Widget>[];

    if (_roots.isEmpty) {
      return Column(
        children: [
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: actions,
              ),
            ),
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No structure has been set up for this project yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        ...actions,
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _SiblingList(
              nodes: _roots,
              parentId: null,
              depth: 0,
              openIds: _openIds,
              canUpdate: canUpdate,
              canDelete: canDelete,
              canCreate: canCreate,
              canDrag: canUpdate && !_reordering,
              onToggle: _toggleOpen,
              onEdit: (item) => _editNode(existing: item),
              onDelete: _deleteNode,
              onAddChild: (item) => _editNode(parentId: idOf(item)),
              onReorder: _reorder,
            ),
          ),
        ),
      ],
    );
  }
}

class _SiblingList extends StatelessWidget {
  const _SiblingList({
    required this.nodes,
    required this.parentId,
    required this.depth,
    required this.openIds,
    required this.onToggle,
    required this.canUpdate,
    required this.canDelete,
    required this.canCreate,
    required this.canDrag,
    required this.onEdit,
    required this.onDelete,
    required this.onAddChild,
    required this.onReorder,
  });

  final List<Map<String, dynamic>> nodes;
  final String? parentId;
  final int depth;
  final Set<String> openIds;
  final ValueChanged<String> onToggle;
  final bool canUpdate;
  final bool canDelete;
  final bool canCreate;
  final bool canDrag;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;
  final ValueChanged<Map<String, dynamic>> onAddChild;
  final void Function(String? parentId, List<Map<String, dynamic>> siblings, int oldIndex, int newIndex)
      onReorder;

  @override
  Widget build(BuildContext context) {
    final shown = sortStructureChildren(nodes);
    final drag = canDrag && shown.where((node) => node['type'] != 'floor').length > 1;
    Widget block(Map<String, dynamic> node, int index) {
      final id = idOf(node);
      final children = structureChildNodes(node);
      final open = id != null && openIds.contains(id);
      return Column(
        key: ValueKey(id ?? '$depth-$index'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NodeTile(
            node: node,
            depth: depth,
            index: index,
            expanded: open,
            canDrag: drag && node['type'] != 'floor',
            canUpdate: canUpdate,
            canDelete: canDelete,
            canCreate: canCreate,
            onToggle: children.isNotEmpty && id != null ? () => onToggle(id) : null,
            onEdit: () => onEdit(node),
            onDelete: () => onDelete(node),
            onAddChild: () => onAddChild(node),
          ),
          if (children.isNotEmpty && open)
            _SiblingList(
              nodes: children,
              parentId: id,
              depth: depth + 1,
              openIds: openIds,
              onToggle: onToggle,
              canUpdate: canUpdate,
              canDelete: canDelete,
              canCreate: canCreate,
              canDrag: canDrag,
              onEdit: onEdit,
              onDelete: onDelete,
              onAddChild: onAddChild,
              onReorder: onReorder,
            ),
        ],
      );
    }

    final children = [for (var i = 0; i < shown.length; i++) block(shown[i], i)];
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    if (!drag) return column;
    return _InlineReorder(
      onReorder: (oldIndex, newIndex) => onReorder(parentId, shown, oldIndex, newIndex),
      children: children,
    );
  }
}

class _ReorderDrag {
  const _ReorderDrag(this.token, this.index);

  final Object token;
  final int index;
}

class _ReorderScope extends InheritedWidget {
  const _ReorderScope({required this.token, required super.child});

  final Object token;

  static Object? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ReorderScope>()?.token;
  }

  @override
  bool updateShouldNotify(_ReorderScope oldWidget) => token != oldWidget.token;
}

/// Sibling reorder that stays inside the parent list. A nested
/// [ReorderableListView] paints its rows outside that list.
class _InlineReorder extends StatefulWidget {
  const _InlineReorder({required this.onReorder, required this.children});

  final void Function(int oldIndex, int newIndex) onReorder;
  final List<Widget> children;

  @override
  State<_InlineReorder> createState() => _InlineReorderState();
}

class _InlineReorderState extends State<_InlineReorder> {
  final Object _token = Object();

  @override
  Widget build(BuildContext context) {
    return _ReorderScope(
      token: _token,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            DragTarget<_ReorderDrag>(
              onWillAcceptWithDetails: (details) =>
                  details.data.token == _token && details.data.index != i,
              onAcceptWithDetails: (details) {
                final from = details.data.index;
                if (details.data.token != _token || from == i) return;
                widget.onReorder(from, i);
              },
              builder: (context, candidate, _) {
                return DecoratedBox(
                  decoration: BoxDecoration(
                    border: candidate.isEmpty
                        ? null
                        : const Border(top: BorderSide(color: AppTheme.brand, width: 2)),
                  ),
                  child: widget.children[i],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.node,
    required this.depth,
    required this.index,
    required this.expanded,
    required this.onToggle,
    required this.canDrag,
    required this.canUpdate,
    required this.canDelete,
    required this.canCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onAddChild,
  });

  final Map<String, dynamic> node;
  final int depth;
  final int index;
  final bool expanded;
  final VoidCallback? onToggle;
  final bool canDrag;
  final bool canUpdate;
  final bool canDelete;
  final bool canCreate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddChild;

  @override
  Widget build(BuildContext context) {
    final type = node['type']?.toString() ?? '';
    final tasks = structureTaskCount(node);
    final name = node['name']?.toString().trim() ?? '';
    return ListTile(
      contentPadding: EdgeInsets.only(left: 8.0 + (depth * 16), right: 4),
      onTap: onToggle,
      title: Row(
        children: [
          if (onToggle != null)
            Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 20),
          Expanded(child: Text(name.isEmpty ? 'Node' : name)),
          if (tasks > 0)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$tasks',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
      subtitle: Text(_subtitle(type)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canDrag) _dragHandle(context, name),
          if (canCreate && structureAcceptsChildren(type))
            IconButton(
              tooltip: 'Add',
              visualDensity: VisualDensity.compact,
              onPressed: onAddChild,
              icon: const Icon(Icons.add),
            ),
          if (canUpdate)
            IconButton(
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (canDelete)
            IconButton(
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
            ),
        ],
      ),
    );
  }

  Widget _dragHandle(BuildContext context, String name) {
    final handle = const Tooltip(
      message: 'Reorder',
      child: Icon(Icons.drag_handle),
    );
    final token = _ReorderScope.maybeOf(context);
    if (token == null) return handle;
    return LongPressDraggable<_ReorderDrag>(
      data: _ReorderDrag(token, index),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(name.isEmpty ? 'Node' : name),
        ),
      ),
      child: handle,
    );
  }

  String _subtitle(String type) {
    final parts = <String>[structureNodeTypeLabels[type] ?? type];
    if (type == 'floor') {
      final level = asNum(node['level_number']);
      if (level != null) {
        parts.add('level ${level == level.roundToDouble() ? level.toInt() : level}');
      }
    }
    if (type == 'core') {
      final from = asNum(node['from_level']);
      final to = asNum(node['to_level']);
      if (from != null && to != null) {
        final fromText = from == from.roundToDouble() ? from.toInt() : from;
        final toText = to == to.roundToDouble() ? to.toInt() : to;
        parts.add('levels $fromText–$toText');
      }
    }
    final category = node['category']?.toString().trim() ?? '';
    if (category.isNotEmpty) parts.add(category);
    return parts.join(' · ');
  }
}

class _NodeDialog extends StatefulWidget {
  const _NodeDialog({
    required this.nodes,
    required this.onSave,
    this.existing,
    this.parentId,
  });

  final Map<String, dynamic>? existing;
  final String? parentId;
  final List<Map<String, dynamic>> nodes;

  /// Null when the node was saved. A [StructureApiError] stays on screen when
  /// the user can fix it, and closes the dialog for no-access or not-found.
  final Future<StructureApiError?> Function(Map<String, dynamic> payload) onSave;

  @override
  State<_NodeDialog> createState() => _NodeDialogState();
}

class _NodeDialogState extends State<_NodeDialog> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _category;
  late final TextEditingController _level;
  late final TextEditingController _fromLevel;
  late final TextEditingController _toLevel;
  late final Map<String, TextEditingController> _geometry;
  late String _type;
  String? _parentId;
  final _fields = FieldErrors();
  String? _banner;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?['name']?.toString() ?? '');
    _code = TextEditingController(text: existing?['code']?.toString() ?? '');
    _category = TextEditingController(text: existing?['category']?.toString() ?? '');
    _level = TextEditingController(text: _levelText(existing?['level_number']));
    _fromLevel = TextEditingController(text: _levelText(existing?['from_level']));
    _toLevel = TextEditingController(text: _levelText(existing?['to_level']));
    final geometry = existing?['geometry'] is Map ? existing!['geometry'] as Map : const {};
    _geometry = {
      for (final key in ['height', 'width', 'depth', 'x', 'z', 'rotation'])
        key: TextEditingController(text: _levelText(geometry[key])),
    };
    if (existing != null) {
      _type = existing['type']?.toString() ?? 'building';
    } else {
      _type = structureChildType(_typeOf(widget.parentId));
    }
    if (!_editing && !structureNodeTypeLabels.containsKey(_type)) _type = 'building';
    _parentId = widget.parentId;
    if (!structureTypeAllowsParent(_type)) _parentId = null;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _category.dispose();
    _level.dispose();
    _fromLevel.dispose();
    _toLevel.dispose();
    for (final controller in _geometry.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _levelText(dynamic value) {
    final number = asNum(value);
    if (number == null) return '';
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number.toString();
  }

  String? _typeOf(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final node in widget.nodes) {
      if (idOf(node) == id) return node['type']?.toString();
    }
    return null;
  }

  List<Map<String, dynamic>> _parentChoices() {
    if (!structureTypeAllowsParent(_type)) return const [];
    final selfId = idOf(widget.existing);
    final blocked = selfId == null
        ? const <String>{}
        : {selfId, ...structureDescendantIds(selfId, widget.nodes)};
    final requiredParent = structureRequiredParentType(_type);
    return [
      for (final node in widget.nodes)
        if (idOf(node) != null && !blocked.contains(idOf(node)))
          if (requiredParent != null && node['type']?.toString() == requiredParent) node,
    ];
  }

  Future<void> _submit() async {
    if (_saving) return;
    _fields.clear();
    final selfId = idOf(widget.existing);
    final blocked = selfId == null
        ? const <String>{}
        : {selfId, ...structureDescendantIds(selfId, widget.nodes)};
    final write = _editing
        ? structurePatchBody(
            existing: widget.existing!,
            parentId: _parentId,
            parentType: _typeOf(_parentId),
            name: _name.text,
            code: _code.text,
            category: _category.text,
            levelText: _level.text,
            fromLevelText: _fromLevel.text,
            toLevelText: _toLevel.text,
            blockedParentIds: blocked,
            geometryText: {for (final entry in _geometry.entries) entry.key: entry.value.text},
          )
        : structureCreateBody(
            type: _type,
            parentId: _parentId,
            parentType: _typeOf(_parentId),
            name: _name.text,
            code: _code.text,
            category: _category.text,
            levelText: _level.text,
            fromLevelText: _fromLevel.text,
            toLevelText: _toLevel.text,
            geometryText: {for (final entry in _geometry.entries) entry.key: entry.value.text},
          );
    if (!write.isValid) {
      setState(() {
        _banner = null;
        _fields.merge(write.errors);
      });
      return;
    }
    final payload = write.payload!;
    if (payload.isEmpty) {
      Navigator.pop(context, true);
      return;
    }

    setState(() {
      _saving = true;
      _banner = null;
    });
    final error = await widget.onSave(payload);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
      return;
    }
    if (error.isNoAccess || error.isNotFound) {
      Navigator.pop(context, error);
      return;
    }
    setState(() {
      _saving = false;
      _banner = error.message;
      if (error.highlightFields) _fields.merge(error.fieldMessages);
    });
  }

  @override
  Widget build(BuildContext context) {
    final parents = _parentChoices();
    final parentValue = parents.any((node) => idOf(node) == _parentId) ? _parentId : null;
    final typeChoices = _editing
        ? <String>[_type]
        : () {
            if (widget.parentId != null && widget.parentId!.isNotEmpty) {
              final types = structureChildTypes(_typeOf(widget.parentId));
              if (types.isNotEmpty) return types;
            }
            return structureNodeTypeLabels.keys.toList();
          }();
    final typeItems = [
      for (final type in typeChoices)
        DropdownMenuItem(
          value: type,
          child: Text(structureNodeTypeLabels[type] ?? type),
        ),
      if (!typeChoices.contains(_type))
        DropdownMenuItem(value: _type, child: Text(structureNodeTypeLabels[_type] ?? _type)),
    ];
    return AlertDialog(
      title: Text(_editing ? 'Edit node' : 'Add node'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_banner != null || _fields.hasErrors) ...[
              ValidationSummaryBanner(
                messages: [
                  ?_banner,
                  for (final message in _fields.messages)
                    if (message != _banner) message,
                ],
              ),
            ],
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _type == 'floor' ? 'Name' : 'Name *',
                helperText: _type == 'floor'
                    ? 'Leave blank for Ground Floor, Floor 5, or Basement 2.'
                    : null,
                errorText: _fields['name'],
              ),
              onChanged: (_) {
                if (_fields['name'] != null) setState(() => _fields.set('name', null));
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('type-$_type'),
              initialValue: _type,
              decoration: InputDecoration(
                labelText: 'Type',
                errorText: _fields['type'],
              ),
              items: typeItems,
              onChanged: _editing || _saving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _type = value;
                        _fields.set('type', null);
                        if (!structureTypeAllowsParent(value) ||
                            !_parentChoices().any((node) => idOf(node) == _parentId)) {
                          _parentId = null;
                        }
                      });
                    },
            ),
            if (structureTypeAllowsParent(_type)) ...[
              const SizedBox(height: 12),
              if (parents.isEmpty)
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Parent *',
                    errorText: _fields['parent'],
                  ),
                  child: const Text('No matching parent'),
                )
              else
                DropdownButtonFormField<String?>(
                  key: ValueKey('parent-$_type-$parentValue'),
                  initialValue: parentValue,
                  decoration: InputDecoration(
                    labelText: 'Parent *',
                    errorText: _fields['parent'],
                  ),
                  items: [
                    if (parentValue == null)
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Select'),
                      ),
                    for (final node in parents)
                      DropdownMenuItem<String?>(
                        value: idOf(node),
                        child: Text(node['name']?.toString() ?? 'Node'),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                            _parentId = value;
                            _fields.set('parent', null);
                          }),
                ),
            ],
            if (_type == 'floor') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _level,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                decoration: InputDecoration(
                  labelText: 'Level *',
                  helperText: 'From −20 to 300. Unique in this building.',
                  errorText: _fields['level_number'],
                ),
                onChanged: (_) {
                  if (_fields['level_number'] != null) {
                    setState(() => _fields.set('level_number', null));
                  }
                },
              ),
            ],
            if (_type == 'core') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _fromLevel,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                decoration: InputDecoration(
                  labelText: 'From level *',
                  errorText: _fields['from_level'],
                ),
                onChanged: (_) {
                  if (_fields['from_level'] != null) {
                    setState(() => _fields.set('from_level', null));
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _toLevel,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                decoration: InputDecoration(
                  labelText: 'To level *',
                  errorText: _fields['to_level'],
                ),
                onChanged: (_) {
                  if (_fields['to_level'] != null) {
                    setState(() => _fields.set('to_level', null));
                  }
                },
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              decoration: InputDecoration(
                labelText: 'Category',
                errorText: _fields['category'],
              ),
              onChanged: (_) {
                if (_fields['category'] != null) setState(() => _fields.set('category', null));
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              decoration: InputDecoration(
                labelText: 'Code',
                errorText: _fields['code'],
              ),
              onChanged: (_) {
                if (_fields['code'] != null) setState(() => _fields.set('code', null));
              },
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Geometry'),
            ),
            for (final key in _geometry.keys) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _geometry[key],
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: InputDecoration(
                  labelText: key,
                  errorText: _fields['geometry.$key'],
                ),
                onChanged: (_) {
                  if (_fields['geometry.$key'] != null) {
                    setState(() => _fields.set('geometry.$key', null));
                  }
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
