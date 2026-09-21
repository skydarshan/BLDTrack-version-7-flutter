import 'package:flutter/material.dart';

import '../../../core/org/org_modules.dart';

/// Shared editor for org product modules + optional approval workflows.
///
/// [approverMode]:
/// - `names` — free-text role names (register flow)
/// - `roleIds` — dropdown of existing roles (org settings)
class ModuleEntitlementsEditor extends StatelessWidget {
  const ModuleEntitlementsEditor({
    super.key,
    required this.modules,
    required this.onModulesChanged,
    this.enabled = true,
    this.showApprovals = true,
    this.approverMode = ModuleApproverMode.names,
    this.roles = const [],
    this.rrSteps = 0,
    this.rrStep1 = '',
    this.rrStep2 = '',
    this.rateSteps = 0,
    this.rateStep1 = '',
    this.rateStep2 = '',
    this.taskSteps = 0,
    this.taskStep1 = '',
    this.taskStep2 = '',
    this.onApprovalChanged,
    this.editableModuleKeys,
  });

  final Map<String, dynamic> modules;
  final ValueChanged<Map<String, dynamic>> onModulesChanged;
  final bool enabled;
  final bool showApprovals;
  final ModuleApproverMode approverMode;
  final List<Map<String, dynamic>> roles;
  /// When set, only these product module keys can be toggled. Others are read-only.
  final Set<String>? editableModuleKeys;

  final int rrSteps;
  final String rrStep1;
  final String rrStep2;
  final int rateSteps;
  final String rateStep1;
  final String rateStep2;
  final int taskSteps;
  final String taskStep1;
  final String taskStep2;
  final void Function({
    int? rrSteps,
    String? rrStep1,
    String? rrStep2,
    int? rateSteps,
    String? rateStep1,
    String? rateStep2,
    int? taskSteps,
    String? taskStep1,
    String? taskStep2,
  })? onApprovalChanged;

  bool get _procurementOn {
    final m = modules['procurement'];
    return m is Map && m['enabled'] == true;
  }

  bool get _pmOn {
    final m = modules['project_management'];
    return m is Map && m['enabled'] == true;
  }

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeOrgModules(modules);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Product modules',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Enable the products this organization will use. Submodules control features inside each product.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
        const SizedBox(height: 12),
        for (final moduleKey in moduleCatalogMap.keys) ...[
          _ModuleCard(
            moduleKey: moduleKey,
            mod: Map<String, dynamic>.from(normalized[moduleKey] as Map),
            enabled: enabled && _canEditModule(moduleKey),
            readOnly: !_canEditModule(moduleKey),
            onToggleModule: (v) {
              var next = enableModuleFully(normalized, moduleKey, v);
              onModulesChanged(next);
              if (!v && onApprovalChanged != null) {
                if (moduleKey == 'procurement') {
                  onApprovalChanged!(
                    rrSteps: 0,
                    rrStep1: '',
                    rrStep2: '',
                    rateSteps: 0,
                    rateStep1: '',
                    rateStep2: '',
                  );
                }
                if (moduleKey == 'project_management') {
                  onApprovalChanged!(
                    taskSteps: 0,
                    taskStep1: '',
                    taskStep2: '',
                  );
                }
              }
            },
            onToggleSub: (sub, v) {
              onModulesChanged(
                setSubmoduleEnabled(normalized, moduleKey, sub, v),
              );
            },
          ),
          const SizedBox(height: 10),
        ],
        if (showApprovals && (_procurementOn || _pmOn)) ...[
          const SizedBox(height: 8),
          const Text(
            'Approval workflows',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            approverMode == ModuleApproverMode.names
                ? 'Optional. Use role names — roles are created on register if missing. Skip = no approval.'
                : 'Optional. Pick existing roles as approvers. Skip = no approval.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (_procurementOn) ...[
            _ApprovalBlock(
              title: 'RR approval',
              steps: rrSteps,
              step1: rrStep1,
              step2: rrStep2,
              enabled: enabled,
              mode: approverMode,
              roles: roles,
              onChanged: (steps, s1, s2) => onApprovalChanged?.call(
                rrSteps: steps,
                rrStep1: s1,
                rrStep2: s2,
              ),
            ),
            const SizedBox(height: 10),
            _ApprovalBlock(
              title: 'Rate approval',
              steps: rateSteps,
              step1: rateStep1,
              step2: rateStep2,
              enabled: enabled,
              mode: approverMode,
              roles: roles,
              onChanged: (steps, s1, s2) => onApprovalChanged?.call(
                rateSteps: steps,
                rateStep1: s1,
                rateStep2: s2,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_pmOn)
            _ApprovalBlock(
              title: 'Task progress approval',
              steps: taskSteps,
              step1: taskStep1,
              step2: taskStep2,
              enabled: enabled,
              mode: approverMode,
              roles: roles,
              onChanged: (steps, s1, s2) => onApprovalChanged?.call(
                taskSteps: steps,
                taskStep1: s1,
                taskStep2: s2,
              ),
            ),
        ],
      ],
    );
  }

  bool _canEditModule(String moduleKey) {
    if (editableModuleKeys == null) return true;
    return editableModuleKeys!.contains(moduleKey);
  }
}

enum ModuleApproverMode { names, roleIds }

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.moduleKey,
    required this.mod,
    required this.enabled,
    required this.readOnly,
    required this.onToggleModule,
    required this.onToggleSub,
  });

  final String moduleKey;
  final Map<String, dynamic> mod;
  final bool enabled;
  final bool readOnly;
  final ValueChanged<bool> onToggleModule;
  final void Function(String sub, bool enabled) onToggleSub;

  @override
  Widget build(BuildContext context) {
    final moduleOn = mod['enabled'] == true;
    final subs = mod['submodules'] is Map
        ? Map<String, dynamic>.from(mod['submodules'] as Map)
        : <String, dynamic>{};

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: Text(
              workspaceLabelsMap[moduleKey] ?? moduleKey,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: readOnly
                ? const Text(
                    'You cannot change this module',
                    style: TextStyle(fontSize: 12),
                  )
                : null,
            value: moduleOn,
            onChanged: enabled ? onToggleModule : null,
          ),
          if (moduleOn)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  for (final sub in moduleCatalogMap[moduleKey] ?? const <String>[])
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(submoduleLabelsMap[sub] ?? sub.replaceAll('_', ' ')),
                      value: subs[sub] == true,
                      onChanged: enabled
                          ? (v) => onToggleSub(sub, v ?? false)
                          : null,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ApprovalBlock extends StatelessWidget {
  const _ApprovalBlock({
    required this.title,
    required this.steps,
    required this.step1,
    required this.step2,
    required this.enabled,
    required this.mode,
    required this.roles,
    required this.onChanged,
  });

  final String title;
  final int steps;
  final String step1;
  final String step2;
  final bool enabled;
  final ModuleApproverMode mode;
  final List<Map<String, dynamic>> roles;
  final void Function(int steps, String step1, String step2) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: ValueKey('$title-steps'),
            initialValue: steps.clamp(0, 2),
            decoration: const InputDecoration(
              labelText: 'Steps',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Skip — no approval')),
              DropdownMenuItem(value: 1, child: Text('1 approval step')),
              DropdownMenuItem(value: 2, child: Text('2 approval steps')),
            ],
            onChanged: enabled
                ? (v) {
                    final n = v ?? 0;
                    onChanged(
                      n,
                      n >= 1 ? step1 : '',
                      n == 2 ? step2 : '',
                    );
                  }
                : null,
          ),
          if (steps >= 1) ...[
            const SizedBox(height: 10),
            _ApproverField(
              label: steps == 1 ? 'Approver role *' : 'Step 1 role *',
              value: step1,
              mode: mode,
              roles: roles,
              enabled: enabled,
              onChanged: (v) => onChanged(steps, v, step2),
            ),
          ],
          if (steps == 2) ...[
            const SizedBox(height: 10),
            _ApproverField(
              label: 'Step 2 role *',
              value: step2,
              mode: mode,
              roles: roles,
              enabled: enabled,
              onChanged: (v) => onChanged(steps, step1, v),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApproverField extends StatefulWidget {
  const _ApproverField({
    required this.label,
    required this.value,
    required this.mode,
    required this.roles,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ModuleApproverMode mode;
  final List<Map<String, dynamic>> roles;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_ApproverField> createState() => _ApproverFieldState();
}

class _ApproverFieldState extends State<_ApproverField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_ApproverField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync when parent clears/resets (e.g. steps dropdown), not on each keystroke.
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == ModuleApproverMode.names) {
      return TextFormField(
        controller: _controller,
        enabled: widget.enabled,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: 'e.g. Site Manager',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: widget.onChanged,
      );
    }

    final ids = widget.roles
        .map((r) => r['_id']?.toString() ?? r['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final selected = ids.contains(widget.value) ? widget.value : '';

    return DropdownButtonFormField<String>(
      key: ValueKey('${widget.label}-dropdown'),
      initialValue: selected.isEmpty ? '' : selected,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('Select role')),
        for (final role in widget.roles)
          if ((role['_id'] ?? role['id']) != null)
            DropdownMenuItem(
              value: (role['_id'] ?? role['id']).toString(),
              child: Text(role['name']?.toString() ?? 'Role'),
            ),
      ],
      onChanged: widget.enabled ? (v) => widget.onChanged(v ?? '') : null,
    );
  }
}
