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
  DateTime? _startDate;
  DateTime? _endDate;

  String? _siteId;
  String _siteLabel = '';
  String? _managerId;
  String _managerLabel = '';
  String? _leadId;
  String _leadLabel = '';

  List<PendingFile> _files = [];
  List<OptionItem> _users = const [];
  List<OptionItem> _sites = const [];
  final _fieldErrors = FieldErrors();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
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
      if (!widget.isEdit && mounted) {
        _sites = await loadSiteOptions(context);
        if (me != null) {
          _managerId = me.id;
          _managerLabel = me.name;
          _leadId = me.id;
          _leadLabel = me.name;
        }
      }
      if (widget.isEdit) {
        final project = await api.projects.getById(widget.projectId!);
        _nameCtrl.text = project['project_name']?.toString() ?? '';
        _codeCtrl.text = project['code']?.toString() ?? '';
        _descCtrl.text = project['description']?.toString() ?? '';
        final status = project['status']?.toString();
        _status = (status == null || status == 'archived') ? 'not_started' : status;
        _priority = project['priority']?.toString() ?? 'medium';
        _siteId = idOf(project['site']);
        _siteLabel = labelOf(project['site']);
        _managerId = idOf(project['project_manager']);
        _managerLabel = labelOf(project['project_manager'], fallback: '');
        _leadId = idOf(project['project_lead']);
        _leadLabel = labelOf(project['project_lead'], fallback: '');
        final timeline = project['timeline'];
        if (timeline is Map) {
          _startDate = DateTime.tryParse('${timeline['start_date'] ?? ''}');
          _endDate = DateTime.tryParse('${timeline['end_date'] ?? ''}');
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

  Future<void> _pickDate({required bool start}) async {
    final initial = (start ? _startDate : _endDate) ?? DateTime.now();
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
        _endDate = picked;
      }
    });
  }

  String? _iso(DateTime? d) =>
      d?.toIso8601String().substring(0, 10);

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
      final api = context.read<PmsServices>().projects;
      final timeline = {
        'start_date': _iso(_startDate),
        'end_date': _iso(_endDate),
      };
      final files = _files.map((f) => f.toEntry()).toList();
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
            if (_reasonCtrl.text.trim().isNotEmpty)
              'reason': _reasonCtrl.text.trim(),
          },
          files: files,
        );
      } else {
        await api.create(
          {
            'project_name': _nameCtrl.text.trim(),
            'code': _codeCtrl.text.trim(),
            'description': _descCtrl.text.trim(),
            'site': _siteId,
            'status': _status,
            'priority': _priority,
            'timeline': timeline,
            'project_manager': _managerId,
            'project_lead': _leadId,
          },
          files: files,
        );
      }
      if (!mounted) return;
      showPmsSnack(context, widget.isEdit ? 'Project updated' : 'Project created');
      context.pop(true);
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
        title: Text(widget.isEdit ? 'Edit project' : 'New project'),
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
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Project name *'),
                    validator: (v) {
                      return FormValidators.minLength(v, 2, 'Project name') ??
                          FormValidators.maxLength(v, 200, 'Project name');
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _codeCtrl,
                    decoration: const InputDecoration(labelText: 'Code'),
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
                      label: 'Site',
                      required: true,
                      valueLabel: _siteLabel,
                      errorText: _fieldErrors['site'],
                      onTap: () async {
                        var options = _sites;
                        if (options.isEmpty) {
                          options = await loadSiteOptions(context);
                          if (mounted) setState(() => _sites = options);
                        }
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
                          _fieldErrors.set('site', null);
                        });
                      },
                    )
                  else
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Site'),
                      child: Text(_siteLabel.isEmpty ? '—' : _siteLabel),
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      for (final s in PmsConstants.projectStatuses)
                        DropdownMenuItem(value: s.$1, child: Text(s.$2)),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? _status),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: [
                      for (final p in PmsConstants.priorities)
                        DropdownMenuItem(value: p.$1, child: Text(p.$2)),
                    ],
                    onChanged: (v) => setState(() => _priority = v ?? _priority),
                  ),
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
                          label: 'End date',
                          required: !widget.isEdit,
                          valueLabel: _endDate == null
                              ? ''
                              : formatDate(_endDate!.toIso8601String()),
                          errorText: _fieldErrors['endDate'],
                          onTap: () async {
                            await _pickDate(start: false);
                            if (mounted) {
                              _fieldErrors.set('endDate', null);
                              setState(() {});
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  PickerField(
                    label: 'Project manager',
                    required: !widget.isEdit,
                    valueLabel: _managerLabel,
                    errorText: _fieldErrors['manager'],
                    onTap: () async {
                      final picked = await showOptionPicker(
                        context,
                        title: 'Project manager',
                        options: _users,
                        selected: _managerId,
                      );
                      if (picked == null) return;
                      setState(() {
                        _managerId = picked.value;
                        _managerLabel = picked.label;
                        _fieldErrors.set('manager', null);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  PickerField(
                    label: 'Project lead',
                    required: !widget.isEdit,
                    valueLabel: _leadLabel,
                    errorText: _fieldErrors['lead'],
                    onTap: () async {
                      final picked = await showOptionPicker(
                        context,
                        title: 'Project lead',
                        options: _users,
                        selected: _leadId,
                      );
                      if (picked == null) return;
                      setState(() {
                        _leadId = picked.value;
                        _leadLabel = picked.label;
                        _fieldErrors.set('lead', null);
                      });
                    },
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
                        : Text(widget.isEdit ? 'Save changes' : 'Create project'),
                  ),
                ],
              ),
            ),
    );
  }
}
