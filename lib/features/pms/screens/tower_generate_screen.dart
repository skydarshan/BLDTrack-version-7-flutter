import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/form_validation_helpers.dart';
import '../utils/structure_errors.dart';
import '../utils/structure_nodes.dart';
import '../utils/tower_generate.dart';
import '../widgets/pms_widgets.dart';

/// Bulk tower generator. Preview is required before Create writes the tower.
class TowerGenerateScreen extends StatefulWidget {
  const TowerGenerateScreen({
    super.key,
    required this.onPreview,
    required this.onCreate,
  });

  /// Preview (`preview: true`). A [StructureApiError] stays on screen unless
  /// the user has no access or the project is gone.
  final Future<Object?> Function(Map<String, dynamic> payload) onPreview;

  /// Create (`preview: false`). A map is the written plan. Null is success
  /// with no body.
  final Future<Object?> Function(Map<String, dynamic> payload) onCreate;

  @override
  State<TowerGenerateScreen> createState() => _TowerGenerateScreenState();
}

class _TowerGenerateScreenState extends State<TowerGenerateScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _basements = TextEditingController(text: '0');
  final _floors = TextEditingController(text: '0');
  final _units = TextEditingController(text: '0');
  final _unitFrom = TextEditingController(text: '1');
  final _unitTo = TextEditingController(text: '0');
  final _category = TextEditingController();
  final _pattern = TextEditingController(text: towerCodePatternDefault);
  final _areas = TextEditingController();
  final _lifts = TextEditingController(text: '0');
  final _staircases = TextEditingController(text: '0');
  final _floorHeight = TextEditingController();
  final _width = TextEditingController();
  final _depth = TextEditingController();
  final _fields = FieldErrors();
  final _previewAnchor = GlobalKey();

  bool _groundFloor = true;
  bool _terrace = false;
  bool _unitRangeEdited = false;
  bool _busy = false;
  int _request = 0;
  String? _banner;
  String? _previewSignature;
  String? _summary;
  List<String> _warnings = const [];
  List<TowerClash> _clashes = const [];
  List<Map<String, dynamic>> _tree = const [];

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _basements.dispose();
    _floors.dispose();
    _units.dispose();
    _unitFrom.dispose();
    _unitTo.dispose();
    _category.dispose();
    _pattern.dispose();
    _areas.dispose();
    _lifts.dispose();
    _staircases.dispose();
    _floorHeight.dispose();
    _width.dispose();
    _depth.dispose();
    super.dispose();
  }

  StructureWrite _write() {
    return towerGenerateBody(
      name: _name.text,
      code: _code.text,
      basementsText: _basements.text,
      groundFloor: _groundFloor,
      floorsText: _floors.text,
      terrace: _terrace,
      unitsText: _units.text,
      unitFromText: _unitFrom.text,
      unitToText: _unitTo.text,
      unitCategory: _category.text,
      codePattern: _pattern.text,
      commonAreasText: _areas.text,
      liftsText: _lifts.text,
      staircasesText: _staircases.text,
      floorHeightText: _floorHeight.text,
      widthText: _width.text,
      depthText: _depth.text,
    );
  }

  bool get _canCreate {
    if (_busy || _clashes.isNotEmpty || _previewSignature == null) return false;
    final write = _write();
    if (!write.isValid) return false;
    return towerGenerateSignature(write.payload!) == _previewSignature;
  }

  void _edited({String? field, bool floors = false}) {
    if (floors && !_unitRangeEdited) {
      final count = int.tryParse(_floors.text.trim());
      if (count != null && count >= 1) {
        _unitFrom.text = '1';
        _unitTo.text = '$count';
      }
    }
    setState(() {
      _banner = null;
      if (field != null) _fields.set(field, null);
      _clearPreview();
    });
  }

  void _clearPreview() {
    _previewSignature = null;
    _summary = null;
    _warnings = const [];
    _clashes = const [];
    _tree = const [];
  }

  Future<void> _preview() async {
    final write = _write();
    if (!write.isValid) {
      setState(() {
        _busy = false;
        _banner = null;
        _fields.clear();
        _fields.merge(write.errors);
        _clearPreview();
      });
      return;
    }
    final payload = write.payload!;
    final signature = towerGenerateSignature(payload);
    final request = ++_request;
    setState(() {
      _busy = true;
      _banner = null;
      _fields.clear();
    });
    final result = await widget.onPreview(payload);
    if (!mounted || request != _request) return;
    if (result is StructureApiError) {
      _applyError(result, signature: signature);
      return;
    }
    final data = result is Map ? Map<String, dynamic>.from(result) : const <String, dynamic>{};
    if (!towerPreviewAccepted(data)) {
      setState(() {
        _busy = false;
        _banner = 'Preview did not return a plan.';
        _clearPreview();
      });
      return;
    }
    final counts = data['counts'] is Map
        ? Map<String, dynamic>.from(data['counts'] as Map)
        : const <String, dynamic>{};
    final clashes = readTowerClashes(data['clashes']);
    setState(() {
      _busy = false;
      _previewSignature = signature;
      _summary = towerGenerateSummary(counts);
      _warnings = readTowerWarnings(data['warnings']);
      _clashes = clashes;
      _tree = structureTreeRoots(data);
      _banner = clashes.isEmpty ? null : towerClashHint;
      _fields
        ..clear()
        ..merge(towerClashFieldErrors(clashes));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _previewAnchor.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
        alignment: 0.05,
      );
    });
  }

  Future<void> _create() async {
    if (!_canCreate) return;
    final write = _write();
    if (!write.isValid) return;
    final payload = write.payload!;
    final signature = towerGenerateSignature(payload);
    final request = ++_request;
    setState(() {
      _busy = true;
      _banner = null;
    });
    final result = await widget.onCreate(payload);
    if (!mounted || request != _request) return;
    if (result is StructureApiError) {
      _applyError(result, signature: signature);
      return;
    }
    if (result == null || result is Map) {
      Navigator.pop(context, true);
    }
  }

  void _applyError(StructureApiError error, {required String signature}) {
    if (error.isNoAccess || error.isNotFound) {
      Navigator.pop(context, error);
      return;
    }
    final clashes = error.statusCode == 409
        ? readTowerClashes([
            for (final detail in error.details)
              if (detail.field != 'cascade' && detail.field != 'unlink_tasks')
                {'field': detail.field, 'message': detail.message},
          ])
        : const <TowerClash>[];
    setState(() {
      _busy = false;
      _banner = clashes.isEmpty ? error.message : towerClashHint;
      if (error.highlightFields) _fields.merge(error.fieldMessages);
      if (clashes.isNotEmpty) {
        _previewSignature = signature;
        _clashes = clashes;
        _fields.merge(towerClashFieldErrors(clashes));
      } else {
        _clearPreview();
      }
    });
  }

  String get _sampleCode {
    final pattern = _pattern.text.trim();
    if (pattern.isEmpty) return '';
    final code = applyTowerCodePattern(
      pattern: pattern,
      level: 5,
      unit: 3,
      towerCode: _code.text.trim(),
    );
    return 'Floor 5, unit 3 → $code';
  }

  @override
  Widget build(BuildContext context) {
    final sample = _sampleCode;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate tower'),
        leading: IconButton(
          tooltip: 'Close',
          onPressed: _busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: AppTheme.formPadding,
              children: [
                const Text(
                  'Preview the tower before creating it. To add another tower, run this again with a different name and code.',
                ),
                const SizedBox(height: 16),
                if (_banner != null || (_fields.hasErrors && _clashes.isEmpty))
                  ValidationSummaryBanner(
                    messages: [
                      ?_banner,
                      if (_clashes.isEmpty)
                        for (final message in _fields.messages)
                          if (message != _banner) message,
                    ],
                  ),
                _section('Building'),
                TextField(
                  key: const Key('tower-name'),
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Building name *',
                    errorText: _fields['name'],
                  ),
                  onChanged: (_) => _edited(field: 'name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('tower-code'),
                  controller: _code,
                  maxLength: 20,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Building code',
                    helperText: 'Optional. Used in unit codes.',
                    counterText: '',
                    errorText: _fields['code'],
                  ),
                  onChanged: (_) => _edited(field: 'code'),
                ),
                _section('Levels'),
                TextField(
                  key: const Key('tower-basements'),
                  controller: _basements,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Basements',
                    helperText: '0–10. Named Basement 1…n at levels −1…−n.',
                    errorText: _fields['basements'],
                  ),
                  onChanged: (_) => _edited(field: 'basements'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ground floor'),
                  subtitle: const Text('Level 0'),
                  value: _groundFloor,
                  onChanged: _busy
                      ? null
                      : (value) {
                          _groundFloor = value;
                          _edited();
                        },
                ),
                TextField(
                  key: const Key('tower-floors'),
                  controller: _floors,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Floors above ground',
                    helperText: '0–200. Named Floor 1…n.',
                    errorText: _fields['floors'],
                  ),
                  onChanged: (_) => _edited(field: 'floors', floors: true),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Terrace'),
                  subtitle: const Text('Above the top floor. No units or common areas.'),
                  value: _terrace,
                  onChanged: _busy
                      ? null
                      : (value) {
                          _terrace = value;
                          _edited();
                        },
                ),
                _section('Units'),
                TextField(
                  key: const Key('tower-units'),
                  controller: _units,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Units per floor',
                    helperText: '0–60. Placed on the levels below.',
                    errorText: _fields['units_per_floor'],
                  ),
                  onChanged: (_) => _edited(field: 'units_per_floor'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('tower-unit-from'),
                        controller: _unitFrom,
                        keyboardType: const TextInputType.numberWithOptions(signed: true),
                        decoration: InputDecoration(
                          labelText: 'Units from level',
                          errorText: _fields['unit_from'],
                        ),
                        onChanged: (_) {
                          _unitRangeEdited = true;
                          _edited(field: 'unit_from');
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: const Key('tower-unit-to'),
                        controller: _unitTo,
                        keyboardType: const TextInputType.numberWithOptions(signed: true),
                        decoration: InputDecoration(
                          labelText: 'Units to level',
                          errorText: _fields['unit_to'],
                        ),
                        onChanged: (_) {
                          _unitRangeEdited = true;
                          _edited(field: 'unit_to');
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _category,
                  decoration: InputDecoration(
                    labelText: 'Unit category',
                    hintText: '2BHK',
                    errorText: _fields['unit_category'],
                  ),
                  onChanged: (_) => _edited(field: 'unit_category'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('tower-pattern'),
                  controller: _pattern,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Code pattern',
                    errorText: _fields['code_pattern'],
                  ),
                  onChanged: (_) => _edited(field: 'code_pattern'),
                ),
                if (sample.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    sample,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '{floor} is G on the ground floor and B1, B2 in basements. {unit:02} is 01. {tower} is the building code.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.muted),
                  ),
                ],
                _section('Common areas'),
                TextField(
                  controller: _areas,
                  decoration: InputDecoration(
                    labelText: 'Common areas',
                    hintText: 'Lobby, Corridor',
                    helperText: 'Created on every floor except the terrace. Up to 20, separated by commas.',
                    errorText: _fields['common_areas'],
                  ),
                  onChanged: (_) => _edited(field: 'common_areas'),
                ),
                _section('Cores'),
                TextField(
                  controller: _lifts,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Lifts',
                    helperText: 'Named Lift 1… and spanning the lowest to the highest level.',
                    errorText: _fields['lifts'],
                  ),
                  onChanged: (_) => _edited(field: 'lifts'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _staircases,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Staircases',
                    helperText: 'Named Staircase 1…',
                    errorText: _fields['staircases'],
                  ),
                  onChanged: (_) => _edited(field: 'staircases'),
                ),
                _section('3D size'),
                TextField(
                  controller: _floorHeight,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Floor height',
                    hintText: '3.2',
                    errorText: _fields['floor_height'],
                  ),
                  onChanged: (_) => _edited(field: 'floor_height'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _width,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Footprint width',
                          hintText: '40',
                          errorText: _fields['width'],
                        ),
                        onChanged: (_) => _edited(field: 'width'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _depth,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Footprint depth',
                          hintText: '22',
                          errorText: _fields['depth'],
                        ),
                        onChanged: (_) => _edited(field: 'depth'),
                      ),
                    ),
                  ],
                ),
                if (_summary != null) ...[
                  const SizedBox(height: 20),
                  KeyedSubtree(
                    key: _previewAnchor,
                    child: Text(
                      _summary!,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (_warnings.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _NoteBox(
                      color: AppTheme.warning,
                      background: const Color(0xFFFFFBEB),
                      icon: Icons.info_outline,
                      title: 'Warnings',
                      lines: _warnings,
                    ),
                  ],
                  if (_clashes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _NoteBox(
                      color: AppTheme.danger,
                      background: const Color(0xFFFEE2E2),
                      icon: Icons.error_outline,
                      title: 'Already exists',
                      lines: [for (final clash in _clashes) towerClashMessage(clash)],
                    ),
                  ],
                  if (_tree.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          for (final node in _tree)
                            _TowerPreviewNode(node: node, depth: 0),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 160),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _clashes.isNotEmpty
                    ? towerClashHint
                    : 'Nothing is saved until you create the tower.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.muted),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _preview,
                      child: const Text('Preview'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _canCreate ? _create : null,
                      child: Text(_busy ? 'Working…' : 'Create'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _NoteBox extends StatelessWidget {
  const _NoteBox({
    required this.color,
    required this.background,
    required this.icon,
    required this.title,
    required this.lines,
  });

  final Color color;
  final Color background;
  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(left: 28, bottom: 4),
              child: Text(line, style: const TextStyle(height: 1.35)),
            ),
        ],
      ),
    );
  }
}

class _TowerPreviewNode extends StatefulWidget {
  const _TowerPreviewNode({required this.node, required this.depth});

  final Map<String, dynamic> node;
  final int depth;

  @override
  State<_TowerPreviewNode> createState() => _TowerPreviewNodeState();
}

class _TowerPreviewNodeState extends State<_TowerPreviewNode> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.depth == 0;
  }

  @override
  Widget build(BuildContext context) {
    final children = structureChildNodes(widget.node);
    final title = towerPreviewTitle(widget.node);
    final subtitle = towerPreviewSubtitle(widget.node);
    final pad = 8.0 + (widget.depth * 12);
    if (children.isEmpty) {
      return ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.only(left: pad + 28, right: 12),
        title: Text(title),
        subtitle: Text(subtitle),
      );
    }
    return Column(
      children: [
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: EdgeInsets.only(left: pad, right: 8),
          leading: Icon(_open ? Icons.expand_more : Icons.chevron_right),
          title: Text(title),
          subtitle: Text(subtitle),
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open)
          for (final child in children)
            _TowerPreviewNode(node: child, depth: widget.depth + 1),
      ],
    );
  }
}
