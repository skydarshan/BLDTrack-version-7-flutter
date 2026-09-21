import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../utils/pms_constants.dart';

Map<String, dynamic> emptyTemplateTaskNode() => {
      'title': '',
      'description': '',
      'priority': 'medium',
      'duration_days': '',
      'children': <Map<String, dynamic>>[],
    };

List<Map<String, dynamic>> mapTemplateTasksFromApi(dynamic tasks) {
  List<Map<String, dynamic>> mapNodes(dynamic list) {
    if (list is! List) return [];
    return list.map((t) {
      final m = t is Map ? Map<String, dynamic>.from(t) : <String, dynamic>{};
      return {
        'title': m['title']?.toString() ?? '',
        'description': m['description']?.toString() ?? '',
        'priority': m['priority']?.toString() ?? 'medium',
        'duration_days': m['duration_days'] != null ? '${m['duration_days']}' : '',
        'children': mapNodes(m['children']),
      };
    }).toList();
  }

  final mapped = mapNodes(tasks);
  return mapped.isEmpty ? [emptyTemplateTaskNode()] : mapped;
}

List<Map<String, dynamic>> serializeTemplateTasks(List<Map<String, dynamic>> tasks) {
  return tasks
      .where((t) => (t['title']?.toString() ?? '').trim().isNotEmpty)
      .map((t) {
        final daysRaw = t['duration_days']?.toString().trim() ?? '';
        final children = (t['children'] is List)
            ? serializeTemplateTasks(
                (t['children'] as List)
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList(),
              )
            : <Map<String, dynamic>>[];
        return {
          'title': (t['title'] as String).trim(),
          'description': (t['description']?.toString() ?? '').trim(),
          'priority': t['priority']?.toString() ?? 'medium',
          'duration_days': daysRaw.isEmpty ? null : num.tryParse(daysRaw),
          'children': children,
        };
      })
      .toList();
}

List<Map<String, dynamic>> _updateAtPath(
  List<Map<String, dynamic>> nodes,
  List<int> path,
  Map<String, dynamic> patch,
) {
  if (path.isEmpty) return nodes;
  final head = path.first;
  final rest = path.sublist(1);
  return [
    for (var i = 0; i < nodes.length; i++)
      if (i != head)
        nodes[i]
      else if (rest.isEmpty)
        {...nodes[i], ...patch}
      else
        {
          ...nodes[i],
          'children': _updateAtPath(_childrenOf(nodes[i]), rest, patch),
        },
  ];
}

List<Map<String, dynamic>> _addChildAtPath(
  List<Map<String, dynamic>> nodes,
  List<int> path,
) {
  if (path.isEmpty) return [...nodes, emptyTemplateTaskNode()];
  final head = path.first;
  final rest = path.sublist(1);
  return [
    for (var i = 0; i < nodes.length; i++)
      if (i != head)
        nodes[i]
      else if (rest.isEmpty)
        {
          ...nodes[i],
          'children': [..._childrenOf(nodes[i]), emptyTemplateTaskNode()],
        }
      else
        {
          ...nodes[i],
          'children': _addChildAtPath(_childrenOf(nodes[i]), rest),
        },
  ];
}

List<Map<String, dynamic>> _removeAtPath(
  List<Map<String, dynamic>> nodes,
  List<int> path,
) {
  if (path.isEmpty) return nodes;
  final head = path.first;
  final rest = path.sublist(1);
  if (rest.isEmpty) {
    return [for (var i = 0; i < nodes.length; i++) if (i != head) nodes[i]];
  }
  return [
    for (var i = 0; i < nodes.length; i++)
      if (i != head)
        nodes[i]
      else
        {
          ...nodes[i],
          'children': _removeAtPath(_childrenOf(nodes[i]), rest),
        },
  ];
}

List<Map<String, dynamic>> _childrenOf(Map<String, dynamic> node) {
  final c = node['children'];
  if (c is! List) return [];
  return c.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

/// Recursive editable template task tree.
class TemplateTreeEditor extends StatelessWidget {
  const TemplateTreeEditor({
    super.key,
    required this.tasks,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> tasks;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tasks.length; i++)
          _TemplateNodeEditor(
            node: tasks[i],
            path: [i],
            depth: 0,
            onOp: (op, path, [patch]) {
              if (op == 'update') {
                onChanged(_updateAtPath(tasks, path, patch ?? {}));
              } else if (op == 'add') {
                onChanged(_addChildAtPath(tasks, path));
              } else if (op == 'remove') {
                onChanged(_removeAtPath(tasks, path));
              }
            },
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => onChanged([...tasks, emptyTemplateTaskNode()]),
          icon: const Icon(Icons.add),
          label: const Text('Add root task'),
        ),
      ],
    );
  }
}

class _TemplateNodeEditor extends StatelessWidget {
  const _TemplateNodeEditor({
    required this.node,
    required this.path,
    required this.depth,
    required this.onOp,
  });

  final Map<String, dynamic> node;
  final List<int> path;
  final int depth;
  final void Function(String op, List<int> path, [Map<String, dynamic>? patch])
      onOp;

  @override
  Widget build(BuildContext context) {
    final children = _childrenOf(node);
    return Card(
      margin: EdgeInsets.only(left: depth * 12.0, bottom: 8),
      color: depth > 0 ? const Color(0xFFFAFBFC) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              initialValue: node['title']?.toString() ?? '',
              decoration: const InputDecoration(
                labelText: 'Task title *',
                isDense: true,
              ),
              onChanged: (v) => onOp('update', path, {'title': v}),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: (node['priority']?.toString().isNotEmpty ?? false)
                        ? node['priority'].toString()
                        : 'medium',
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      isDense: true,
                    ),
                    items: [
                      for (final p in PmsConstants.priorities)
                        DropdownMenuItem(value: p.$1, child: Text(p.$2)),
                    ],
                    onChanged: (v) {
                      if (v != null) onOp('update', path, {'priority': v});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: node['duration_days']?.toString() ?? '',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Days',
                      isDense: true,
                    ),
                    onChanged: (v) => onOp('update', path, {'duration_days': v}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: node['description']?.toString() ?? '',
              decoration: const InputDecoration(
                labelText: 'Description',
                isDense: true,
              ),
              maxLines: 2,
              onChanged: (v) => onOp('update', path, {'description': v}),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => onOp('add', path),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Sub-task'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => onOp('remove', path),
                  icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                ),
              ],
            ),
            for (var i = 0; i < children.length; i++)
              _TemplateNodeEditor(
                node: children[i],
                path: [...path, i],
                depth: depth + 1,
                onOp: onOp,
              ),
          ],
        ),
      ),
    );
  }
}
