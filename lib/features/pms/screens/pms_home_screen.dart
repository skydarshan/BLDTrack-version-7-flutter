import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/modern_widgets.dart';
import '../../../core/widgets/motion.dart';
import '../../app/app_shell.dart';
import '../../org/org_session.dart';
import '../services/pms_services.dart';
import '../utils/dpr_format.dart';
import '../utils/site_options.dart';
import '../widgets/pickers.dart';
import '../widgets/pms_widgets.dart';

/// Project management home — status charts, workload counts, and the full
/// recent project list, matching the website overview.
class PmsHomeScreen extends StatefulWidget {
  const PmsHomeScreen({super.key});

  @override
  State<PmsHomeScreen> createState() => _PmsHomeScreenState();
}

class _PmsHomeScreenState extends State<PmsHomeScreen> {
  bool _loading = true;
  String? _error;
  String? _siteId;
  String _siteLabel = 'All sites';
  Map<String, dynamic>? _overview;
  List<OptionItem> _siteOptions = const [];
  int _motion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await _loadSites();
    await _load();
  }

  Future<void> _loadSites() async {
    if (!mounted) return;
    final options = await loadSiteOptions(context);
    if (!mounted) return;
    setState(() => _siteOptions = options);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final overview = await context.read<PmsServices>().dashboard.pmsOverview(
        siteId: _siteId,
      );
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _loading = false;
        _motion += 1;
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

  Future<void> _pickSite() async {
    final options = [
      const OptionItem(value: '', label: 'All sites'),
      ..._siteOptions,
    ];
    final picked = await showOptionPicker(
      context,
      title: 'Filter by site',
      options: options,
      selected: _siteId ?? '',
    );
    if (picked == null) return;
    setState(() {
      _siteId = picked.value.isEmpty ? null : picked.value;
      _siteLabel = picked.label;
    });
    await _load();
  }

  String _withSite(String path) {
    if (_siteId == null || _siteId!.isEmpty) return path;
    final uri = Uri.parse(path);
    return uri
        .replace(queryParameters: {...uri.queryParameters, 'site': _siteId!})
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    final projects = (overview?['projects'] is Map)
        ? Map<String, dynamic>.from(overview!['projects'] as Map)
        : null;
    final tasks = (overview?['tasks'] is Map)
        ? Map<String, dynamic>.from(overview!['tasks'] as Map)
        : null;
    final myWork = (overview?['my_work'] is Map)
        ? Map<String, dynamic>.from(overview!['my_work'] as Map)
        : null;

    final ready = (myWork?['ready_for_completion'] is num)
        ? (myWork!['ready_for_completion'] as num).toInt()
        : int.tryParse('${myWork?['ready_for_completion'] ?? 0}') ?? 0;
    final pending = (myWork?['pending_approvals'] is num)
        ? (myWork!['pending_approvals'] as num).toInt()
        : int.tryParse('${myWork?['pending_approvals'] ?? 0}') ?? 0;
    final overdue = (myWork?['overdue'] is num)
        ? (myWork!['overdue'] as num).toInt()
        : int.tryParse('${myWork?['overdue'] ?? 0}') ?? 0;

    final recent = (projects?['recent'] is List)
        ? (projects!['recent'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];
    final projectCounts = _countMap(projects?['counts']);
    final taskCounts = _countMap(tasks?['counts']);
    final taskOverdue = tasks?['overdue'] is num
        ? (tasks!['overdue'] as num).toInt()
        : int.tryParse('${tasks?['overdue'] ?? overdue}') ?? overdue;
    final completedProjects = projectCounts['completed'] ?? 0;

    final avg = projects?['avg_progress'];

    return Scaffold(
      extendBody: true,
      body: StaggeredEntrance(
        active: !_loading,
        replayToken: _motion,
        maxIndex: 8,
        slide: 20,
        itemMs: 420,
        stepMs: 50,
        scaleFrom: 0.97,
        child: RefreshIndicator(
          onRefresh: _load,
          edgeOffset: 72,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                elevation: 0,
                scrolledUnderElevation: 0,
                toolbarHeight: 68,
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                automaticallyImplyLeading: false,
                centerTitle: false,
                titleSpacing: 16,
                title: StaggeredEntrance(
                  maxIndex: 0,
                  slide: 14,
                  itemMs: 380,
                  scaleFrom: 0.98,
                  child: EntranceItem(
                    index: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Project Management',
                          style: AppTheme.headlineSmall.copyWith(
                            color: Colors.white,
                            fontSize: 17,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _siteLabel,
                          style: AppTheme.bodySmall.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  const PressScale(child: WorkspaceSwitcherButton()),
                  PressScale(
                    child: IconButton(
                      tooltip: 'Filter site',
                      onPressed: _pickSite,
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ),
                  const PressScale(child: UserProfileButton()),
                ],
                flexibleSpace: Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: AppTheme.pagePadding,
                sliver: _loading
                    ? const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : SliverList(
                        delegate: SliverChildListDelegate([
                          if (_error != null) ...[
                            EntranceItem(
                              index: 0,
                              child: ErrorBanner(
                                message: _error!,
                                onRetry: _load,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (ready > 0 || pending > 0) ...[
                            EntranceItem(
                              index: 1,
                              child: _VerificationBanner(
                                ready: ready,
                                pending: pending,
                                onReady: () => context.go('/pms/approvals'),
                                onPending: () => context.go('/pms/approvals'),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          LayoutBuilder(
                            builder: (context, constraints) {
                              // Original card proportion. On a wide window, height stays at the
                              // phone size so the cards do not stretch and open a gap above
                              // Overall progress. Width still fills the page.
                              final measureWidth = constraints.maxWidth > 400
                                  ? 400.0
                                  : constraints.maxWidth;
                              final cardH =
                                  ((measureWidth - AppTheme.gridGap) / 2) *
                                  0.78;
                              Widget tile(Widget child) =>
                                  Expanded(child: child);
                              return Column(
                                children: [
                                  SizedBox(
                                    height: cardH,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        tile(
                                          EntranceItem(
                                            index: 2,
                                            child: PressScale(
                                              child: BentoStatCard(
                                                expand: true,
                                                badgeSize: 44,
                                                glyphSize: 24,
                                                label: 'Projects',
                                                value:
                                                    '${projects?['total'] ?? 0}',
                                                icon: Icons
                                                    .folder_special_rounded,
                                                color: AppTheme.info,
                                                onTap: () => context.go(
                                                  _withSite('/pms/projects'),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: AppTheme.gridGap),
                                        tile(
                                          EntranceItem(
                                            index: 3,
                                            child: PressScale(
                                              child: BentoStatCard(
                                                expand: true,
                                                badgeSize: 44,
                                                glyphSize: 24,
                                                label: 'Active tasks',
                                                value:
                                                    '${tasks?['total'] ?? 0}',
                                                icon: Icons.task_alt_rounded,
                                                color: AppTheme.success,
                                                onTap: () => context.go(
                                                  _withSite('/pms/tasks'),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: AppTheme.gridGap),
                                  SizedBox(
                                    height: cardH,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        tile(
                                          EntranceItem(
                                            index: 4,
                                            child: PressScale(
                                              child: BentoStatCard(
                                                expand: true,
                                                badgeSize: 44,
                                                glyphSize: 24,
                                                label: 'Overdue',
                                                value: '$overdue',
                                                icon:
                                                    Icons.warning_amber_rounded,
                                                color: overdue > 0
                                                    ? AppTheme.danger
                                                    : AppTheme.muted,
                                                highlight: overdue > 0,
                                                onTap: () => context.go(
                                                  _withSite(
                                                    '/pms/tasks?mine=1',
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: AppTheme.gridGap),
                                        tile(
                                          EntranceItem(
                                            index: 5,
                                            child: PressScale(
                                              child: BentoStatCard(
                                                expand: true,
                                                badgeSize: 44,
                                                glyphSize: 24,
                                                label: 'Approvals',
                                                value: '${ready + pending}',
                                                hint: pending > 0 || ready > 0
                                                    ? '$ready ready · $pending final'
                                                    : null,
                                                icon: Icons.verified_rounded,
                                                color: (ready + pending) > 0
                                                    ? AppTheme.accent
                                                    : AppTheme.muted,
                                                highlight:
                                                    (ready + pending) > 0,
                                                onTap: () => context.go(
                                                  '/pms/approvals',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          if (avg != null) ...[
                            const SizedBox(height: AppTheme.gridGap),
                            EntranceItem(
                              index: 6,
                              child: _ProgressStrip(
                                percent: avg,
                                overdue: taskOverdue,
                                completed: completedProjects,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppTheme.sectionGap),
                          EntranceItem(
                            index: 7,
                            child: _StatusChartCard(
                              title: 'Project status',
                              subtitle:
                                  '${projects?['total'] ?? 0} total projects',
                              slices: _statusSlices(
                                projectCounts,
                                byKey: _projectStatusColors,
                              ),
                              emptyMessage: 'No project data yet',
                            ),
                          ),
                          EntranceItem(
                            index: 8,
                            child: _StatusChartCard(
                              title: 'Task distribution',
                              subtitle: '${tasks?['total'] ?? 0} total tasks',
                              slices: _statusSlices(
                                taskCounts,
                                byIndex: _taskStatusColors,
                              ),
                              emptyMessage: 'No task data yet',
                            ),
                          ),
                          if (context.watch<OrgSession>().canUseSubmodule('project_management', 'dpr') &&
                              canDpr(context, 'read')) ...[
                            const SizedBox(height: AppTheme.sectionGap),
                            EntranceItem(
                              index: 6,
                              child: PressScale(
                                child: ModernListCard(
                                  title: 'Daily progress reports',
                                  subtitle: 'One report per site per day',
                                  icon: Icons.calendar_month_rounded,
                                  color: AppTheme.accent,
                                  onTap: () => context.go('/pms/dpr'),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: AppTheme.sectionGap),
                          EntranceItem(
                            index: 6,
                            child: SectionHeader(
                              title: 'Recent projects',
                              color: AppTheme.brand,
                              trailing: PressScale(
                                child: TextButton(
                                  onPressed: () =>
                                      context.go(_withSite('/pms/projects')),
                                  child: const Text('See all'),
                                ),
                              ),
                            ),
                          ),
                          if (recent.isEmpty)
                            const EntranceItem(
                              index: 6,
                              child: EmptyState(message: 'No recent projects'),
                            )
                          else
                            ...recent.asMap().entries.map((entry) {
                              final p = entry.value;
                              final i = entry.key;
                              final id = idOf(p);
                              return EntranceItem(
                                index: 6,
                                child: PressScale(
                                  enabled: id != null,
                                  child: ModernListCard(
                                    title:
                                        p['project_name']?.toString() ??
                                        labelOf(p),
                                    subtitle: [
                                      statusLabel(p['status']?.toString()),
                                      if (p['site'] != null) labelOf(p['site']),
                                      '${_percentOf(p['progress']).round()}%',
                                    ].join(' · '),
                                    icon: Icons.folder_special_rounded,
                                    color: AppTheme.colorAt(i),
                                    trailing: StatusChip(
                                      status: p['status']?.toString(),
                                    ),
                                    onTap: id == null
                                        ? null
                                        : () =>
                                              context.push('/pms/projects/$id'),
                                  ),
                                ),
                              );
                            }),
                        ]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner({
    required this.ready,
    required this.pending,
    required this.onReady,
    required this.onPending,
  });

  final int ready;
  final int pending;
  final VoidCallback onReady;
  final VoidCallback onPending;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.cardShadow,
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fact_check_rounded,
                size: 16,
                color: AppTheme.brand,
              ),
              const SizedBox(width: 8),
              Text('Needs your attention', style: AppTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          if (ready > 0)
            _AttentionRow(
              label: 'Ready for completion',
              count: ready,
              color: AppTheme.orange,
              onTap: onReady,
            ),
          if (ready > 0 && pending > 0) const SizedBox(height: 8),
          if (pending > 0)
            _AttentionRow(
              label: 'Final approval',
              count: pending,
              color: AppTheme.accent,
              onTap: onPending,
            ),
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Material(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppTheme.titleSmall.copyWith(fontSize: 13),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: color, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({
    required this.percent,
    required this.overdue,
    required this.completed,
  });

  final dynamic percent;
  final int overdue;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final v = percent is num
        ? percent.toDouble()
        : double.tryParse('$percent') ?? 0;
    final clamped = (v / 100).clamp(0.0, 1.0);
    final color = v >= 100
        ? AppTheme.success
        : v >= 60
        ? AppTheme.info
        : v >= 30
        ? AppTheme.warning
        : AppTheme.danger;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Overall progress',
                style: AppTheme.titleSmall.copyWith(fontSize: 13),
              ),
              const Spacer(),
              Text(
                '${v.round()}%',
                style: AppTheme.titleSmall.copyWith(color: color, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: 8,
              backgroundColor: AppTheme.surface,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$overdue overdue',
                  style: AppTheme.bodySmall.copyWith(
                    color: overdue > 0 ? AppTheme.danger : AppTheme.muted,
                  ),
                ),
              ),
              Text(
                '$completed completed',
                style: AppTheme.bodySmall.copyWith(color: AppTheme.success),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Map<String, int> _countMap(dynamic raw) {
  if (raw is! Map) return {};
  final out = <String, int>{};
  for (final entry in raw.entries) {
    final value = entry.value;
    out['${entry.key}'] = value is num
        ? value.toInt()
        : int.tryParse('$value') ?? 0;
  }
  return out;
}

double _percentOf(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

const _projectStatusColors = <String, Color>{
  'not_started': Color(0xFF94A3B8),
  'in_progress': Color(0xFF3B82F6),
  'on_hold': Color(0xFFF59E0B),
  'completed': Color(0xFF22C55E),
  'archived': Color(0xFFA1A1AA),
  'cancelled': Color(0xFFEF4444),
  'completion_requested': Color(0xFF8B5CF6),
};

const _taskStatusColors = <Color>[
  Color(0xFF3B82F6),
  Color(0xFF22C55E),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFF8B5CF6),
  Color(0xFF94A3B8),
  Color(0xFF06B6D4),
];

List<_StatusSlice> _statusSlices(
  Map<String, int> counts, {
  Map<String, Color>? byKey,
  List<Color>? byIndex,
}) {
  final slices = <_StatusSlice>[];
  var index = 0;
  for (final entry in counts.entries) {
    final indexed = byIndex == null
        ? null
        : byIndex[index % byIndex.length];
    slices.add(
      _StatusSlice(
        label: entry.key.replaceAll('_', ' '),
        value: entry.value,
        color: indexed ?? byKey?[entry.key] ?? AppTheme.colorAt(index),
      ),
    );
    index += 1;
  }
  return slices;
}

class _StatusSlice {
  const _StatusSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

class _StatusChartCard extends StatelessWidget {
  const _StatusChartCard({
    required this.title,
    required this.subtitle,
    required this.slices,
    required this.emptyMessage,
  });

  final String title;
  final String subtitle;
  final List<_StatusSlice> slices;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.value);
    final maxValue = slices.fold<int>(
      0,
      (max, slice) => slice.value > max ? slice.value : max,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.gridGap),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.titleMedium.copyWith(fontSize: 15)),
          Text(subtitle, style: AppTheme.bodySmall.copyWith(color: AppTheme.muted)),
          const SizedBox(height: 12),
          if (slices.isEmpty || total == 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(emptyMessage, style: const TextStyle(color: AppTheme.muted)),
            )
          else ...[
            Center(
              child: SizedBox(
                width: 132,
                height: 132,
                child: CustomPaint(
                  painter: _DonutPainter(slices),
                  child: Center(
                    child: Text('$total', style: AppTheme.titleMedium),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final slice in slices)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 108,
                      child: Text(
                        slice.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodySmall.copyWith(fontSize: 11),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: maxValue == 0 ? 0 : slice.value / maxValue,
                          minHeight: 7,
                          backgroundColor: AppTheme.surface,
                          color: slice.color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${slice.value}',
                        textAlign: TextAlign.end,
                        style: AppTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices);

  final List<_StatusSlice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.value);
    if (total <= 0) return;
    const stroke = 14.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    var start = -math.pi / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    final gap = slices.length > 1 ? 0.06 : 0.0;
    for (final slice in slices) {
      final sweep = math.max(0.0, (slice.value / total) * math.pi * 2 - gap);
      paint.color = slice.color;
      canvas.drawArc(arc, start, sweep, false, paint);
      start += (slice.value / total) * math.pi * 2;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices != slices;
}
