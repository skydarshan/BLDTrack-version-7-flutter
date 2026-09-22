import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../services/pms_services.dart';
import '../utils/pms_constants.dart';
import '../widgets/pms_widgets.dart';
import '../widgets/template_tree_editor.dart';

class TemplateFormScreen extends StatefulWidget {
  const TemplateFormScreen({super.key, this.templateId});

  final String? templateId;

  bool get isEdit => templateId != null && templateId!.isNotEmpty;

  @override
  State<TemplateFormScreen> createState() => _TemplateFormScreenState();
}

class _TemplateFormScreenState extends State<TemplateFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  bool _loading = false;
  bool _saving = false;
  String _scope = 'organization';
  List<Map<String, dynamic>> _tasks = [emptyTemplateTaskNode()];
  String? _tasksError;

  @override
  void initState() {
    super.initState();
    if (widget.isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tpl =
          await context.read<PmsServices>().templates.getById(widget.templateId!);
      if (!mounted) return;
      _nameCtrl.text = tpl['name']?.toString() ?? '';
      _descCtrl.text = tpl['description']?.toString() ?? '';
      _scope = tpl['scope']?.toString() ?? 'organization';
      _tasks = mapTemplateTasksFromApi(tpl['tasks']);
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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final serialized = serializeTemplateTasks(_tasks);
    if (serialized.isEmpty) {
      setState(() => _tasksError = 'Add at least one task with a title');
      return;
    }
    setState(() {
      _tasksError = null;
      _saving = true;
    });
    try {
      final api = context.read<PmsServices>().templates;
      if (widget.isEdit) {
        await api.update(widget.templateId!, {
          'name': _nameCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'scope': _scope,
          'tasks': serialized,
        });
      } else {
        await api.create({
          'name': _nameCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'scope': _scope,
          'tasks': serialized,
        });
      }
      if (!mounted) return;
      showPmsSnack(
        context,
        widget.isEdit ? 'Template updated' : 'Template created',
      );
      context.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Edit template' : 'New template'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: AppTheme.formPadding,
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name *'),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.length < 2) return 'Min 2 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _scope,
                    decoration: const InputDecoration(labelText: 'Scope'),
                    items: [
                      for (final s in PmsConstants.templateScopes)
                        DropdownMenuItem(value: s.$1, child: Text(s.$2)),
                    ],
                    onChanged: (v) => setState(() => _scope = v ?? _scope),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Task tree',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  if (_tasksError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _tasksError!,
                      style: const TextStyle(color: Color(0xFFDC2626)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TemplateTreeEditor(
                    tasks: _tasks,
                    onChanged: (v) => setState(() {
                      _tasks = v;
                      _tasksError = null;
                    }),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.isEdit ? 'Save template' : 'Create template',
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
