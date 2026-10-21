import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/modern_widgets.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/utils/share_bytes.dart';
import '../services/dpr_api.dart';
import '../services/pms_services.dart';
import '../utils/dpr_format.dart';
import '../widgets/media_widgets.dart';
import '../widgets/pms_widgets.dart';

class DprDetailScreen extends StatefulWidget {
  const DprDetailScreen({super.key, required this.reportId});

  final String reportId;

  @override
  State<DprDetailScreen> createState() => _DprDetailScreenState();
}

class _DprDetailScreenState extends State<DprDetailScreen> {
  bool _loading = true;
  String? _error;
  DprDetail? _detail;
  bool _busy = false;
  bool _changed = false;

  List<Map<String, dynamic>> get _majorHistory {
    const major = {
      'dpr_created',
      'dpr_submitted',
      'dpr_submitted_auto_approved',
      'dpr_step_approved',
      'dpr_approved',
      'dpr_revision_requested',
    };
    final rows = (_detail?.history ?? const <Map<String, dynamic>>[])
        .where((h) => major.contains(h['action']?.toString()))
        .toList();
    rows.sort((a, b) {
      final at = parseApiDate(a['timestamp'] ?? a['createdAt']);
      final bt = parseApiDate(b['timestamp'] ?? b['createdAt']);
      if (at == null && bt == null) return 0;
      if (at == null) return -1;
      if (bt == null) return 1;
      return at.compareTo(bt);
    });
    return rows;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await context.read<PmsServices>().dpr.getById(widget.reportId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
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

  Map<String, dynamic>? get _report => _detail?.report;

  Future<void> _delete() async {
    final report = _report;
    if (report == null || report['status'] != 'draft') return;
    final ok = await confirmAction(
      context,
      title: 'Delete draft',
      message: 'Delete this draft report permanently?',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<PmsServices>().dpr.delete(widget.reportId);
      if (!mounted) return;
      showPmsSnack(context, 'Draft deleted');
      context.pop(true);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final remarks = await _askRemarks(required: false, title: 'Approve report');
    if (remarks == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await context.read<PmsServices>().dpr.approve(widget.reportId, remarks: remarks);
      if (!mounted) return;
      _changed = true;
      final approval = updated['approval'];
      final steps = approval is Map
          ? ((approval['required_steps'] as num?)?.toInt() ?? (approval['steps'] as num?)?.toInt() ?? 0)
          : 0;
      final stillPending = updated['status']?.toString() == 'pending';
      showPmsSnack(
        context,
        stillPending && steps == 2 ? 'Sent to final approval' : 'Report approved',
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revise() async {
    final remarks = await _askRemarks(required: true, title: 'Send back');
    if (remarks == null || remarks.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<PmsServices>().dpr.revise(widget.reportId, remarks: remarks.trim());
      if (!mounted) return;
      _changed = true;
      showPmsSnack(context, 'Sent back for revision');
      await _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askRemarks({required bool required, required String title}) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: required ? 'Remarks *' : 'Remarks',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (required && ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _exportPdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await context.read<PmsServices>().dpr.exportPdf(widget.reportId);
      final site = dprSiteLabel(_report?['site']).replaceAll(RegExp(r'\s+'), '-');
      await shareDownloadedBytes(
        bytes: bytes,
        filename: 'DPR-$site-${apiDay(DateTime.now())}.pdf',
        text: 'Daily progress report',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      final message = e.statusCode == 503
          ? 'PDF export is temporarily unavailable. Contact your administrator.'
          : e.message;
      showPmsSnack(context, message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final status = report?['status']?.toString();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.pop(_changed);
      },
      child: Scaffold(
        appBar: ModernAppBar(
          title: 'Daily report',
          actions: [
            if (report != null && status == 'approved')
              PressScale(
                child: IconButton(
                  tooltip: 'Export PDF',
                  onPressed: _busy ? null : _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
              ),
            if (report != null && canDpr(context, 'update') && isDprEditable(status))
              PressScale(
                child: IconButton(
                  tooltip: 'Edit',
                  onPressed: () async {
                    final changed = await context.push('/pms/dpr/${widget.reportId}/edit');
                    if (changed == true) {
                      _changed = true;
                      await _load();
                    }
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Padding(
                    padding: AppTheme.pagePadding,
                    child: SoftAppear(
                      child: ErrorBanner(message: _error!, onRetry: _load),
                    ),
                  )
                : report == null
                    ? const StaggeredEntrance(
                        maxIndex: 0,
                        child: EntranceItem(
                          index: 0,
                          child: EmptyState(message: 'Report not found'),
                        ),
                      )
                    : _content(report),
      ),
    );
  }

  Widget _content(Map<String, dynamic> report) {
    final status = report['status']?.toString();
    final weather = report['weather'] is Map
        ? Map<String, dynamic>.from(report['weather'] as Map)
        : const <String, dynamic>{};
    final safety = report['safety'] is Map
        ? Map<String, dynamic>.from(report['safety'] as Map)
        : const <String, dynamic>{};
    final approval = report['approval'] is Map
        ? Map<String, dynamic>.from(report['approval'] as Map)
        : const <String, dynamic>{};
    final remarks = approval['remarks']?.toString() ?? '';

    return StaggeredEntrance(
      maxIndex: 6,
      slide: 16,
      itemMs: 380,
      stepMs: 40,
      scaleFrom: 0.97,
      child: ListView(
      padding: AppTheme.pagePadding,
      children: [
        EntranceItem(
          index: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
        Row(
          children: [
            Expanded(
              child: Text(
                dprSiteLabel(report['site']),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            StatusChip(status: status, label: dprStatusLabel(status)),
          ],
        ),
        if (approvalStepLabel(report) != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(approvalStepLabel(report)!, style: const TextStyle(color: AppTheme.muted)),
          ),
        const SizedBox(height: 6),
        Text(formatDprDate(report['report_date']), style: const TextStyle(color: AppTheme.muted)),
        if (report['is_backdated'] == true)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Backfilled'),
          ),
        if (status == 'revision_requested' && remarks.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Material(
            color: const Color(0xFFFFF1F0),
            borderRadius: BorderRadius.circular(12),
            child: Padding(padding: const EdgeInsets.all(12), child: Text(remarks)),
          ),
        ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        EntranceItem(index: 1, child: _section('Details', [
          _row('Project', labelOf(report['project'], fallback: '—')),
          _row('Prepared by', personName(report['prepared_by'] ?? report['created_by'])),
          _row('Filed', report['submitted_at'] == null ? '—' : formatDprDateTime(report['submitted_at'])),
        ])),
        EntranceItem(index: 2, child: _section('Weather', [
          _row('Condition', dprWeatherLabels[weather['condition']] ?? '—'),
          _row('Temperature', weather['temperature_c'] == null ? '—' : '${weather['temperature_c']} °C'),
          _row('Remarks', _text(weather['remarks'])),
        ])),
        EntranceItem(index: 3, child: _section('Work performed', [
          Text(_text(report['work_performed'])),
        ])),
        EntranceItem(index: 4, child: _lines(
          'Equipment',
          asMapList(report['equipment'] is List ? report['equipment'] as List : const []),
          (e) => '${e['name'] ?? '—'} · qty ${e['quantity'] ?? '—'} · ${e['hours_used'] ?? '—'} h',
        )),
        EntranceItem(index: 5, child: _lines(
          'Materials',
          asMapList(report['materials'] is List ? report['materials'] as List : const []),
          (m) =>
              '${m['name'] ?? '—'} · ${m['movement'] == 'received' ? 'Received' : 'Consumed'} · ${m['quantity'] ?? '—'} ${m['uom'] ?? ''}',
        )),
        EntranceItem(index: 6, child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
        _lines(
          'Visitors',
          asMapList(report['visitors'] is List ? report['visitors'] as List : const []),
          (v) => '${v['name'] ?? '—'} · ${v['purpose'] ?? ''}'.trim(),
        ),
        _section('Safety', [
          _row('Observations', _text(safety['observations'])),
          _row('Corrective actions', _text(safety['corrective_actions'])),
          ...asMapList(safety['incidents'] is List ? safety['incidents'] as List : const []).map(
            (i) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${dprSeverityLabels[i['severity']] ?? i['severity'] ?? 'Incident'}: ${i['description'] ?? ''}',
              ),
            ),
          ),
        ]),
        _section('Site notes', [Text(_text(report['site_notes']))]),
        _media(report),
        if (_majorHistory.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Activity', style: TextStyle(fontWeight: FontWeight.w700)),
          ..._majorHistory.map((h) {
            final note = (h['reason'] ?? h['remarks'])?.toString().trim() ?? '';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(dprActivityLabel(h['action']?.toString())),
              subtitle: Text(
                [
                  personName(h['performed_by']),
                  formatDprDateTime(h['timestamp'] ?? h['createdAt']),
                  if (note.isNotEmpty) note,
                ].where((p) => p != '—').join(' · '),
              ),
            );
          }),
        ],
        const SizedBox(height: 16),
        if (status == 'pending' && canActOnDprApproval(context, report)) ...[
          FilledButton(onPressed: _busy ? null : _approve, child: const Text('Approve')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _busy ? null : _revise, child: const Text('Send back')),
        ],
        if (status == 'draft' && canDpr(context, 'delete')) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: _busy ? null : _delete, child: const Text('Delete draft')),
        ],
        const SizedBox(height: 24),
          ],
        )),
      ],
    ),
    );
  }

  Widget _media(Map<String, dynamic> report) {
    final photos = attachmentUrlsOf(report['photos']);
    final videos = attachmentUrlsOf(report['videos']);
    final files = asMapList(report['attachments'] is List ? report['attachments'] as List : const []);
    return _section('Media', [
      Text('${photos.length} photos · ${videos.length} videos · ${files.length} files'),
      for (final url in [...photos, ...videos])
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => openAttachment(context, url),
        ),
      for (final file in files)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(file['name']?.toString().trim().isNotEmpty == true ? file['name'].toString() : 'Attachment'),
          onTap: () => openAttachment(context, file['url']?.toString() ?? ''),
        ),
    ]);
  }
}

String _text(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? '—' : text;
}

Widget _row(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(color: AppTheme.muted))),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

Widget _section(String title, List<Widget> children) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ...children,
      ],
    ),
  );
}

Widget _lines(
  String title,
  List<Map<String, dynamic>> rows,
  String Function(Map<String, dynamic>) line,
) {
  return _section(title, [
    if (rows.isEmpty) const Text('—'),
    for (final row in rows) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(line(row))),
  ]);
}
