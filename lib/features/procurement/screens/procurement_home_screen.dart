import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/modern_widgets.dart';
import '../../../core/utils/share_bytes.dart';
import '../../../core/widgets/motion.dart';
import '../../app/app_services.dart';
import '../../app/app_shell.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/pdf/dashboard_pdf.dart';
import '../../dashboard/utils/dashboard_values.dart';
import '../../dashboard/widgets/procurement_dashboard_widgets.dart';
import '../../pms/utils/site_options.dart';
import '../../pms/widgets/pickers.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../../settings/utils/permissions.dart';

/// Procurement home — same overview as the website dashboard, including the
/// day / week / month chart and a full PDF export.
class ProcurementHomeScreen extends StatefulWidget {
  const ProcurementHomeScreen({super.key});

  @override
  State<ProcurementHomeScreen> createState() => _ProcurementHomeScreenState();
}

class _ProcurementHomeScreenState extends State<ProcurementHomeScreen> {
  bool _loading = true;
  bool _chartLoading = false;
  bool _exporting = false;
  String? _error;
  String _granularity = 'week';
  String? _siteId;
  String _siteLabel = 'All sites';
  late String _dateFrom;
  late String _dateTo;
  List<OptionItem> _siteOptions = const [];
  DashboardOverview _overview = DashboardOverview.empty;
  ProcurementOverview _procurement = ProcurementOverview.empty;
  int _motion = 0;

  @override
  void initState() {
    super.initState();
    final range = defaultDashboardDateRange();
    _dateFrom = range.dateFrom;
    _dateTo = range.dateTo;
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

  Map<String, dynamic> _rangeParams() => {
    if (_siteId != null && _siteId!.isNotEmpty) 'site_id': _siteId,
    'from': _dateFrom,
    'to': _dateTo,
  };

  Future<void> _load({bool chartOnly = false}) async {
    if (chartOnly) {
      setState(() => _chartLoading = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final api = context.read<AppServices>().pms.dashboard;
    try {
      if (chartOnly) {
        final raw = await api.procurement({
          ..._rangeParams(),
          'granularity': _granularity,
          'limit': 10,
        });
        if (!mounted) return;
        final next = normalizeProcurementOverview(raw);
        setState(() {
          _procurement = _procurement.copyWith(
            granularity: next.granularity,
            buckets: next.buckets,
          );
          _chartLoading = false;
          _motion += 1;
        });
        return;
      }

      final overviewFuture = api.overview(_rangeParams());
      final procurementFuture = api.procurement({
        ..._rangeParams(),
        'granularity': _granularity,
        'limit': 10,
      });
      final overview = await overviewFuture;
      ProcurementOverview procurement = ProcurementOverview.empty;
      Object? procurementError;
      try {
        procurement = normalizeProcurementOverview(await procurementFuture);
      } catch (e) {
        procurementError = e;
      }
      if (!mounted) return;
      setState(() {
        _overview = normalizeDashboardOverview(overview);
        _procurement = procurement;
        _loading = false;
        _chartLoading = false;
        _motion += 1;
      });
      if (procurementError != null && mounted) {
        final message = procurementError is ApiException
            ? procurementError.message
            : 'Could not load the procurement chart';
        showPmsSnack(context, message, error: true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (chartOnly) {
        setState(() => _chartLoading = false);
        showPmsSnack(context, e.message, error: true);
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
        _chartLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (chartOnly) {
        setState(() => _chartLoading = false);
        showPmsSnack(context, 'Could not load the procurement chart', error: true);
        return;
      }
      setState(() {
        _error = e.toString();
        _loading = false;
        _chartLoading = false;
      });
    }
  }

  Future<void> _pickSite() async {
    final picked = await showOptionPicker(
      context,
      title: 'Site',
      options: [
        const OptionItem(value: '', label: 'All sites'),
        ..._siteOptions,
      ],
      selected: _siteId ?? '',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _siteId = picked.value.isEmpty ? null : picked.value;
      _siteLabel = picked.value.isEmpty ? 'All sites' : picked.label;
    });
    await _load();
  }

  Future<void> _pickDate({required bool from}) async {
    final initial = DateTime.tryParse(from ? _dateFrom : _dateTo) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    final iso = isoYmd(picked);
    setState(() {
      if (from) {
        _dateFrom = iso;
        if (_dateTo.compareTo(_dateFrom) < 0) _dateTo = _dateFrom;
      } else {
        _dateTo = iso;
        if (_dateFrom.compareTo(_dateTo) > 0) _dateFrom = _dateTo;
      }
    });
    await _load();
  }

  void _selectSiteCard(SitePrRow site) {
    final already = _siteId == site.siteId;
    setState(() {
      _siteId = already ? null : site.siteId;
      _siteLabel = already ? 'All sites' : site.siteName;
    });
    _load();
  }

  Future<void> _setGranularity(String value) async {
    if (value == _granularity) return;
    setState(() => _granularity = value);
    await _load(chartOnly: true);
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final user = context.read<AuthProvider>().user;
      final bytes = await buildDashboardPdfBytes(
        overview: _overview,
        siteRows: visibleSiteRows(
          apiRows: _overview.sites,
          unrestricted: Permissions(user).isSuperAdmin,
          assignedSites: sitesFromAuthProfile(user?.sites ?? const []),
        ),
        procurement: _procurement,
        chartGranularity: _granularity,
        siteLabel: _siteLabel,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      if (!mounted) return;
      await shareDownloadedBytes(
        bytes: bytes,
        filename: 'dashboard-overview-$_dateTo.pdf',
        text: 'Procurement dashboard',
      );
    } catch (_) {
      if (mounted) {
        showPmsSnack(
          context,
          'Could not export PDF. Please try again.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final siteRows = visibleSiteRows(
      apiRows: _overview.sites,
      unrestricted: Permissions(user).isSuperAdmin,
      assignedSites: sitesFromAuthProfile(user?.sites ?? const []),
    );
    final inventory = formatCompactInr(
      _overview.inventoryValue,
      _overview.inventoryFormatted,
    );
    final yetToReceive = formatCompactInr(
      _overview.yetToReceive,
      _overview.yetFormatted,
    );

    return Scaffold(
      extendBody: true,
      appBar: const ModernAppBar(
        title: 'Procurement',
        actions: [
          PressScale(child: WorkspaceSwitcherButton()),
          PressScale(child: UserProfileButton()),
        ],
      ),
      body: StaggeredEntrance(
        active: !_loading,
        replayToken: _motion,
        maxIndex: 10,
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const CenteredScrollLoader()
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: AppTheme.pagePadding,
                  children: [
                    EntranceItem(
                      index: 0,
                      child: _FilterCard(
                        siteLabel: _siteLabel,
                        fromLabel: formatDisplayDate(_dateFrom),
                        toLabel: formatDisplayDate(_dateTo),
                        exporting: _exporting,
                        onSite: _pickSite,
                        onFrom: () => _pickDate(from: true),
                        onTo: () => _pickDate(from: false),
                        onRefresh: _load,
                        onExport: _exportPdf,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      EntranceItem(
                        index: 1,
                        child: ErrorBanner(message: _error!, onRetry: _load),
                      ),
                    ],
                    const SizedBox(height: 8),
                    AppStatRow(
                      left: EntranceItem(
                        index: 2,
                        child: BentoStatCard(
                          label: 'Inventory value',
                          value: inventory,
                          hint: _overview.trendPercent == null
                              ? null
                              : '${_overview.trendPercent}% vs last period',
                          icon: Icons.inventory_2_rounded,
                          color: AppTheme.accent,
                        ),
                      ),
                      right: EntranceItem(
                        index: 3,
                        child: BentoStatCard(
                          label: 'Active sites',
                          value: '${_overview.activeSites}',
                          hint: _overview.sitesStatus,
                          icon: Icons.place_rounded,
                          color: AppTheme.info,
                        ),
                      ),
                    ),
                    AppStatRow(
                      left: EntranceItem(
                        index: 4,
                        child: PressScale(
                          child: BentoStatCard(
                            label: 'Yet to receive',
                            value: yetToReceive,
                            hint: '${_overview.pendingLines} pending lines',
                            icon: Icons.local_shipping_rounded,
                            color: AppTheme.orange,
                            highlight: _overview.pendingLines > 0,
                            onTap: () => context.go('/dmr/status'),
                          ),
                        ),
                      ),
                      right: EntranceItem(
                        index: 5,
                        child: PressScale(
                          child: BentoStatCard(
                            label: 'Purchase requests',
                            value: '${_overview.prCount}',
                            hint: '${_overview.prPending} pending',
                            icon: Icons.description_rounded,
                            color: AppTheme.brand,
                            highlight: _overview.prPending > 0,
                            onTap: () => context.go('/procurement/rr'),
                          ),
                        ),
                      ),
                    ),
                    EntranceItem(
                      index: 6,
                      child: Row(
                        children: [
                          Expanded(
                            child: _QuickTile(
                              label: 'New RR',
                              icon: Icons.add_box_rounded,
                              color: AppTheme.brand,
                              onTap: () => context.push('/procurement/rr/new'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _QuickTile(
                              label: 'Approvals',
                              icon: Icons.verified_rounded,
                              color: AppTheme.success,
                              onTap: () => context.go('/procurement/approvals'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _QuickTile(
                              label: 'Orders',
                              icon: Icons.shopping_bag_rounded,
                              color: AppTheme.info,
                              onTap: () => context.go('/procurement/po'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.sectionGap),
                    EntranceItem(
                      index: 7,
                      child: SitePurchaseCards(
                        sites: siteRows,
                        selectedSiteId: _siteId,
                        onSiteSelected: _selectSiteCard,
                      ),
                    ),
                    EntranceItem(
                      index: 8,
                      child: ProcurementValueChart(
                        buckets: _procurement.buckets,
                        granularity: _granularity,
                        loading: _chartLoading,
                        onGranularityChanged: _setGranularity,
                      ),
                    ),
                    EntranceItem(
                      index: 9,
                      child: PurchasedMaterialsCard(
                        title: 'Top 10 purchased materials',
                        materials: _procurement.top,
                        accent: AppTheme.success,
                      ),
                    ),
                    EntranceItem(
                      index: 10,
                      child: PurchasedMaterialsCard(
                        title: 'Least 10 purchased materials',
                        materials: _procurement.least,
                        accent: AppTheme.danger,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.siteLabel,
    required this.fromLabel,
    required this.toLabel,
    required this.exporting,
    required this.onSite,
    required this.onFrom,
    required this.onTo,
    required this.onRefresh,
    required this.onExport,
  });

  final String siteLabel;
  final String fromLabel;
  final String toLabel;
  final bool exporting;
  final VoidCallback onSite;
  final VoidCallback onFrom;
  final VoidCallback onTo;
  final VoidCallback onRefresh;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _FilterField(
                  label: 'Site',
                  value: siteLabel,
                  onTap: onSite,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FilterField(
                  label: 'From',
                  value: fromLabel,
                  onTap: onFrom,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FilterField(label: 'To', value: toLabel, onTap: onTo),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ToolbarButton(
                label: 'Refresh',
                icon: Icons.refresh_rounded,
                onPressed: onRefresh,
              ),
              const SizedBox(width: 6),
              _ToolbarButton(
                label: 'Export PDF',
                icon: Icons.download_rounded,
                filled: true,
                busy: exporting,
                onPressed: exporting ? null : onExport,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      ),
      textStyle: WidgetStatePropertyAll(
        AppTheme.titleSmall.copyWith(fontSize: 11, fontWeight: FontWeight.w700),
      ),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
    final iconWidget = busy
        ? const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 14);
    if (filled) {
      return FilledButton.icon(
        style: style,
        onPressed: onPressed,
        icon: iconWidget,
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      style: style,
      onPressed: onPressed,
      icon: iconWidget,
      label: Text(label),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
              boxShadow: AppTheme.cardShadow,
            ),
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.titleSmall.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTheme.bodySmall.copyWith(
                  fontSize: 9,
                  letterSpacing: 0.4,
                  color: AppTheme.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.titleSmall.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
