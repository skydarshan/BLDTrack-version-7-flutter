import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/modern_widgets.dart';
import '../../app/app_shell.dart';
import '../../auth/providers/auth_provider.dart';
import '../services/pms_services.dart';
import '../utils/site_options.dart';
import '../widgets/pickers.dart';
import '../widgets/pms_widgets.dart';

/// Mobile PMS home — essentials only (charts / long status lists stay on web).
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
      final overview =
          await context.read<PmsServices>().dashboard.pmsOverview(siteId: _siteId);
      if (!mounted) return;
      setState(() {
        _overview = overview;
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

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    final projects =
        (overview?['projects'] is Map) ? Map<String, dynamic>.from(overview!['projects'] as Map) : null;
    final tasks =
        (overview?['tasks'] is Map) ? Map<String, dynamic>.from(overview!['tasks'] as Map) : null;
    final myWork =
        (overview?['my_work'] is Map) ? Map<String, dynamic>.from(overview!['my_work'] as Map) : null;

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
            .take(5)
            .toList()
        : <Map<String, dynamic>>[];

    final avg = projects?['avg_progress'];

    return Scaffold(
      extendBody: true,
      body: RefreshIndicator(
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
              title: Column(
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
              actions: [
                const WorkspaceSwitcherButton(),
                IconButton(
                  tooltip: 'Filter site',
                  onPressed: _pickSite,
                  icon: const Icon(Icons.tune_rounded),
                ),
                IconButton(
                  tooltip: 'Logout',
                  onPressed: () async {
                    await context.read<AuthProvider>().logout();
                    if (context.mounted) context.go('/login');
                  },
                  icon: const Icon(Icons.logout_rounded),
                ),
              ],
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
              sliver: _loading
                  ? const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : SliverList(
                      delegate: SliverChildListDelegate([
                        if (_error != null) ...[
                          ErrorBanner(message: _error!, onRetry: _load),
                          const SizedBox(height: 12),
                        ],
                        if (ready > 0 || pending > 0) ...[
                          _VerificationBanner(
                            ready: ready,
                            pending: pending,
                            onReady: () => context.go('/pms/approvals'),
                            onPending: () => context.go('/pms/approvals'),
                          ),
                          const SizedBox(height: 12),
                        ],
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.55,
                          children: [
                            BentoStatCard(
                              label: 'Projects',
                              value: '${projects?['total'] ?? 0}',
                              icon: Icons.folder_special_rounded,
                              color: AppTheme.info,
                              onTap: () => context.go('/pms/projects'),
                            ),
                            BentoStatCard(
                              label: 'Active tasks',
                              value: '${tasks?['total'] ?? 0}',
                              icon: Icons.task_alt_rounded,
                              color: AppTheme.success,
                              onTap: () => context.go('/pms/tasks'),
                            ),
                            BentoStatCard(
                              label: 'Overdue',
                              value: '$overdue',
                              icon: Icons.warning_amber_rounded,
                              color: overdue > 0 ? AppTheme.danger : AppTheme.muted,
                              highlight: overdue > 0,
                              onTap: () => context.go('/pms/tasks?mine=1'),
                            ),
                            BentoStatCard(
                              label: 'Approvals',
                              value: '${ready + pending}',
                              hint: pending > 0 || ready > 0
                                  ? '$ready ready · $pending final'
                                  : null,
                              icon: Icons.verified_rounded,
                              color: (ready + pending) > 0 ? AppTheme.accent : AppTheme.muted,
                              highlight: (ready + pending) > 0,
                              onTap: () => context.go('/pms/approvals'),
                            ),
                          ],
                        ),
                        if (avg != null) ...[
                          const SizedBox(height: 12),
                          _ProgressStrip(percent: avg),
                        ],
                        const SizedBox(height: 18),
                        SectionHeader(
                          title: 'Recent projects',
                          color: AppTheme.brand,
                          trailing: TextButton(
                            onPressed: () => context.go('/pms/projects'),
                            child: const Text('See all'),
                          ),
                        ),
                        if (recent.isEmpty)
                          const EmptyState(message: 'No recent projects')
                        else
                          ...recent.asMap().entries.map((entry) {
                            final p = entry.value;
                            final i = entry.key;
                            final id = idOf(p);
                            return ModernListCard(
                              title: p['project_name']?.toString() ?? labelOf(p),
                              subtitle: [
                                statusLabel(p['status']?.toString()),
                                if (p['site'] != null) labelOf(p['site']),
                              ].join(' · '),
                              icon: Icons.folder_special_rounded,
                              color: AppTheme.colorAt(i),
                              trailing: StatusChip(status: p['status']?.toString()),
                              onTap: id == null
                                  ? null
                                  : () => context.push('/pms/projects/$id'),
                            );
                          }),
                      ]),
                    ),
            ),
          ],
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_rounded, size: 16, color: AppTheme.brand),
              const SizedBox(width: 8),
              Text('Needs your attention', style: AppTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 10),
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
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(child: Text(label, style: AppTheme.titleSmall.copyWith(fontSize: 13))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.percent});

  final dynamic percent;

  @override
  Widget build(BuildContext context) {
    final v = percent is num ? percent.toDouble() : double.tryParse('$percent') ?? 0;
    final clamped = (v / 100).clamp(0.0, 1.0);
    final color = v >= 100
        ? AppTheme.success
        : v >= 60
            ? AppTheme.info
            : v >= 30
                ? AppTheme.warning
                : AppTheme.danger;

    return Container(
      padding: const EdgeInsets.all(12),
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
              Text('Overall progress', style: AppTheme.titleSmall.copyWith(fontSize: 13)),
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
        ],
      ),
    );
  }
}
