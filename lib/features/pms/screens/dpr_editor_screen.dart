import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/modern_widgets.dart';
import '../../../core/widgets/motion.dart';
import '../services/pms_services.dart';
import '../utils/dpr_format.dart';
import '../utils/site_options.dart';
import '../widgets/media_widgets.dart';
import '../widgets/pickers.dart';
import '../widgets/pms_widgets.dart';

class DprEditorScreen extends StatefulWidget {
  const DprEditorScreen({super.key, this.reportId});

  final String? reportId;

  @override
  State<DprEditorScreen> createState() => _DprEditorScreenState();
}

class _DprEditorScreenState extends State<DprEditorScreen> {
  final _work = TextEditingController();
  final _temp = TextEditingController();
  final _weatherRemarks = TextEditingController();
  final _observations = TextEditingController();
  final _corrective = TextEditingController();
  final _notes = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _reportId;
  String _status = 'draft';
  String? _siteId;
  String _siteLabel = 'Select a site';
  String? _projectId;
  String _projectLabel = 'No project';
  String _preparedByLabel = '—';
  String _reportDateLabel = formatCalendarDate(DateTime.now());
  String _revisionRemarks = '';
  int _tab = 0;
  String _weather = 'clear';
  List<OptionItem> _sites = const [];
  List<OptionItem> _projects = const [];
  List<Map<String, dynamic>> _equipment = [];
  List<Map<String, dynamic>> _materials = [];
  List<Map<String, dynamic>> _visitors = [];
  List<Map<String, dynamic>> _incidents = [];
  List<String> _photos = [];
  List<String> _videos = [];
  List<Map<String, dynamic>> _attachments = [];
  List<PendingFile> _pending = [];

  bool get _isNew => _reportId == null;

  @override
  void initState() {
    super.initState();
    _reportId = widget.reportId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _work.dispose();
    _temp.dispose();
    _weatherRemarks.dispose();
    _observations.dispose();
    _corrective.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      _sites = await loadSiteOptions(context);
    } catch (_) {}
    if (_reportId != null) {
      await _loadReport();
    } else {
      if (_sites.length == 1) {
        _siteId = _sites.first.value;
        _siteLabel = _sites.first.label;
      }
      await _loadProjects();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await context.read<PmsServices>().dpr.getById(_reportId!);
      if (!mounted) return;
      _applyReport(detail.report);
      await _loadProjects();
      if (!mounted) return;
      setState(() => _loading = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _applyReport(Map<String, dynamic> report) {
    _reportId = idOf(report) ?? _reportId;
    _status = report['status']?.toString() ?? 'draft';
    _siteId = idOf(report['site']);
    _siteLabel = dprSiteLabel(report['site']);
    _projectId = idOf(report['project']);
    _projectLabel = labelOf(report['project'], fallback: 'No project');
    _preparedByLabel = personName(report['prepared_by'] ?? report['created_by']);
    _reportDateLabel = formatDprDate(report['report_date']);
    final approval = report['approval'];
    _revisionRemarks = report['status'] == 'revision_requested' && approval is Map
        ? (approval['remarks']?.toString() ?? '')
        : '';
    final weather = report['weather'] is Map
        ? Map<String, dynamic>.from(report['weather'] as Map)
        : const <String, dynamic>{};
    _weather = weather['condition']?.toString() ?? 'clear';
    _temp.text = weather['temperature_c']?.toString() ?? '';
    _weatherRemarks.text = weather['remarks']?.toString() ?? '';
    _work.text = report['work_performed']?.toString() ?? '';
    _notes.text = report['site_notes']?.toString() ?? '';
    final safety = report['safety'] is Map
        ? Map<String, dynamic>.from(report['safety'] as Map)
        : const <String, dynamic>{};
    _observations.text = safety['observations']?.toString() ?? '';
    _corrective.text = safety['corrective_actions']?.toString() ?? '';
    _equipment = asMapList(report['equipment'] is List ? report['equipment'] as List : const []);
    _materials = asMapList(report['materials'] is List ? report['materials'] as List : const []);
    _visitors = asMapList(report['visitors'] is List ? report['visitors'] as List : const []);
    _incidents = asMapList(safety['incidents'] is List ? safety['incidents'] as List : const []);
    _photos = attachmentUrlsOf(report['photos']);
    _videos = attachmentUrlsOf(report['videos']);
    _attachments = asMapList(report['attachments'] is List ? report['attachments'] as List : const []);
    _pending = [];
  }

  Future<void> _loadProjects() async {
    if (_siteId == null) {
      _projects = const [];
      return;
    }
    try {
      final res = await context.read<PmsServices>().projects.list({
        'site': _siteId,
        'page': 1,
        'limit': 100,
      });
      _projects = res.items
          .map((p) => OptionItem(
                value: idOf(p) ?? '',
                label: p['project_name']?.toString() ?? labelOf(p),
              ))
          .where((o) => o.value.isNotEmpty)
          .toList();
    } catch (_) {
      _projects = const [];
    }
  }

  Map<String, dynamic> _payload({bool submit = false}) {
    final temp = double.tryParse(_temp.text.trim());
    return {
      'project': (_projectId == null || _projectId!.isEmpty) ? null : _projectId,
      'weather': {
        'condition': _weather,
        'temperature_c': temp,
        'remarks': _weatherRemarks.text.trim(),
      },
      'work_performed': _work.text.trim(),
      'equipment': _equipment,
      'materials': _materials,
      'visitors': _visitors,
      'safety': {
        'incidents': _incidents,
        'observations': _observations.text.trim(),
        'corrective_actions': _corrective.text.trim(),
      },
      'site_notes': _notes.text.trim(),
      if (submit) 'remarks': '',
    };
  }

  String? _validateLines() {
    final time = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');
    for (final row in _visitors) {
      for (final key in ['time_in', 'time_out']) {
        final value = row[key]?.toString().trim() ?? '';
        if (value.isNotEmpty && !time.hasMatch(value)) {
          return 'Visitor times must be HH:MM';
        }
      }
    }
    for (final row in _equipment) {
      final hours = row['hours_used'];
      if (hours is num && hours > 24) return 'Hours used cannot exceed 24';
    }
    return null;
  }

  Future<bool> _save({bool submit = false, bool quiet = false, String remarks = ''}) async {
    if (_siteId == null || _siteId!.isEmpty) {
      if (!quiet) showPmsSnack(context, 'Site is required', error: true);
      return false;
    }
    final lineError = _validateLines();
    if (lineError != null) {
      showPmsSnack(context, lineError, error: true);
      return false;
    }
    if (submit && _work.text.trim().isEmpty) {
      showPmsSnack(context, 'Work performed is required before you can submit this report.', error: true);
      setState(() => _tab = 1);
      return false;
    }
    final existingMedia = _photos.length + _videos.length + _attachments.length;
    if (existingMedia + _pending.length > 15) {
      showPmsSnack(context, 'You can attach up to 15 files', error: true);
      return false;
    }
    setState(() => _busy = true);
    final files = _pending.map((f) => f.toEntry()).toList();
    try {
      final api = context.read<PmsServices>().dpr;
      Map<String, dynamic> saved;
      if (_isNew) {
        saved = await api.create({
          ..._payload(),
          'site': _siteId,
          'report_date': apiDay(DateTime.now()),
          if (submit) 'submit': true,
          if (submit && remarks.trim().isNotEmpty) 'remarks': remarks.trim(),
        }, files: files);
      } else if (submit) {
        await api.update(_reportId!, _payload(), files: files);
        saved = await api.submit(
          _reportId!,
          {if (remarks.trim().isNotEmpty) 'remarks': remarks.trim()},
        );
      } else {
        saved = await api.update(_reportId!, _payload(), files: files);
      }
      if (!mounted) return false;
      _applyReport(saved);
      if (!quiet) {
        showPmsSnack(context, submit ? 'Report submitted for approval' : 'Draft saved');
      }
      if (submit) {
        context.pop(true);
      } else {
        setState(() {});
      }
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 409 && _isNew && mounted) {
        await _openExisting();
      } else if (mounted) {
        showPmsSnack(context, e.message, error: true);
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _goTab(int next) async {
    if (next == _tab || _busy) return;
    if (_reportId != null) {
      final ok = await _save(quiet: true);
      if (!ok || !mounted) return;
    }
    setState(() => _tab = next);
  }

  Future<void> _submit() async {
    if (_work.text.trim().isEmpty) {
      showPmsSnack(context, 'Work performed is required before you can submit this report.', error: true);
      setState(() => _tab = 1);
      return;
    }
    final ctrl = TextEditingController();
    final remarks = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit for approval'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Remarks (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (remarks == null || !mounted) return;
    await _save(submit: true, remarks: remarks);
  }

  Future<void> _openExisting() async {
    try {
      final data = await context.read<PmsServices>().dpr.getForDate(siteId: _siteId!);
      final report = data['report'];
      final id = report is Map ? idOf(report) : null;
      if (!mounted || id == null) return;
      showPmsSnack(context, 'A report already exists. Opening it.');
      context.pushReplacement('/pms/dpr/$id');
    } catch (_) {}
  }

  Future<void> _prefill({bool replace = false}) async {
    if (_reportId == null) {
      showPmsSnack(context, 'Save the draft first', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await context.read<PmsServices>().dpr.prefillWorkSummary(
            _reportId!,
            replace: replace,
          );
      if (!mounted) return;
      if (!result.applied) {
        showPmsSnack(context, 'No task progress logged for this site on this date');
        return;
      }
      _applyReport(result.report);
      showPmsSnack(context, '${result.entryCount} entries added to work summary');
      setState(() {});
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onPrefill() async {
    if (_work.text.trim().isNotEmpty) {
      final ok = await confirmAction(
        context,
        title: 'Replace work summary',
        message: 'Replace what you have written with the task progress summary?',
        confirmLabel: 'Replace',
      );
      if (!ok || !mounted) return;
      await _prefill(replace: true);
      return;
    }
    await _prefill();
  }

  Future<void> _removeMedia(String type, String url) async {
    if (_reportId == null || url.isEmpty) return;
    setState(() => _busy = true);
    try {
      final saved = await context.read<PmsServices>().dpr.removeMedia(
            _reportId!,
            type: type,
            url: url,
          );
      if (!mounted) return;
      _applyReport(saved);
      setState(() {});
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_reportId == null || _status != 'draft' || !canDpr(context, 'delete')) return;
    final ok = await confirmAction(
      context,
      title: 'Delete draft',
      message: 'Delete this draft report permanently?',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<PmsServices>().dpr.delete(_reportId!);
      if (!mounted) return;
      showPmsSnack(context, 'Draft deleted');
      context.pop(true);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isDprEditable(_isNew ? 'draft' : _status) && !_loading) {
      return Scaffold(
        appBar: const ModernAppBar(title: 'Daily report'),
        body: StaggeredEntrance(
          maxIndex: 1,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EntranceItem(
                  index: 0,
                  child: EmptyState(message: 'This report cannot be edited.'),
                ),
                EntranceItem(
                  index: 1,
                  child: TextButton(
                    onPressed: () => context.pushReplacement('/pms/dpr/$_reportId'),
                    child: const Text('View report'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: ModernAppBar(
        title: _isNew ? 'New daily report' : 'Edit daily report',
        actions: [
          if (!_isNew && _status == 'draft' && canDpr(context, 'delete'))
            PressScale(
              child: IconButton(
                tooltip: 'Delete',
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: AppTheme.pagePadding,
                  child: ErrorBanner(message: _error!, onRetry: _loadReport),
                )
              : StaggeredEntrance(
                  replayToken: _tab,
                  maxIndex: 2,
                  slide: 16,
                  itemMs: 380,
                  stepMs: 45,
                  scaleFrom: 0.98,
                  child: ListView(
                  padding: AppTheme.pagePadding,
                  children: [
                    if (_revisionRemarks.trim().isNotEmpty)
                      EntranceItem(
                        index: 0,
                        child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('Approver feedback: $_revisionRemarks'),
                      ),
                      ),
                    EntranceItem(
                      index: 0,
                      child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final entry in const [
                            (0, 'Header'),
                            (1, 'Work'),
                            (2, 'Weather'),
                            (3, 'Equipment'),
                            (4, 'Materials'),
                            (5, 'Visitors'),
                            (6, 'Safety'),
                            (7, 'Notes'),
                            (8, 'Media'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(entry.$2),
                                selected: _tab == entry.$1,
                                onSelected: (_) => _goTab(entry.$1),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ),
                    const SizedBox(height: 12),
                    EntranceItem(
                      index: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                    if (_tab == 0) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Site'),
                      subtitle: Text(_siteLabel),
                      enabled: _isNew,
                      onTap: !_isNew
                          ? null
                          : () async {
                              final picked = await showOptionPicker(
                                context,
                                title: 'Site',
                                options: _sites,
                                selected: _siteId,
                              );
                              if (picked == null) return;
                              setState(() {
                                _siteId = picked.value;
                                _siteLabel = picked.label;
                                _projectId = null;
                                _projectLabel = 'No project';
                              });
                              await _loadProjects();
                              if (mounted) setState(() {});
                            },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Project'),
                      subtitle: Text(_projectLabel),
                      onTap: () async {
                        final picked = await showOptionPicker(
                          context,
                          title: 'Project',
                          options: [
                            const OptionItem(value: '', label: 'No project'),
                            ..._projects,
                          ],
                          selected: _projectId ?? '',
                        );
                        if (picked == null) return;
                        setState(() {
                          _projectId = picked.value.isEmpty ? null : picked.value;
                          _projectLabel = picked.label;
                        });
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Report date'),
                      subtitle: Text(_reportDateLabel),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Prepared by'),
                      subtitle: Text(_preparedByLabel),
                    ),
                    ],
                    if (_tab == 1) ...[
                    TextField(
                      controller: _work,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Work performed',
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (orgHasTaskProgress(context))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _busy ? null : _onPrefill,
                          child: const Text('Pull from task progress'),
                        ),
                      ),
                    ],
                    if (_tab == 2) ...[
                    DropdownButtonFormField<String>(
                      initialValue: dprWeatherLabels.containsKey(_weather) ? _weather : 'clear',
                      decoration: const InputDecoration(labelText: 'Weather'),
                      items: [
                        for (final entry in dprWeatherLabels.entries)
                          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                      ],
                      onChanged: (v) => setState(() => _weather = v ?? 'clear'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _temp,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
                      decoration: const InputDecoration(labelText: 'Temperature °C'),
                    ),
                    TextField(
                      controller: _weatherRemarks,
                      decoration: const InputDecoration(labelText: 'Weather remarks'),
                    ),
                    ],
                    if (_tab == 3)
                    _lineSection(
                      title: 'Equipment',
                      rows: _equipment,
                      line: (e) => '${e['name']} · ${e['quantity'] ?? '—'} · ${e['hours_used'] ?? '—'} h',
                      onAdd: () => _editEquipment(),
                      onEdit: (i) => _editEquipment(existing: _equipment[i], index: i),
                      onRemove: (i) => setState(() => _equipment.removeAt(i)),
                    ),
                    if (_tab == 4)
                    _lineSection(
                      title: 'Materials',
                      rows: _materials,
                      line: (m) =>
                          '${m['name']} · ${m['movement'] == 'received' ? 'Received' : 'Consumed'} · ${m['quantity'] ?? '—'} ${m['uom'] ?? ''}',
                      onAdd: () => _editMaterial(),
                      onEdit: (i) => _editMaterial(existing: _materials[i], index: i),
                      onRemove: (i) => setState(() => _materials.removeAt(i)),
                    ),
                    if (_tab == 5)
                    _lineSection(
                      title: 'Visitors',
                      rows: _visitors,
                      line: (v) => '${v['name']} · ${v['time_in'] ?? ''}–${v['time_out'] ?? ''}',
                      onAdd: () => _editVisitor(),
                      onEdit: (i) => _editVisitor(existing: _visitors[i], index: i),
                      onRemove: (i) => setState(() => _visitors.removeAt(i)),
                    ),
                    if (_tab == 6) ...[
                    _lineSection(
                      title: 'Safety incidents',
                      rows: _incidents,
                      line: (i) => '${dprSeverityLabels[i['severity']] ?? 'Incident'}: ${i['description']}',
                      onAdd: () => _editIncident(),
                      onEdit: (i) => _editIncident(existing: _incidents[i], index: i),
                      onRemove: (i) => setState(() => _incidents.removeAt(i)),
                    ),
                    TextField(
                      controller: _observations,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Safety observations'),
                    ),
                    TextField(
                      controller: _corrective,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Corrective actions'),
                    ),
                    ],
                    if (_tab == 7)
                    TextField(
                      controller: _notes,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(labelText: 'Site notes'),
                    ),
                    if (_tab == 8) ...[
                    const Text('Existing media', style: TextStyle(fontWeight: FontWeight.w700)),
                    for (final url in _photos)
                      _mediaTile('photo', url),
                    for (final url in _videos)
                      _mediaTile('video', url),
                    for (final file in _attachments)
                      _mediaTile('attachment', file['url']?.toString() ?? '', label: file['name']?.toString()),
                    const SizedBox(height: 8),
                    MediaPickerBar(
                      files: _pending,
                      onChanged: (files) {
                        final existing = _photos.length + _videos.length + _attachments.length;
                        if (existing + files.length > 15) {
                          showPmsSnack(context, 'You can attach up to 15 files', error: true);
                          return;
                        }
                        final tooBig = files.any((f) => f.bytes.length > 100 * 1024 * 1024);
                        if (tooBig) {
                          showPmsSnack(context, 'Each file must be 100 MB or smaller', error: true);
                          return;
                        }
                        setState(() => _pending = files);
                      },
                    ),
                    ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    EntranceItem(
                      index: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                    PressScale(
                      child: FilledButton(
                        onPressed: _busy ? null : () => _save(),
                        child: Text(_busy ? 'Saving…' : 'Save draft'),
                      ),
                    ),
                    if (canDpr(context, 'update') && canDpr(context, 'submit') == false)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'You can save this draft, but your role cannot submit it.',
                          style: TextStyle(color: AppTheme.muted),
                        ),
                      ),
                    if (canDpr(context, 'submit')) ...[
                      const SizedBox(height: 8),
                      PressScale(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _submit,
                          child: const Text('Submit for approval'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
                ),
    );
  }

  Widget _mediaTile(String type, String url, {String? label}) {
    if (url.isEmpty) return const SizedBox.shrink();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label?.trim().isNotEmpty == true ? label!.trim() : url, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => openAttachment(context, url),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _busy ? null : () => _removeMedia(type, url),
      ),
    );
  }

  Widget _lineSection({
    required String title,
    required List<Map<String, dynamic>> rows,
    required String Function(Map<String, dynamic>) line,
    required VoidCallback onAdd,
    required void Function(int index) onEdit,
    required void Function(int index) onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
            TextButton(onPressed: onAdd, child: const Text('Add')),
          ],
        ),
        if (rows.isEmpty) const Text('None', style: TextStyle(color: AppTheme.muted)),
        for (var i = 0; i < rows.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(line(rows[i])),
            onTap: () => onEdit(i),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => onRemove(i),
            ),
          ),
      ],
    );
  }

  Future<void> _editEquipment({Map<String, dynamic>? existing, int? index}) async {
    final saved = await _lineDialog(
      title: 'Equipment',
      fields: [
        _Field('name', 'Name', required: true, initial: existing?['name']?.toString()),
        _Field('quantity', 'Quantity', number: true, initial: existing?['quantity']?.toString()),
        _Field('hours_used', 'Hours used', number: true, initial: existing?['hours_used']?.toString()),
        _Field('remarks', 'Remarks', initial: existing?['remarks']?.toString()),
      ],
    );
    if (saved == null || !mounted) return;
    final row = {
      'name': saved['name'],
      'quantity': _numOrNull(saved['quantity']),
      'hours_used': _numOrNull(saved['hours_used']),
      'remarks': saved['remarks'] ?? '',
    };
    setState(() {
      if (index == null) {
        _equipment.add(row);
      } else {
        _equipment[index] = row;
      }
    });
  }

  Future<void> _editMaterial({Map<String, dynamic>? existing, int? index}) async {
    var movement = existing?['movement']?.toString() ?? 'received';
    final saved = await _lineDialog(
      title: 'Material',
      fields: [
        _Field('name', 'Name', required: true, initial: existing?['name']?.toString()),
        _Field('quantity', 'Quantity', number: true, initial: existing?['quantity']?.toString()),
        _Field('uom', 'UOM', initial: existing?['uom']?.toString()),
        _Field('remarks', 'Remarks', initial: existing?['remarks']?.toString()),
      ],
      extra: (setLocal) => DropdownButtonFormField<String>(
        initialValue: movement,
        decoration: const InputDecoration(labelText: 'Movement'),
        items: const [
          DropdownMenuItem(value: 'received', child: Text('Received')),
          DropdownMenuItem(value: 'consumed', child: Text('Consumed')),
        ],
        onChanged: (v) => setLocal(() => movement = v ?? 'received'),
      ),
    );
    if (saved == null) return;
    final row = {
      'name': saved['name'],
      'movement': movement,
      'quantity': _numOrNull(saved['quantity']),
      'uom': saved['uom'] ?? '',
      'remarks': saved['remarks'] ?? '',
    };
    setState(() {
      if (index == null) {
        _materials.add(row);
      } else {
        _materials[index] = row;
      }
    });
  }

  Future<void> _editVisitor({Map<String, dynamic>? existing, int? index}) async {
    final saved = await _lineDialog(
      title: 'Visitor',
      fields: [
        _Field('name', 'Name', required: true, initial: existing?['name']?.toString()),
        _Field('visitor_organisation', 'Organisation', initial: existing?['visitor_organisation']?.toString()),
        _Field('purpose', 'Purpose', initial: existing?['purpose']?.toString()),
        _Field('time_in', 'Time in (HH:MM)', initial: existing?['time_in']?.toString()),
        _Field('time_out', 'Time out (HH:MM)', initial: existing?['time_out']?.toString()),
      ],
    );
    if (saved == null) return;
    setState(() {
      final row = {
        'name': saved['name'],
        'visitor_organisation': saved['visitor_organisation'] ?? '',
        'purpose': saved['purpose'] ?? '',
        'time_in': saved['time_in'] ?? '',
        'time_out': saved['time_out'] ?? '',
      };
      if (index == null) {
        _visitors.add(row);
      } else {
        _visitors[index] = row;
      }
    });
  }

  Future<void> _editIncident({Map<String, dynamic>? existing, int? index}) async {
    var severity = existing?['severity']?.toString() ?? 'minor';
    final saved = await _lineDialog(
      title: 'Incident',
      fields: [
        _Field('description', 'Description', required: true, initial: existing?['description']?.toString()),
        _Field('corrective_action', 'Corrective action', initial: existing?['corrective_action']?.toString()),
      ],
      extra: (setLocal) => DropdownButtonFormField<String>(
        initialValue: severity,
        decoration: const InputDecoration(labelText: 'Severity'),
        items: [
          for (final entry in dprSeverityLabels.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (v) => setLocal(() => severity = v ?? 'minor'),
      ),
    );
    if (saved == null) return;
    final row = {
      'description': saved['description'],
      'severity': severity,
      'corrective_action': saved['corrective_action'] ?? '',
    };
    setState(() {
      if (index == null) {
        _incidents.add(row);
      } else {
        _incidents[index] = row;
      }
    });
  }

  Future<Map<String, String>?> _lineDialog({
    required String title,
    required List<_Field> fields,
    Widget Function(void Function(VoidCallback) setLocal)? extra,
  }) {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _LineEntryDialog(title: title, fields: fields, extra: extra),
    );
  }
}

class _LineEntryDialog extends StatefulWidget {
  const _LineEntryDialog({required this.title, required this.fields, this.extra});

  final String title;
  final List<_Field> fields;
  final Widget Function(void Function(VoidCallback) setLocal)? extra;

  @override
  State<_LineEntryDialog> createState() => _LineEntryDialogState();
}

class _LineEntryDialogState extends State<_LineEntryDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final field in widget.fields) field.key: TextEditingController(text: field.initial ?? ''),
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.extra != null) widget.extra!(setState),
            for (final field in widget.fields)
              TextField(
                controller: _controllers[field.key],
                keyboardType: field.number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                decoration: InputDecoration(labelText: field.required ? '${field.label} *' : field.label),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            for (final field in widget.fields) {
              if (field.required && _controllers[field.key]!.text.trim().isEmpty) return;
            }
            Navigator.pop(context, {
              for (final field in widget.fields) field.key: _controllers[field.key]!.text.trim(),
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _Field {
  const _Field(this.key, this.label, {this.required = false, this.number = false, this.initial});

  final String key;
  final String label;
  final bool required;
  final bool number;
  final String? initial;
}

num? _numOrNull(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  return num.tryParse(text);
}
