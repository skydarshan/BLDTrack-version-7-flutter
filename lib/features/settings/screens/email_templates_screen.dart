import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/form_validation_helpers.dart';
import '../../auth/providers/auth_provider.dart';
import '../../org/org_session.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../services/settings_apis.dart';
import '../utils/permissions.dart';

const _moduleOrder = ['procurement', 'inventory', 'project_management'];

const _moduleLabels = {
  'procurement': 'Procurement',
  'inventory': 'Inventory',
  'project_management': 'Project Management',
};

const _sampleValues = {
  'organisationName': 'Acme Corp',
  'recipientName': 'Priya Sharma',
  'firstName': 'Priya',
  'title': 'Task assigned',
  'message': 'Please review the update below.',
  'projectName': 'Tower A',
  'siteName': 'Site 1',
  'taskTitle': 'Footing',
  'remarks': 'Complete by EOD.',
  'commentBody': 'Please share the latest site photos.',
  'rrNumber': '1042',
  'rrTitle': 'Cement order',
  'createdByName': 'Ravi',
  'rrDate': '21 Aug 2026',
  'recordNumber': 'INV-1042',
  'recordKind': 'Stock receipt',
  'recordDate': '21 Aug 2026',
};

String _resolveModule(Map<String, dynamic> tpl) {
  final raw = (tpl['moduleTag'] ?? tpl['module'] ?? tpl['group'] ?? '')
      .toString()
      .trim();
  final upper = raw.toUpperCase();
  if (upper == 'PROJECT_MANAGEMENT' || raw == 'pms' || raw == 'project-management') {
    return 'project_management';
  }
  if (upper == 'PROCUREMENT' || raw == 'procurement') return 'procurement';
  if (upper == 'INVENTORY' || raw == 'inventory') return 'inventory';
  final key = (tpl['key'] ?? '').toString();
  final type = (tpl['notificationType'] ?? '').toString();
  if (key.startsWith('pms.')) return 'project_management';
  if (key.startsWith('rr_') || type.contains('rr')) return 'procurement';
  if (key.startsWith('inventory_') || type.startsWith('inventory_')) return 'inventory';
  return '';
}

List<String> _placeholders(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .map((item) {
        if (item is String) return item.trim();
        if (item is Map) {
          return (item['name'] ?? item['key'] ?? '').toString().trim();
        }
        return item.toString().trim();
      })
      .where((name) => name.isNotEmpty)
      .toList();
}

String _stripHtml(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _renderTemplate(String template, Map<String, String> samples) {
  var out = template;
  samples.forEach((key, value) {
    out = out.replaceAll(
      RegExp('\\{\\{\\s*${RegExp.escape(key)}\\s*\\}\\}'),
      value,
    );
  });
  return out;
}

class EmailTemplateDraft {
  EmailTemplateDraft({
    required this.key,
    required this.module,
    required this.name,
    required this.description,
    required this.subject,
    required this.greeting,
    required this.body,
    required this.footer,
    required this.placeholders,
    required this.ctaLabel,
    required this.lockedCtaNote,
    required this.isCustomized,
  });

  final String key;
  final String module;
  final String name;
  final String description;
  final String subject;
  final String greeting;
  final String body;
  final String footer;
  final List<String> placeholders;
  final String ctaLabel;
  final String lockedCtaNote;
  final bool isCustomized;

  factory EmailTemplateDraft.fromJson(Map<String, dynamic> tpl) {
    final module = _resolveModule(tpl);
    final storedCta = (tpl['ctaLabel'] ?? '').toString().trim();
    return EmailTemplateDraft(
      key: (tpl['key'] ?? '').toString(),
      module: module,
      name: (tpl['name'] ?? 'Template').toString(),
      description: (tpl['description'] ?? '').toString(),
      subject: (tpl['subject'] ?? '').toString(),
      greeting: (tpl['greeting'] ?? '').toString(),
      body: (tpl['body'] ?? tpl['intro'] ?? '').toString(),
      footer: (tpl['footer'] ?? '').toString(),
      placeholders: _placeholders(tpl['placeholders']),
      ctaLabel: storedCta.isNotEmpty ? storedCta : _defaultCta(module, tpl),
      lockedCtaNote: (tpl['lockedCtaNote'] ?? '').toString(),
      isCustomized: tpl['isCustomized'] == true,
    );
  }

  static String _defaultCta(String module, Map<String, dynamic> tpl) {
    if (module == 'procurement') return 'Review & approve';
    if (module == 'inventory') return 'Open inventory';
    final type = (tpl['notificationType'] ?? tpl['key'] ?? '').toString();
    if (type.contains('project_completed') ||
        type.contains('project_manager') ||
        type.contains('project_lead')) {
      return 'Open project';
    }
    return 'Open task';
  }

  List<String> get lockedRows {
    if (module == 'procurement') {
      return const ['RR number, title, and site', 'Created by and date'];
    }
    if (module == 'inventory') {
      return const ['Record number and site', 'Created by and date'];
    }
    return const ['Project / site / task rows'];
  }
}

class EmailTemplatesScreen extends StatefulWidget {
  const EmailTemplatesScreen({super.key});

  @override
  State<EmailTemplatesScreen> createState() => _EmailTemplatesScreenState();
}

class _EmailTemplatesScreenState extends State<EmailTemplatesScreen> {
  bool _loading = true;
  String? _error;
  String _module = 'procurement';
  List<String> _modules = const ['procurement', 'inventory'];
  List<EmailTemplateDraft> _templates = const [];

  Permissions get _perms => Permissions(context.read<AuthProvider>().user);

  bool get _canUpdate =>
      _perms.can('organization', 'update') || _perms.isSuperAdmin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  void _bootstrap() {
    final org = context.read<OrgSession>();
    final enabled = org.enabledWorkspaces.where(_moduleOrder.contains).toList();
    final modules = enabled.isEmpty
        ? const ['procurement', 'inventory']
        : _moduleOrder.where(enabled.contains).toList();
    final current = org.workspace;
    setState(() {
      _modules = modules;
      _module = modules.contains(current) ? current : modules.first;
    });
    _load();
  }

  Future<void> _load() async {
    if (!_canUpdate) {
      setState(() {
        _loading = false;
        _error = null;
        _templates = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await context.read<SettingsApis>().listEmailTemplates(_module);
      if (!mounted) return;
      final drafts = rows
          .map(EmailTemplateDraft.fromJson)
          .where((tpl) => tpl.key.isNotEmpty)
          .where((tpl) => tpl.module.isEmpty || tpl.module == _module)
          .toList();
      setState(() {
        _templates = drafts;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _templates = const [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _templates = const [];
        _loading = false;
      });
    }
  }

  Future<void> _open(EmailTemplateDraft template) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EmailTemplateEditorScreen(initial: template),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final label = _moduleLabels[_module] ?? 'this module';
    return Scaffold(
      appBar: AppBar(title: const Text('Email templates')),
      body: !_canUpdate
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'You do not have permission to edit email templates.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: AppTheme.chipRowPadding,
                  child: Row(
                    children: [
                      for (final module in _modules)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_moduleLabels[module] ?? module),
                            selected: _module == module,
                            onSelected: _loading
                                ? null
                                : (_) {
                                    if (_module == module) return;
                                    setState(() => _module = module);
                                    _load();
                                  },
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: AppTheme.listPadding,
                            children: [
                              if (_error != null)
                                ErrorBanner(message: _error!, onRetry: _load)
                              else if (_templates.isEmpty)
                                EmptyState(
                                  message: 'No $label email templates yet.',
                                )
                              else
                                ..._templates.map(_tile),
                            ],
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _tile(EmailTemplateDraft template) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(template.name),
        subtitle: Text(
          template.description.isNotEmpty ? template.description : template.key,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _StatusChip(customized: template.isCustomized),
        onTap: () => _open(template),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.customized, this.dirty = false});

  final bool customized;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    final label = dirty ? 'UNSAVED' : (customized ? 'CUSTOM' : 'DEFAULT');
    final color = dirty
        ? AppTheme.warning
        : (customized ? AppTheme.brand : AppTheme.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.softBg(color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class EmailTemplateEditorScreen extends StatefulWidget {
  const EmailTemplateEditorScreen({super.key, required this.initial});

  final EmailTemplateDraft initial;

  @override
  State<EmailTemplateEditorScreen> createState() => _EmailTemplateEditorScreenState();
}

class _EmailTemplateEditorScreenState extends State<EmailTemplateEditorScreen> {
  final _subject = TextEditingController();
  final _greeting = TextEditingController();
  final _body = TextEditingController();
  final _footer = TextEditingController();
  final _subjectFocus = FocusNode();
  final _greetingFocus = FocusNode();
  final _bodyFocus = FocusNode();
  final _footerFocus = FocusNode();
  final _fieldErrors = FieldErrors();

  late EmailTemplateDraft _draft;
  String _activeField = 'body';
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  bool _forcePop = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _apply(_draft);
    for (final node in [_subjectFocus, _greetingFocus, _bodyFocus, _footerFocus]) {
      node.addListener(_trackFocus);
    }
    for (final controller in [_subject, _greeting, _body, _footer]) {
      controller.addListener(_onEdit);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final node in [_subjectFocus, _greetingFocus, _bodyFocus, _footerFocus]) {
      node.removeListener(_trackFocus);
      node.dispose();
    }
    for (final controller in [_subject, _greeting, _body, _footer]) {
      controller.removeListener(_onEdit);
      controller.dispose();
    }
    super.dispose();
  }

  void _trackFocus() {
    if (_subjectFocus.hasFocus) _activeField = 'subject';
    if (_greetingFocus.hasFocus) _activeField = 'greeting';
    if (_bodyFocus.hasFocus) _activeField = 'body';
    if (_footerFocus.hasFocus) _activeField = 'footer';
  }

  void _onEdit() {
    if (mounted) setState(() {});
  }

  bool get _dirty =>
      _subject.text != _draft.subject ||
      _greeting.text != _draft.greeting ||
      _body.text != _draft.body ||
      _footer.text != _draft.footer;

  void _apply(EmailTemplateDraft draft) {
    _draft = draft;
    _subject.text = draft.subject;
    _greeting.text = draft.greeting;
    _body.text = draft.body;
    _footer.text = draft.footer;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<SettingsApis>().getEmailTemplate(_draft.key);
      if (!mounted) return;
      if (data.isNotEmpty) _apply(EmailTemplateDraft.fromJson(data));
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

  Map<String, String> _samples() {
    final orgName =
        context.read<OrgSession>().organization?['name']?.toString().trim() ?? '';
    return {
      ..._sampleValues,
      if (orgName.isNotEmpty) 'organisationName': orgName,
    };
  }

  void _insertPlaceholder(String name) {
    final token = '{{$name}}';
    final controller = switch (_activeField) {
      'subject' => _subject,
      'greeting' => _greeting,
      'footer' => _footer,
      _ => _body,
    };
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final next = text.replaceRange(start, end, token);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
  }

  bool _validate() {
    _fieldErrors.clear();
    if (_subject.text.trim().isEmpty) {
      _fieldErrors.set('subject', 'Subject is required');
    } else if (_subject.text.length > 300) {
      _fieldErrors.set('subject', 'Max 300 characters');
    }
    if (_greeting.text.trim().isEmpty) {
      _fieldErrors.set('greeting', 'Greeting is required');
    } else if (_greeting.text.length > 300) {
      _fieldErrors.set('greeting', 'Max 300 characters');
    }
    if (_stripHtml(_body.text).isEmpty) {
      _fieldErrors.set('body', 'Body is required');
    } else if (_body.text.length > 5000) {
      _fieldErrors.set('body', 'Max 5000 characters');
    }
    if (_footer.text.length > 1000) {
      _fieldErrors.set('footer', 'Max 1000 characters');
    }
    setState(() {});
    if (_fieldErrors.hasErrors) {
      showPmsSnack(context, _fieldErrors.messages.first, error: true);
    }
    return !_fieldErrors.hasErrors;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _busy = true);
    try {
      final data = await context.read<SettingsApis>().updateEmailTemplate(
        _draft.key,
        {
          'subject': _subject.text.trim(),
          'greeting': _greeting.text.trim(),
          'body': _body.text.trim(),
          'footer': _footer.text,
        },
      );
      if (!mounted) return;
      if (data.isNotEmpty) {
        _apply(EmailTemplateDraft.fromJson(data));
      } else {
        _draft = EmailTemplateDraft(
          key: _draft.key,
          module: _draft.module,
          name: _draft.name,
          description: _draft.description,
          subject: _subject.text.trim(),
          greeting: _greeting.text.trim(),
          body: _body.text.trim(),
          footer: _footer.text,
          placeholders: _draft.placeholders,
          ctaLabel: _draft.ctaLabel,
          lockedCtaNote: _draft.lockedCtaNote,
          isCustomized: true,
        );
      }
      _changed = true;
      setState(() {});
      await showSavedConfirmation(context, 'Saved "${_draft.name}" template');
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      _fieldErrors.merge(apiFieldErrors(e));
      setState(() {});
      showPmsSnack(context, formatApiErrorSummary(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset template?'),
        content: const Text('Reset this template to the system default?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final data = await context.read<SettingsApis>().resetEmailTemplate(_draft.key);
      if (!mounted) return;
      if (data.isNotEmpty) _apply(EmailTemplateDraft.fromJson(data));
      _fieldErrors.clear();
      _changed = true;
      setState(() {});
      showPmsSnack(context, 'Template reset to default');
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _maybePop() async {
    if (_forcePop) return;
    if (_dirty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('You have unsaved changes to this template.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _forcePop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(_changed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final samples = _samples();
    final previewSubject = _renderTemplate(_subject.text, samples);
    final previewGreeting = _renderTemplate(_greeting.text, samples);
    final previewBody = _stripHtml(_renderTemplate(_body.text, samples));
    final previewFooter = _renderTemplate(_footer.text, samples);
    final htmlBody = RegExp(r'<[a-z][\s\S]*>', caseSensitive: false).hasMatch(_body.text);

    return PopScope(
      canPop: !_dirty || _forcePop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _forcePop) return;
        _maybePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_draft.name),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _busy ? null : _maybePop,
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: AppTheme.formPadding,
                children: [
                  if (_error != null) ...[
                    ErrorBanner(message: _error!, onRetry: _load),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      _StatusChip(customized: _draft.isCustomized, dirty: _dirty),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _draft.description.isNotEmpty ? _draft.description : _draft.key,
                          style: const TextStyle(color: AppTheme.muted),
                        ),
                      ),
                    ],
                  ),
                  if (_draft.lockedCtaNote.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Card(
                      margin: EdgeInsets.zero,
                      color: AppTheme.brandLight,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'System CTA',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(_draft.lockedCtaNote),
                            const SizedBox(height: 8),
                            Text(
                              '${_draft.ctaLabel} →',
                              style: const TextStyle(
                                color: AppTheme.brand,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_draft.placeholders.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Placeholders — tap to insert into the focused field',
                      style: TextStyle(color: AppTheme.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final name in _draft.placeholders)
                          ActionChip(
                            label: Text('{{$name}}'),
                            onPressed: _busy ? null : () => _insertPlaceholder(name),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_fieldErrors.hasErrors)
                    ValidationSummaryBanner(messages: _fieldErrors.messages),
                  TextFormField(
                    controller: _subject,
                    focusNode: _subjectFocus,
                    enabled: !_busy,
                    maxLength: 300,
                    decoration: InputDecoration(
                      labelText: 'Subject *',
                      errorText: _fieldErrors['subject'],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _greeting,
                    focusNode: _greetingFocus,
                    enabled: !_busy,
                    maxLength: 300,
                    decoration: InputDecoration(
                      labelText: 'Greeting *',
                      errorText: _fieldErrors['greeting'],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _body,
                    focusNode: _bodyFocus,
                    enabled: !_busy,
                    minLines: 6,
                    maxLines: 14,
                    maxLength: 5000,
                    decoration: InputDecoration(
                      labelText: 'Body *',
                      alignLabelWithHint: true,
                      errorText: _fieldErrors['body'],
                      helperText: htmlBody
                          ? 'This body uses formatted text. Keep the tags if you edit them.'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _footer,
                    focusNode: _footerFocus,
                    enabled: !_busy,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 1000,
                    decoration: InputDecoration(
                      labelText: 'Footer',
                      alignLabelWithHint: true,
                      errorText: _fieldErrors['footer'],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Preview',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sample values stand in for live data. The button and detail rows stay system-generated.',
                    style: TextStyle(color: AppTheme.muted),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            previewSubject.isEmpty ? 'Subject' : previewSubject,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Text(previewGreeting),
                          if (previewBody.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(previewBody),
                          ],
                          const SizedBox(height: 12),
                          const Text(
                            'System details (locked)',
                            style: TextStyle(
                              color: AppTheme.muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          for (final row in _draft.lockedRows)
                            Text('• $row', style: const TextStyle(color: AppTheme.muted)),
                          const SizedBox(height: 8),
                          Text(
                            '${_draft.ctaLabel} →',
                            style: const TextStyle(
                              color: AppTheme.brand,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (previewFooter.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              previewFooter,
                              style: const TextStyle(color: AppTheme.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy || !_dirty ? null : _save,
                    child: const Text('Save changes'),
                  ),
                  if (_draft.isCustomized) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy ? null : _reset,
                      child: const Text('Reset to default'),
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
      ),
    );
  }
}
