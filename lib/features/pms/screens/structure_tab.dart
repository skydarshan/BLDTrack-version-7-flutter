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
import '../utils/structure_nodes.dart';
import '../widgets/pms_widgets.dart';
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
    await _load(silent: true);
    if (!mounted) return;
    showPmsSnack(context, creating ? 'Node added.' : 'Node updated.');
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

  Future<void> _fromTasks() async {
    try {
      final data = await context.read<PmsServices>().structure.fromTasks(widget.projectId);
      if (!mounted) return;
      final created = asNum(data['created_nodes'])?.toInt() ?? 0;
      final linked = asNum(data['linked_tasks'])?.toInt() ?? 0;
      showPmsSnack(context, 'Added $created node(s). Linked $linked task(s).');
      await _load(silent: true);
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
      showPmsSnack(
        context,
        error.isNotFound ? error.notFoundMessage : error.message,
        error: true,
      );
      if (error.isNotFound) await _load(silent: true);
    }
  }

  Future<void> _generate() async {
    final result = await showDialog<Object?>(
      context: context,
      useSafeArea: false,
      builder: (ctx) => Dialog.fullscreen(
        child: TowerGenerateScreen(
          onPreview: (payload) async {
            try {
              return await context.read<PmsServices>().structure.generateTower(
                    widget.projectId,
                    payload,
                  );
            } on ApiException catch (e) {
              return readStructureError(e);
            }
          },
          onCreate: (payload) async {
            try {
              return await context.read<PmsServices>().structure.generateTower(
                    widget.projectId,
                    payload,
                    preview: false,
                  );
            } on ApiException catch (e) {
              return readStructureError(e);
            }
          },
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

    return Column(
      children: [
        if (canCreate)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _fromTasks,
                      child: const Text('From tasks'),
                    ),
                    OutlinedButton(
                      onPressed: _generate,
                      child: const Text('Generate tower'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _editNode(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: _roots.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No structure has been set up for this project yet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _SiblingList(
                  nodes: _roots,
                  parentId: null,
                  depth: 0,
                  primary: true,
                  canUpdate: canUpdate,
                  canDelete: canDelete,
                  canCreate: canCreate,
                  canDrag: canUpdate && !_reordering,
                  onEdit: (item) => _editNode(existing: item),
                  onDelete: _deleteNode,
                  onAddChild: (item) => _editNode(parentId: idOf(item)),
                  onReorder: _reorder,
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
    required this.primary,
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
  final bool primary;
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
    final drag = canDrag && nodes.length > 1;
    Widget block(Map<String, dynamic> node, int index) {
      final id = idOf(node);
      final children = structureChildNodes(node);
      return Column(
        key: ValueKey(id ?? '$depth-$index'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NodeTile(
            node: node,
            depth: depth,
            index: index,
            canDrag: drag,
            canUpdate: canUpdate,
            canDelete: canDelete,
            canCreate: canCreate,
            onEdit: () => onEdit(node),
            onDelete: () => onDelete(node),
            onAddChild: () => onAddChild(node),
          ),
          if (children.isNotEmpty)
            _SiblingList(
              nodes: children,
              parentId: id,
              depth: depth + 1,
              primary: false,
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

    final children = [for (var i = 0; i < nodes.length; i++) block(nodes[i], i)];
    if (!drag) {
      final column = Column(children: children);
      if (!primary) return column;
      return ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        children: [column],
      );
    }
    return ReorderableListView(
      shrinkWrap: !primary,
      physics: primary ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
      padding: primary ? const EdgeInsets.fromLTRB(8, 8, 8, 24) : EdgeInsets.zero,
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) => onReorder(parentId, nodes, oldIndex, newIndex),
      children: children,
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.node,
    required this.depth,
    required this.index,
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
      title: Row(
        children: [
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
          if (canDrag)
            ReorderableDragStartListener(
              index: index,
              child: const Tooltip(
                message: 'Reorder',
                child: Icon(Icons.drag_handle),
              ),
            ),
          if (canCreate)
            IconButton(
              tooltip: 'Add',
              onPressed: onAddChild,
              icon: const Icon(Icons.add),
            ),
          if (canUpdate)
            IconButton(
              tooltip: 'Edit',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (canDelete)
            IconButton(
              tooltip: 'Delete',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
            ),
        ],
      ),
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
    return [
      for (final node in widget.nodes)
        if (idOf(node) != null && !blocked.contains(idOf(node)))
          if (_type != 'unit' || node['type']?.toString() == 'floor') node,
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
    final typeItems = [
      for (final entry in structureNodeTypeLabels.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      if (!structureNodeTypeLabels.containsKey(_type))
        DropdownMenuItem(value: _type, child: Text(_type)),
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
