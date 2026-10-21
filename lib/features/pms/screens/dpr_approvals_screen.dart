import 'package:flutter/material.dart';
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
import '../widgets/pickers.dart';
import '../widgets/pms_widgets.dart';

class DprApprovalsScreen extends StatefulWidget {
  const DprApprovalsScreen({super.key});

  @override
  State<DprApprovalsScreen> createState() => _DprApprovalsScreenState();
}

class _DprApprovalsScreenState extends State<DprApprovalsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  bool _hasMore = false;
  List<OptionItem> _sites = const [];
  String? _siteId;
  String _siteLabel = 'All sites';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (!mounted || !canAccessDprApprovals(context)) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      _sites = await loadSiteOptions(context);
    } catch (_) {}
    if (_sites.length == 1) {
      _siteId = _sites.first.value;
      _siteLabel = _sites.first.label;
    }
    if (!mounted) return;
    final open = GoRouterState.of(context).uri.queryParameters['open'];
    await _load(reset: true);
    if (open != null && open.isNotEmpty && mounted) {
      final changed = await context.push('/pms/dpr/$open');
      if (changed == true && mounted) _load(reset: true);
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await context.read<PmsServices>().dpr.pendingApprovals({
        'page': _page,
        'limit': 20,
        'site': _siteId,
      });
      if (!mounted) return;
      setState(() {
        _items = reset ? res.items : [..._items, ...res.items];
        _hasMore = dprHasNextPage(res.pagination, _page);
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
    final picked = await showOptionPicker(
      context,
      title: 'Site',
      options: [const OptionItem(value: '', label: 'All sites'), ..._sites],
      selected: _siteId ?? '',
    );
    if (picked == null) return;
    setState(() {
      _siteId = picked.value.isEmpty ? null : picked.value;
      _siteLabel = picked.label;
    });
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!canDpr(context, 'approve')) {
      return const Scaffold(
        appBar: ModernAppBar(title: 'DPR approvals'),
        body: StaggeredEntrance(
          maxIndex: 0,
          child: EntranceItem(
            index: 0,
            child: EmptyState(message: 'You do not have permission to approve daily reports.'),
          ),
        ),
      );
    }
    if (!canAccessDprApprovals(context)) {
      return const Scaffold(
        appBar: ModernAppBar(title: 'DPR approvals'),
        body: StaggeredEntrance(
          maxIndex: 0,
          child: EntranceItem(
            index: 0,
            child: EmptyState(
              message: 'Your role is not set as a DPR Step 1 or Step 2 approver in organization settings.',
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: ModernAppBar(
        title: 'DPR approvals',
        actions: [
          if (_sites.length != 1)
            PressScale(
              child: IconButton(
                tooltip: _siteLabel,
                onPressed: _pickSite,
                icon: const Icon(Icons.apartment_rounded),
              ),
            ),
        ],
      ),
      body: StaggeredEntrance(
        active: !_loading,
        replayToken: _siteId,
        maxIndex: 6,
        slide: 16,
        itemMs: 380,
        stepMs: 40,
        scaleFrom: 0.97,
        child: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: AppTheme.pagePadding,
                    children: [
                      EntranceItem(
                        index: 0,
                        child: ErrorBanner(message: _error!, onRetry: () => _load(reset: true)),
                      ),
                    ],
                  )
                : _items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 80),
                          EntranceItem(
                            index: 0,
                            child: EmptyState(message: 'No reports are waiting for your approval'),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: AppTheme.pagePadding,
                        itemCount: _items.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _items.length) {
                            return EntranceItem(
                              index: 6,
                              child: TextButton(
                                onPressed: () {
                                  _page += 1;
                                  _load();
                                },
                                child: const Text('Load more'),
                              ),
                            );
                          }
                          final row = _items[index];
                          final id = idOf(row);
                          return EntranceItem(
                            index: index,
                            child: PressScale(
                              child: ModernListCard(
                            title: dprSiteLabel(row['site']),
                            subtitle: [
                              formatDprDate(row['report_date']),
                              personName(row['prepared_by'] ?? row['created_by']),
                              if (approvalStepLabel(row) != null) approvalStepLabel(row)!,
                              if (row['is_backdated'] == true) 'Backfilled',
                            ].join(' · '),
                            icon: Icons.fact_check_rounded,
                            color: AppTheme.accent,
                            trailing: StatusChip(
                              status: row['status']?.toString(),
                              label: dprStatusLabel(row['status']?.toString()),
                            ),
                            onTap: id == null
                                ? null
                                : () async {
                                    final changed = await context.push('/pms/dpr/$id');
                                    if (changed == true && mounted) _load(reset: true);
                                  },
                          ),
                            ),
                          );
                        },
                      ),
      ),
      ),
    );
  }
}
