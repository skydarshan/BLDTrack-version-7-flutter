import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/form_validation_helpers.dart';
import '../../../core/utils/form_validators.dart';
import '../../auth/providers/auth_provider.dart';
import '../services/pms_services.dart';
import '../utils/pms_constants.dart';
import '../utils/site_options.dart';
import '../widgets/media_widgets.dart';
import '../widgets/pickers.dart';
import '../widgets/pms_widgets.dart';

class ProjectFormScreen extends StatefulWidget {
  const ProjectFormScreen({super.key, this.projectId});

  final String? projectId;

  bool get isEdit => projectId != null && projectId!.isNotEmpty;

  @override
  State<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends State<ProjectFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  bool _loading = false;
  bool _saving = false;
  String? _error;

  String _status = 'not_started';
  String _priority = 'medium';
  String _priorityOff = 'medium';
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _actualStart;
  DateTime? _actualEnd;

  String? _siteId;
  String _siteLabel = '';
  Map<String, dynamic>? _siteRaw;
  Map<String, dynamic>? _loaded;
  Timer? _codeTimer;
  int _codeReq = 0;
  int _previewSeq = 1;
  String? _serverCode;
  bool _useNextCodeApi = true;
  String? _managerId;
  String _managerLabel = '';
  String? _leadId;
  String _leadLabel = '';
  String? _coordinatorId;
  String _coordinatorLabel = '';
  List<PendingFile> _pendingMedia = [];

  List<OptionItem> _users = const [];
  final _fieldErrors = FieldErrors();

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onProjectNameChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _codeTimer?.cancel();
    _nameCtrl.removeListener(_onProjectNameChanged);
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _descCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final api = context.read<PmsServices>();
      final me = widget.isEdit ? null : context.read<AuthProvider>().user;
      _users = mapToOptions(await api.masters.listUsers());
      if (!widget.isEdit && me != null && mounted) {
        _managerId = me.id;
        _managerLabel = me.name;
        _leadId = me.id;
        _leadLabel = me.name;
        _coordinatorId = me.id;
        _coordinatorLabel = me.name;
      }
      if (widget.isEdit) {
        final project = await api.projects.getById(widget.projectId!);
        _loaded = project;
        _nameCtrl.text = project['project_name']?.toString() ?? '';
        _codeCtrl.text = project['code']?.toString() ?? '';
        _descCtrl.text = project['description']?.toString() ?? '';
        final status = project['status']?.toString();
        _status = (status == null || status.isEmpty) ? 'not_started' : status;
        _priority = project['priority']?.toString() ?? 'medium';
        if (_priority != 'high') _priorityOff = _priority;
        _siteId = idOf(project['site']);
        _siteLabel = labelOf(project['site']);
        _managerId = idOf(project['project_manager']);
        _managerLabel = labelOf(project['project_manager'], fallback: '');
        _leadId = idOf(project['project_lead']);
        _leadLabel = labelOf(project['project_lead'], fallback: '');
        _coordinatorId = idOf(project['default_coordinator']);
        _coordinatorLabel = labelOf(project['default_coordinator'], fallback: '');
        final timeline = project['timeline'];
        if (timeline is Map) {
          _startDate = DateTime.tryParse('${timeline['start_date'] ?? ''}');
          _endDate = DateTime.tryParse('${timeline['end_date'] ?? ''}');
          _actualStart = DateTime.tryParse('${timeline['actual_start_date'] ?? ''}');
          _actualEnd = DateTime.tryParse('${timeline['actual_end_date'] ?? ''}');
        }
      }
      if (!mounted) return;
      setState(() => _loading = false);
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

  Future<DateTime?> _pickDate(DateTime? current) {
    return showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
  }

  String? _iso(DateTime? d) =>
      d?.toIso8601String().substring(0, 10);

  void _onProjectNameChanged() {
    if (widget.isEdit) return;
    _serverCode = null;
    if (mounted) setState(() {});
    _scheduleGeneratedCode();
  }

  void _scheduleGeneratedCode() {
    _codeTimer?.cancel();
    _codeTimer = Timer(const Duration(milliseconds: 350), _refreshGeneratedCode);
  }

  /// Code shown in the input. Comes from the name and site immediately.
  String _displayCode() {
    if (widget.isEdit) return _codeCtrl.text.trim();
    final server = _serverCode?.trim() ?? '';
    if (server.isNotEmpty) return server;
    final name = _nameCtrl.text.trim();
    if (name.length < 2 || (_siteId ?? '').isEmpty) return '';
    final site = _siteRaw ?? <String, dynamic>{'site_name': _siteLabel};
    return _buildProjectCode(name, site, _previewSeq);
  }

  Future<void> _refreshGeneratedCode() async {
    if (widget.isEdit || !mounted) return;
    final name = _nameCtrl.text.trim();
    final siteId = _siteId;
    if (name.length < 2 || siteId == null || siteId.isEmpty) {
      if (_serverCode != null || _previewSeq != 1) {
        setState(() {
          _serverCode = null;
          _previewSeq = 1;
        });
      }
      return;
    }
    final req = ++_codeReq;
    try {
      final api = context.read<PmsServices>().projects;
      if (_useNextCodeApi) {
        try {
          final code = await api.nextCode(siteId: siteId, projectName: name);
          if (!mounted || req != _codeReq) return;
          if (code.isNotEmpty) {
            setState(() => _serverCode = code);
            return;
          }
        } on ApiException catch (e) {
          if (e.statusCode == 404 || e.statusCode == 403 || e.statusCode == 400) {
            _useNextCodeApi = false;
          }
        }
      }
      final seq = await _localSequence(api, siteId);
      if (!mounted || req != _codeReq) return;
      setState(() => _previewSeq = seq);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<int> _localSequence(dynamic api, String siteId) async {
    final counts = await api.statusCounts({'site': siteId});
    final total = (counts['total'] as num?)?.toInt() ?? 0;
    return total + 1;
  }

  bool _validateForm() {
    _fieldErrors.clear();
    if (!widget.isEdit) {
      _fieldErrors.set('site', requiredSelection(_siteId, 'Site'));
      _fieldErrors.set('startDate', requiredDate(_startDate, 'Start date'));
      _fieldErrors.set('endDate', requiredDate(_endDate, 'End date'));
      _fieldErrors.set('manager', requiredSelection(_managerId, 'Project manager'));
      _fieldErrors.set('lead', requiredSelection(_leadId, 'Project lead'));
    }
    _fieldErrors.set(
      'endDate',
      _fieldErrors['endDate'] ??
          dateRangeError(
            start: _startDate,
            end: _endDate,
            startLabel: 'Start date',
            endLabel: 'End date',
          ),
    );
    _fieldErrors.set(
      'actualEnd',
      dateRangeError(
        start: _actualStart,
        end: _actualEnd,
        startLabel: 'Actual start',
        endLabel: 'Actual end',
      ),
    );
    setState(() {});
    return !_fieldErrors.hasErrors;
  }

  void _setPriority(String value) {
    setState(() {
      _priority = value;
      if (value != 'high') _priorityOff = value;
    });
  }

  Future<void> _removeExistingMedia(String type, String url) async {
    final id = widget.projectId;
    if (id == null || id.isEmpty) return;
    setState(() => _saving = true);
    final api = context.read<PmsServices>().projects;
    try {
      await api.removeMedia(id, {'type': type, 'url': url});
      final project = await api.getById(id);
      if (!mounted) return;
      setState(() => _loaded = project);
      showPmsSnack(context, 'File removed');
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
      if (!widget.isEdit) {
        _codeTimer?.cancel();
        await _refreshGeneratedCode();
      }
      if (!mounted) return;
      final api = context.read<PmsServices>().projects;
      final timeline = {
        'start_date': _iso(_startDate),
        'end_date': _iso(_endDate),
        'actual_start_date': _iso(_actualStart),
        'actual_end_date': _iso(_actualEnd),
      };
      final files = _pendingMedia.map((file) => file.toEntry()).toList();
      if (widget.isEdit) {
        await api.update(
          widget.projectId!,
          {
            'project_name': _nameCtrl.text.trim(),
            'code': _codeCtrl.text.trim(),
            'description': _descCtrl.text.trim(),
            'status': _status,
            'priority': _priority,
            'timeline': timeline,
            'project_manager': _managerId,
            'project_lead': _leadId,
            'default_coordinator': _coordinatorId,
            if (_reasonCtrl.text.trim().isNotEmpty)
              'reason': _reasonCtrl.text.trim(),
          },
          files: files,
        );
      } else {
        await api.create(
          {
            'project_name': _nameCtrl.text.trim(),
            if (_displayCode().isNotEmpty) 'code': _displayCode(),
            'description': _descCtrl.text.trim(),
            'site': _siteId,
            'status': _status,
            'priority': _priority,
            'timeline': timeline,
            'project_manager': _managerId,
            'project_lead': _leadId,
            if (_coordinatorId != null) 'default_coordinator': _coordinatorId,
          },
          files: files,
        );
      }
      if (!mounted) return;
      await showSavedConfirmation(
        context,
        widget.isEdit ? 'Project updated' : 'Project created',
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
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Edit project' : 'Add Project'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: AppTheme.formPadding,
                children: [
                  if (_error != null) ...[
                    ErrorBanner(message: _error!, onRetry: _bootstrap),
                    const SizedBox(height: 12),
                  ],
                  if (_fieldErrors.hasErrors)
                    ValidationSummaryBanner(messages: _fieldErrors.messages),
                  if (!widget.isEdit) ...[
                    const Text(
                      'Plan better, Track smarter.',
                      style: TextStyle(color: AppTheme.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    const _AddProjectSteps(),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Project name *',
                      hintText: 'e.g. Green Valley Residences — Phase 2',
                    ),
                    onChanged: (_) => _onProjectNameChanged(),
                    validator: (v) {
                      return FormValidators.minLength(v, 2, 'Project name') ??
                          FormValidators.maxLength(v, 200, 'Project name');
                    },
                  ),
                  const SizedBox(height: 12),
                  if (!widget.isEdit)
                    PickerField(
                      label: 'Site',
                      required: true,
                      valueLabel: _siteLabel,
                      errorText: _fieldErrors['site'],
                      onTap: () async {
                        final options = await loadSiteOptions(context);
                        if (!mounted) return;
                        if (!context.mounted) return;
                        final picked = await showOptionPicker(
                          context,
                          title: 'Select site',
                          options: options,
                          selected: _siteId,
                          emptyMessage: 'No sites available. Assign sites to your user or create a site in Settings.',
                        );
                        if (picked == null) return;
                        setState(() {
                          _siteId = picked.value;
                          _siteLabel = picked.label;
                          _siteRaw = picked.raw;
                          _serverCode = null;
                          _fieldErrors.set('site', null);
                        });
                        _scheduleGeneratedCode();
                      },
                    )
                  else
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Site'),
                      child: Text(_siteLabel.isEmpty ? '—' : _siteLabel),
                    ),
                  const SizedBox(height: 12),
                  _projectCodeBox(),
                  const SizedBox(height: 12),
                  AppDropdownFormField<String>(
                    key: ValueKey('priority-$_priority'),
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Priority *'),
                    items: [
                      for (final p in PmsConstants.priorities)
                        DropdownMenuItem(value: p.$1, child: Text(p.$2)),
                    ],
                    onChanged: (v) => _setPriority(v ?? _priority),
                  ),
                  const SizedBox(height: 12),
                  _personField(
                    label: 'Project lead',
                    required: !widget.isEdit,
                    valueLabel: _leadLabel,
                    errorKey: 'lead',
                    selected: _leadId,
                    onPicked: (picked) {
                      _leadId = picked.value;
                      _leadLabel = picked.label;
                    },
                  ),
                  const SizedBox(height: 12),
                  _personField(
                    label: 'Project manager',
                    required: !widget.isEdit,
                    valueLabel: _managerLabel,
                    errorKey: 'manager',
                    selected: _managerId,
                    onPicked: (picked) {
                      final followCoordinator =
                          _coordinatorId == null || _coordinatorId == _managerId;
                      _managerId = picked.value;
                      _managerLabel = picked.label;
                      if (followCoordinator) {
                        _coordinatorId = picked.value;
                        _coordinatorLabel = picked.label;
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _personField(
                    label: 'Default coordinator',
                    required: false,
                    valueLabel: _coordinatorLabel,
                    errorKey: 'coordinator',
                    selected: _coordinatorId,
                    onPicked: (picked) {
                      _coordinatorId = picked.value;
                      _coordinatorLabel = picked.label;
                    },
                  ),
                  if (widget.isEdit) ...[
                    const SizedBox(height: 12),
                    AppDropdownFormField<String>(
                      key: ValueKey('status-$_status'),
                      initialValue: _status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: [
                        for (final s in [
                          ...PmsConstants.projectStatuses,
                          if (_status == 'archived') ('archived', 'Archived'),
                        ])
                          DropdownMenuItem(value: s.$1, child: Text(s.$2)),
                      ],
                      onChanged: (v) => setState(() => _status = v ?? _status),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: PickerField(
                          label: 'Start date',
                          required: !widget.isEdit,
                          valueLabel: _startDate == null
                              ? ''
                              : formatDate(_startDate!.toIso8601String()),
                          errorText: _fieldErrors['startDate'],
                          onTap: () async {
                            final picked = await _pickDate(_startDate);
                            if (picked == null || !mounted) return;
                            _fieldErrors.set('startDate', null);
                            setState(() => _startDate = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PickerField(
                          label: 'End date',
                          required: !widget.isEdit,
                          valueLabel: _endDate == null
                              ? ''
                              : formatDate(_endDate!.toIso8601String()),
                          errorText: _fieldErrors['endDate'],
                          onTap: () async {
                            final picked = await _pickDate(_endDate);
                            if (picked == null || !mounted) return;
                            _fieldErrors.set('endDate', null);
                            setState(() => _endDate = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: PickerField(
                          label: 'Actual start',
                          valueLabel: _actualStart == null
                              ? ''
                              : formatDate(_actualStart!.toIso8601String()),
                          onTap: () async {
                            final picked = await _pickDate(_actualStart);
                            if (picked == null || !mounted) return;
                            setState(() => _actualStart = picked);
                          },
                        ),
                      ),
                      if (_actualStart != null)
                        IconButton(
                          tooltip: 'Clear actual start',
                          onPressed: () => setState(() => _actualStart = null),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PickerField(
                          label: 'Actual end',
                          valueLabel: _actualEnd == null
                              ? ''
                              : formatDate(_actualEnd!.toIso8601String()),
                          errorText: _fieldErrors['actualEnd'],
                          onTap: () async {
                            final picked = await _pickDate(_actualEnd);
                            if (picked == null || !mounted) return;
                            _fieldErrors.set('actualEnd', null);
                            setState(() => _actualEnd = picked);
                          },
                        ),
                      ),
                      if (_actualEnd != null)
                        IconButton(
                          tooltip: 'Clear actual end',
                          onPressed: () => setState(() => _actualEnd = null),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mark as High Priority'),
                    value: _priority == 'high',
                    onChanged: (on) => setState(() {
                      if (on) {
                        if (_priority != 'high') _priorityOff = _priority;
                        _priority = 'high';
                      } else {
                        _priority = _priorityOff == 'high' ? 'medium' : _priorityOff;
                      }
                    }),
                  ),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Scope of work, towers/blocks, client notes...',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Photos, videos and attachments',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (widget.isEdit && _loaded != null)
                    MediaListPanel(
                      entity: _loaded!,
                      busy: _saving,
                      onRemove: _removeExistingMedia,
                    ),
                  MediaPickerBar(
                    files: _pendingMedia,
                    onChanged: (files) => setState(() => _pendingMedia = files),
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : () => context.pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                          onPressed: _saving ? null : _submit,
                          child: _saving
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(widget.isEdit ? 'Save changes' : 'Create Project'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _projectCodeBox() {
    if (widget.isEdit) {
      return TextFormField(
        controller: _codeCtrl,
        decoration: const InputDecoration(
          labelText: 'Project code *',
          prefixIcon: Icon(Icons.tag, size: 18),
        ),
        textCapitalization: TextCapitalization.characters,
        validator: (v) =>
            FormValidators.requiredField(v, 'Project code') ??
            FormValidators.maxLength(v, 50, 'Project code'),
      );
    }
    final code = _displayCode();
    final hasCode = code.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Project code *',
            filled: true,
            fillColor: const Color(0xFFF3F4F6),
            prefixIcon: const Icon(Icons.tag, size: 18),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                label: const Text('Auto-generated'),
                labelStyle: const TextStyle(
                  color: Color(0xFF6D28D9),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                backgroundColor: const Color(0xFFEDE9FE),
                visualDensity: VisualDensity.compact,
                side: BorderSide.none,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          child: Text(
            hasCode ? code : 'Generated after project name & site selection',
            style: TextStyle(
              color: hasCode ? AppTheme.primary : AppTheme.muted,
              fontWeight: hasCode ? FontWeight.w700 : FontWeight.w500,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: AppTheme.muted),
            SizedBox(width: 4),
            Expanded(
              child: Text(
                'Project code will be generated automatically',
                style: TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _personField({
    required String label,
    required bool required,
    required String valueLabel,
    required String errorKey,
    required String? selected,
    required void Function(OptionItem picked) onPicked,
  }) {
    final needsSite = !widget.isEdit && (_siteId == null || _siteId!.isEmpty);
    return PickerField(
      label: label,
      required: required,
      valueLabel: needsSite ? 'Select site first' : valueLabel,
      errorText: _fieldErrors[errorKey],
      onTap: () async {
        if (needsSite) {
          showPmsSnack(context, 'Select site first', error: true);
          return;
        }
        final picked = await showOptionPicker(
          context,
          title: label,
          options: _users,
          selected: selected,
        );
        if (picked == null) return;
        setState(() {
          onPicked(picked);
          _fieldErrors.set(errorKey, null);
        });
      },
    );
  }
}

class _AddProjectSteps extends StatelessWidget {
  const _AddProjectSteps();

  @override
  Widget build(BuildContext context) {
    const steps = [
      ('1', 'Basics', 'Project details'),
      ('2', 'Team & Roles', 'Lead & Manager'),
      ('3', 'Schedule', 'Start & end date'),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: i == 0 ? AppTheme.accent : const Color(0xFFE5E7EB),
                      child: Text(
                        steps[i].$1,
                        style: TextStyle(
                          fontSize: 11,
                          color: i == 0 ? Colors.white : AppTheme.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        steps[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  steps[i].$3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppTheme.muted),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: i == 0 ? AppTheme.accent : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

String _lettersOnly(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();

String _projectNamePrefix(String projectName) {
  final letters = _lettersOnly(projectName);
  if (letters.isEmpty) return 'PRJ';
  return letters.substring(0, letters.length >= 3 ? 3 : letters.length).padRight(3, 'X');
}

String _siteCodePart(Map<String, dynamic>? site) {
  var raw = '';
  for (final key in ['code', 'site_name', 'name']) {
    final value = site?[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) {
      raw = value.toUpperCase();
      break;
    }
  }
  final alnum = raw.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (alnum.isEmpty) return 'STE';
  if (alnum.length <= 6) return alnum;
  final letters = _lettersOnly(raw);
  final base = letters.isEmpty ? alnum : letters;
  return base.substring(0, base.length >= 3 ? 3 : base.length).padRight(3, 'X');
}

String _buildProjectCode(String projectName, Map<String, dynamic>? site, int sequence) {
  final seq = sequence < 1 ? 1 : sequence;
  return '${_projectNamePrefix(projectName)}-${_siteCodePart(site)}-${seq.toString().padLeft(3, '0')}';
}
