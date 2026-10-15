import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/form_validation_helpers.dart';
import '../../../core/utils/form_validators.dart';
import '../../auth/providers/auth_provider.dart';
import '../../settings/services/settings_apis.dart';
import '../services/pms_services.dart';
import '../utils/pms_constants.dart';
import '../widgets/media_widgets.dart';
import '../widgets/pickers.dart';
import '../widgets/pms_widgets.dart';

class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({
    super.key,
    this.taskId,
    this.initialProjectId,
  });

  final String? taskId;
  final String? initialProjectId;

  bool get isEdit => taskId != null && taskId!.isNotEmpty;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _sequenceCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();

  bool _loading = false;
  bool _saving = false;

  String _priority = 'medium';
  String _status = 'not_started';
  String _loadedStatus = 'not_started';
  DateTime? _startDate;
  DateTime? _dueDate;

  String? _projectId;
  String _projectLabel = '';
  String? _parentId;
  String _parentLabel = '';
  String? _coordinatorId;
  String _coordinatorLabel = '';
  List<String> _memberIds = [];
  List<String> _memberLabels = [];
  String? _locationId;
  String _locationLabel = '';
  String? _contractorId;
  String _contractorLabel = '';
  int _approvalSteps = 1;
  int _loadedApprovalSteps = 1;
  int _orgApprovalSteps = 0;

  List<PendingFile> _files = [];
  List<OptionItem> _projects = const [];
  List<OptionItem> _users = const [];
  List<OptionItem> _parents = const [];
  List<OptionItem> _locations = const [];
  List<OptionItem> _contractors = const [];
  final _fieldErrors = FieldErrors();

  @override
  void initState() {
    super.initState();
    _projectId = widget.initialProjectId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _reasonCtrl.dispose();
    _sequenceCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final api = context.read<PmsServices>();
      final settings = context.read<SettingsApis>();
      final me = (!widget.isEdit && _projectId == null)
          ? context.read<AuthProvider>().user
          : null;
      final projects = await api.projects.list({
        'page': 1,
        'limit': 100,
        'sortBy': 'project_name',
        'sortOrder': 'asc',
      });
      final users = await api.masters.listUsers();
      _projects = projects.items
          .map(
            (p) => OptionItem(
              value: idOf(p) ?? '',
              label: p['project_name']?.toString() ?? labelOf(p),
              raw: p,
            ),
          )
          .where((o) => o.value.isNotEmpty)
          .toList();
      _users = mapToOptions(users);
      try {
        final locations = await settings.locations.listAll({
          'sortBy': 'location_name',
          'sortOrder': 'asc',
        });
        _locations = mapToOptions(
          locations,
          labelOfRow: (row) => row['location_name']?.toString() ?? labelOf(row),
        );
      } catch (_) {}
      try {
        final contractors = await settings.contractors.listAll({
          'sortBy': 'name',
          'sortOrder': 'asc',
        });
        _contractors = mapToOptions(contractors);
      } catch (_) {}
      try {
        final org = await settings.getOrganization();
        final pm = org?['project_management_config'];
        final taskApproval = pm is Map ? pm['task_approval'] : null;
        final enabled = taskApproval is Map && taskApproval['enabled'] == true;
        final steps = enabled && taskApproval['steps'] is num
            ? (taskApproval['steps'] as num).toInt()
            : 0;
        _orgApprovalSteps = steps.clamp(0, 2);
        if (_orgApprovalSteps >= 1) _approvalSteps = 1;
      } catch (_) {}

      if (_projectId != null) {
        final match = _projects.where((p) => p.value == _projectId);
        if (match.isNotEmpty) _projectLabel = match.first.label;
        await _loadParents(_projectId!);
      } else if (me != null) {
        _coordinatorId = me.id;
        _coordinatorLabel = me.name;
        _memberIds = [me.id];
        _memberLabels = [me.name];
      }

      if (widget.isEdit) {
        final task = await api.tasks.getById(widget.taskId!);
        _titleCtrl.text = task['title']?.toString() ?? '';
        _descCtrl.text = task['description']?.toString() ?? '';
        _priority = task['priority']?.toString() ?? 'medium';
        final status = task['status']?.toString() ?? 'not_started';
        _loadedStatus = status;
        _status = status == 'completed'
            ? 'completed'
            : (['completion_requested', 'pending_approval'].contains(status)
                ? 'in_progress'
                : (PmsConstants.taskSettableStatuses.any((s) => s.$1 == status)
                    ? status
                    : 'not_started'));
        _projectId = idOf(task['project']);
        _projectLabel = labelOf(task['project'], fallback: '');
        _parentId = idOf(task['parentTask'] ?? task['parent_task']);
        _parentLabel = labelOf(task['parentTask'] ?? task['parent_task'], fallback: '');
        _coordinatorId = idOf(task['coordinator']);
        _coordinatorLabel = labelOf(task['coordinator'], fallback: '');
        final members = task['assignedMembers'] ?? task['assigned_members'];
        if (members is List) {
          _memberIds = members.map(idOf).whereType<String>().toList();
          _memberLabels = members.map((m) => labelOf(m)).toList();
        }
        _startDate = DateTime.tryParse('${task['start_date'] ?? ''}');
        _dueDate = DateTime.tryParse('${task['due_date'] ?? ''}');
        _locationId = idOf(task['location']);
        _locationLabel = labelOf(task['location'], fallback: '');
        if (_locationLabel == '—') _locationLabel = '';
        _contractorId = idOf(task['contractor']);
        _contractorLabel = labelOf(task['contractor'], fallback: '');
        if (_contractorLabel == '—') _contractorLabel = '';
        final sequence = task['sequence'];
        if (sequence != null) _sequenceCtrl.text = sequence.toString();
        final duration = task['duration_days'];
        if (duration != null) _durationCtrl.text = duration.toString();
        final completion = task['completion'];
        if (completion is Map) {
          final required = completion['required_steps'];
          if (required is num && (required == 1 || required == 2)) {
            _approvalSteps = required.toInt();
            _loadedApprovalSteps = _approvalSteps;
          }
        }
        if (_projectId != null) await _loadParents(_projectId!);
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showPmsSnack(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showPmsSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _loadParents(String projectId) async {
    try {
      final res = await context.read<PmsServices>().tasks.list({
        'page': 1,
        'limit': 100,
        'project': projectId,
        'sortBy': 'title',
        'sortOrder': 'asc',
      });
      _parents = res.items
          .where((t) => idOf(t) != widget.taskId)
          .map(
            (t) => OptionItem(
              value: idOf(t) ?? '',
              label: t['title']?.toString() ?? labelOf(t),
              raw: t,
            ),
          )
          .where((o) => o.value.isNotEmpty)
          .toList();
    } catch (_) {
      _parents = const [];
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = (start ? _startDate : _dueDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startDate = picked;
      } else {
        _dueDate = picked;
      }
    });
  }

  String? _iso(DateTime? d) =>
      d?.toIso8601String().substring(0, 10);

  Map<String, dynamic> _planningFields({required bool includeApproval}) {
    final sequenceText = _sequenceCtrl.text.trim();
    final durationText = _durationCtrl.text.trim();
    final sequence = int.tryParse(sequenceText);
    final duration = int.tryParse(durationText);
    return {
      'location': _locationId,
      'contractor': _contractorId,
      if (sequence != null) 'sequence': sequence,
      'duration_days': durationText.isEmpty ? null : duration,
      if (includeApproval && _orgApprovalSteps >= 1) 'approval_steps': _approvalSteps,
    };
  }

  bool _validateForm() {
    _fieldErrors.clear();
    if (!widget.isEdit) {
      _fieldErrors.set('project', requiredSelection(_projectId, 'Project'));
      _fieldErrors.set(
        'coordinator',
        requiredSelection(_coordinatorId, 'Coordinator'),
      );
      _fieldErrors.set('startDate', requiredDate(_startDate, 'Start date'));
      _fieldErrors.set(
        'dueDate',
        dateRangeError(
          start: _startDate,
          end: _dueDate,
          startLabel: 'Start date',
          endLabel: 'Due date',
        ),
      );
    } else if (_startDate != null && _dueDate != null) {
      _fieldErrors.set(
        'dueDate',
        dateRangeError(
          start: _startDate,
          end: _dueDate,
          startLabel: 'Start date',
          endLabel: 'Due date',
        ),
      );
    }
    _fieldErrors.set(
      'members',
      requiredList(_memberIds, 'At least one assigned member'),
    );
    final sequenceText = _sequenceCtrl.text.trim();
    if (sequenceText.isNotEmpty && int.tryParse(sequenceText) == null) {
      _fieldErrors.set('sequence', 'Sequence must be a whole number');
    }
    final durationText = _durationCtrl.text.trim();
    if (durationText.isNotEmpty && int.tryParse(durationText) == null) {
      _fieldErrors.set('duration', 'Duration must be a whole number of days');
    }
    setState(() {});
    return !_fieldErrors.hasErrors;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final formOk = _formKey.currentState?.validate() ?? false;
    final pickersOk = _validateForm();
    if (!formOk || !pickersOk) {
      showPmsSnack(
        context,
        _fieldErrors.summary.isNotEmpty
            ? _fieldErrors.summary
            : 'Please check the highlighted fields',
        error: true,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final api = context.read<PmsServices>().tasks;
      final files = _files.map((f) => f.toEntry()).toList();
      if (widget.isEdit) {
        final markDone = _status == 'completed' && _loadedStatus != 'completed';
        await api.update(
          widget.taskId!,
          {
            'title': _titleCtrl.text.trim(),
            'description': _descCtrl.text.trim(),
            'priority': _priority,
            if (_status != 'completed') 'status': _status,
            'start_date': _iso(_startDate),
            'due_date': _iso(_dueDate),
            'coordinator': _coordinatorId,
            'assignedMembers': _memberIds,
            ..._planningFields(includeApproval: _approvalSteps != _loadedApprovalSteps),
            if (_reasonCtrl.text.trim().isNotEmpty)
              'reason': _reasonCtrl.text.trim(),
          },
          files: files,
        );
        if (markDone) await api.markComplete(widget.taskId!);
      } else {
        await api.create(
          {
            'title': _titleCtrl.text.trim(),
            'description': _descCtrl.text.trim(),
            'project': _projectId,
            'parentTask': _parentId,
            'priority': _priority,
            'status': _status,
            'start_date': _iso(_startDate),
            'due_date': _iso(_dueDate),
            'coordinator': _coordinatorId,
            'assignedMembers': _memberIds,
            ..._planningFields(includeApproval: true),
          },
          files: files,
        );
      }
      if (!mounted) return;
      await showSavedConfirmation(
        context,
        widget.isEdit ? 'Task updated' : 'Task created',
      );
      if (mounted) context.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      _fieldErrors.merge(apiFieldErrors(e));
      setState(() {});
      showPmsSnack(context, formatApiErrorSummary(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isEdit ? 'Edit task' : 'New task')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: AppTheme.formPadding,
                children: [
                  if (_fieldErrors.hasErrors)
                    ValidationSummaryBanner(messages: _fieldErrors.messages),
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title *'),
                    validator: (v) => FormValidators.minLength(v, 2, 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  if (!widget.isEdit)
                    PickerField(
                      label: 'Project',
                      required: true,
                      valueLabel: _projectLabel,
                      errorText: _fieldErrors['project'],
                      onTap: () async {
                        final picked = await showOptionPicker(
                          context,
                          title: 'Select project',
                          options: _projects,
                          selected: _projectId,
                        );
                        if (picked == null) return;
                        setState(() {
                          _projectId = picked.value;
                          _projectLabel = picked.label;
                          _parentId = null;
                          _parentLabel = '';
                          _fieldErrors.set('project', null);
                        });
                        await _loadParents(picked.value);
                        if (mounted) setState(() {});
                      },
                    )
                  else
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Project'),
                      child: Text(_projectLabel.isEmpty ? '—' : _projectLabel),
                    ),
                  const SizedBox(height: 12),
                  if (!widget.isEdit)
                    PickerField(
                      label: 'Parent task',
                      valueLabel: _parentLabel,
                      enabled: _projectId != null,
                      onTap: () async {
                        final picked = await showOptionPicker(
                          context,
                          title: 'Parent task',
                          options: [
                            const OptionItem(value: '', label: 'None'),
                            ..._parents,
                          ],
                          selected: _parentId ?? '',
                        );
                        if (picked == null) return;
                        setState(() {
                          _parentId =
                              picked.value.isEmpty ? null : picked.value;
                          _parentLabel =
                              picked.value.isEmpty ? '' : picked.label;
                        });
                      },
                    ),
                  const SizedBox(height: 12),
                  AppDropdownFormField<String>(
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: [
                      for (final p in PmsConstants.priorities)
                        DropdownMenuItem(value: p.$1, child: Text(p.$2)),
                    ],
                    onChanged: (v) => setState(() => _priority = v ?? _priority),
                  ),
                  const SizedBox(height: 12),
                  AppDropdownFormField<String>(
                    key: ValueKey('status-$_status-${widget.isEdit}'),
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      for (final s in PmsConstants.taskSettableStatuses)
                        DropdownMenuItem(value: s.$1, child: Text(s.$2)),
                      if (widget.isEdit)
                        const DropdownMenuItem(value: 'completed', child: Text('Complete')),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? _status),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: PickerField(
                          label: 'Start date',
                          required: true,
                          valueLabel: _startDate == null
                              ? ''
                              : formatDate(_startDate!.toIso8601String()),
                          errorText: _fieldErrors['startDate'],
                          onTap: () async {
                            await _pickDate(start: true);
                            if (mounted) {
                              _fieldErrors.set('startDate', null);
                              setState(() {});
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PickerField(
                          label: 'Due date',
                          valueLabel: _dueDate == null
                              ? ''
                              : formatDate(_dueDate!.toIso8601String()),
                          errorText: _fieldErrors['dueDate'],
                          onTap: () async {
                            await _pickDate(start: false);
                            if (mounted) {
                              _fieldErrors.set('dueDate', null);
                              setState(() {});
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  PickerField(
                    label: 'Coordinator',
                    required: !widget.isEdit,
                    valueLabel: _coordinatorLabel,
                    errorText: _fieldErrors['coordinator'],
                    onTap: () async {
                      final picked = await showOptionPicker(
                        context,
                        title: 'Coordinator',
                        options: _users,
                        selected: _coordinatorId,
                      );
                      if (picked == null) return;
                      setState(() {
                        _coordinatorId = picked.value;
                        _coordinatorLabel = picked.label;
                        _fieldErrors.set('coordinator', null);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  PickerField(
                    label: 'Assigned members',
                    required: !widget.isEdit,
                    valueLabel: _memberLabels.isEmpty
                        ? ''
                        : _memberLabels.join(', '),
                    errorText: _fieldErrors['members'],
                    onTap: () async {
                      final picked = await showOptionPicker(
                        context,
                        title: 'Add member',
                        options: _users,
                      );
                      if (picked == null) return;
                      if (_memberIds.contains(picked.value)) return;
                      setState(() {
                        _memberIds = [..._memberIds, picked.value];
                        _memberLabels = [..._memberLabels, picked.label];
                        _fieldErrors.set('members', null);
                      });
                    },
                  ),
                  if (_memberIds.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      children: [
                        for (var i = 0; i < _memberIds.length; i++)
                          InputChip(
                            label: Text(_memberLabels[i]),
                            onDeleted: () => setState(() {
                              _memberIds = [..._memberIds]..removeAt(i);
                              _memberLabels = [..._memberLabels]..removeAt(i);
                              if (_memberIds.isEmpty && !widget.isEdit) {
                                _fieldErrors.set(
                                  'members',
                                  'At least one assigned member is required',
                                );
                              } else {
                                _fieldErrors.set('members', null);
                              }
                            }),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  PickerField(
                    label: 'Location',
                    valueLabel: _locationLabel,
                    onTap: () async {
                      final picked = await showOptionPicker(
                        context,
                        title: 'Location',
                        options: [
                          const OptionItem(value: '', label: 'None'),
                          ..._locations,
                        ],
                        selected: _locationId ?? '',
                        emptyMessage: 'No locations found',
                      );
                      if (picked == null) return;
                      setState(() {
                        _locationId = picked.value.isEmpty ? null : picked.value;
                        _locationLabel = picked.value.isEmpty ? '' : picked.label;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  PickerField(
                    label: 'Contractor',
                    valueLabel: _contractorLabel,
                    onTap: () async {
                      final picked = await showOptionPicker(
                        context,
                        title: 'Contractor',
                        options: [
                          const OptionItem(value: '', label: 'None'),
                          ..._contractors,
                        ],
                        selected: _contractorId ?? '',
                        emptyMessage: 'No contractors found',
                      );
                      if (picked == null) return;
                      setState(() {
                        _contractorId = picked.value.isEmpty ? null : picked.value;
                        _contractorLabel = picked.value.isEmpty ? '' : picked.label;
                      });
                    },
                  ),
                  if (_orgApprovalSteps >= 1) ...[
                    const SizedBox(height: 12),
                    AppDropdownFormField<int>(
                      initialValue: _approvalSteps.clamp(1, _orgApprovalSteps),
                      decoration: const InputDecoration(labelText: 'Approval steps'),
                      items: [
                        const DropdownMenuItem(value: 1, child: Text('1 step')),
                        if (_orgApprovalSteps >= 2)
                          const DropdownMenuItem(value: 2, child: Text('2 steps')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _approvalSteps = value);
                      },
                    ),
                  ] else if (widget.isEdit) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Approval steps: $_loadedApprovalSteps',
                      style: const TextStyle(color: AppTheme.muted),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _sequenceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Sequence',
                      errorText: _fieldErrors['sequence'],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _durationCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Duration (days)',
                      errorText: _fieldErrors['duration'],
                    ),
                  ),
                  if (widget.isEdit) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Reason (optional)',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  MediaPickerBar(
                    files: _files,
                    onChanged: (v) => setState(() => _files = v),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.isEdit ? 'Save changes' : 'Create task'),
                  ),
                ],
              ),
            ),
    );
  }
}
