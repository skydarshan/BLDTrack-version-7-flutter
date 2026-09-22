import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../app/app_services.dart';
import '../../app/app_shell.dart';
import '../../pms/widgets/pms_widgets.dart';
import 'procurement_screens.dart';

class RcListScreen extends StatefulWidget {
  const RcListScreen({super.key});

  @override
  State<RcListScreen> createState() => _RcListScreenState();
}

class _RcListScreenState extends State<RcListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _page = 1;

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
      final res = await context.read<AppServices>().rc.list({'page': _page, 'limit': 20});
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate comparatives'),
        actions: const [WorkspaceSwitcherButton()],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(children: const [SizedBox(height: 80), Center(child: CircularProgressIndicator())])
            : _error != null
                ? ListView(padding: AppTheme.formPadding, children: [ErrorBanner(message: _error!, onRetry: _load)])
                : _items.isEmpty
                    ? ListView(children: const [EmptyState(message: 'No rate comparatives')])
                    : ListView.separated(
                        padding: AppTheme.formPadding,
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final row = _items[i];
                          return Card(
                            child: ListTile(
                              title: Text(row['title']?.toString() ?? labelOf(row['requisition_request'])),
                              subtitle: Text(labelOf(row['site'])),
                              trailing: StatusChip(status: row['status']?.toString()),
                              onTap: () => context.push('/procurement/rc/${idOf(row)}'),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class RcDetailScreen extends StatefulWidget {
  const RcDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<RcDetailScreen> createState() => _RcDetailScreenState();
}

class _RcDetailScreenState extends State<RcDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _doc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final doc = await context.read<AppServices>().rc.getById(widget.id);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _status(String status) async {
    try {
      await context.read<AppServices>().rc.updateStatus(widget.id, {'status': status});
      showPmsSnack(context, 'Updated');
      _load();
    } on ApiException catch (e) {
      showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _analyze() async {
    try {
      await context.read<AppServices>().rc.analyze(widget.id);
      showPmsSnack(context, 'AI analysis started / cached');
      _load();
    } on ApiException catch (e) {
      showPmsSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      appBar: AppBar(title: const Text('Rate comparative')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: AppTheme.formPadding,
                  child: ErrorBanner(message: _error!, onRetry: _load),
                )
              : ListView(
                  padding: AppTheme.formPadding,
                  children: [
                    StatusChip(status: doc?['status']?.toString()),
                    const SizedBox(height: 8),
                    Text('Title: ${doc?['title'] ?? '—'}'),
                    Text('Site: ${labelOf(doc?['site'])}'),
                    Text('Category: ${doc?['purchase_category'] ?? doc?['category'] ?? '—'}'),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(onPressed: () => _status('approved'), child: const Text('Approve')),
                        OutlinedButton(onPressed: () => _status('revise'), child: const Text('Revise')),
                        OutlinedButton(onPressed: () => _status('rejected'), child: const Text('Reject')),
                        OutlinedButton(onPressed: _analyze, child: const Text('AI analyze')),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class RateApprovalsScreen extends StatefulWidget {
  const RateApprovalsScreen({super.key});

  @override
  State<RateApprovalsScreen> createState() => _RateApprovalsScreenState();
}

class _RateApprovalsScreenState extends State<RateApprovalsScreen> {
  int _step = 1;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

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
      final api = context.read<AppServices>().rc;
      final res = _step == 1 ? await api.pendingFirst() : await api.pendingSecond();
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rate approvals')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppTheme.filterPadding,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Step 1')),
                ButtonSegment(value: 2, label: Text('Step 2')),
              ],
              selected: {_step},
              onSelectionChanged: (s) {
                setState(() => _step = s.first);
                _load();
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ErrorBanner(message: _error!, onRetry: _load),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const EmptyState(message: 'No pending rate approvals')
                    : ListView.separated(
                        padding: AppTheme.formPadding,
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final row = _items[i];
                          return Card(
                            child: ListTile(
                              title: Text(row['title']?.toString() ?? 'RC'),
                              onTap: () => context.push('/procurement/rc/${idOf(row)}'),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class PoListScreen extends StatefulWidget {
  const PoListScreen({super.key});

  @override
  State<PoListScreen> createState() => _PoListScreenState();
}

class _PoListScreenState extends State<PoListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _status = '';

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
      final res = await context.read<AppServices>().po.list({
        'page': 1,
        'limit': 30,
        if (_status.isNotEmpty) 'status': _status,
      });
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase orders'),
        actions: const [WorkspaceSwitcherButton()],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: AppTheme.chipRowPadding,
            child: Row(
              children: [
                for (final s in ['', 'pending', 'approved', 'rejected', 'revised'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.isEmpty ? 'All' : s),
                      selected: _status == s,
                      onSelected: (_) {
                        setState(() => _status = s);
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
                  ? ListView(children: const [SizedBox(height: 80), Center(child: CircularProgressIndicator())])
                  : _error != null
                      ? ListView(padding: AppTheme.formPadding, children: [ErrorBanner(message: _error!, onRetry: _load)])
                      : _items.isEmpty
                          ? ListView(children: const [EmptyState(message: 'No purchase orders')])
                          : ListView.separated(
                              padding: AppTheme.formPadding,
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final row = _items[i];
                                return Card(
                                  child: ListTile(
                                    title: Text(
                                      row['purchase_order_number']?.toString() ??
                                          row['ro_number']?.toString() ??
                                          'PO',
                                    ),
                                    subtitle: Text(labelOf(row['vendor'] ?? row['site'])),
                                    trailing: StatusChip(status: row['status']?.toString()),
                                    onTap: () => context.push('/procurement/po/${idOf(row)}'),
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

class PoDetailScreen extends StatefulWidget {
  const PoDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<PoDetailScreen> createState() => _PoDetailScreenState();
}

class _PoDetailScreenState extends State<PoDetailScreen> {
  Map<String, dynamic>? _doc;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final doc = await context.read<AppServices>().po.getById(widget.id);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _approve() async {
    try {
      await context.read<AppServices>().po.approval(widget.id, {'status': 'approved'});
      showPmsSnack(context, 'Approved');
      _load();
    } on ApiException catch (e) {
      showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _reject() async {
    try {
      await context.read<AppServices>().po.reject(widget.id);
      showPmsSnack(context, 'Rejected');
      _load();
    } on ApiException catch (e) {
      showPmsSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      appBar: AppBar(title: const Text('Purchase order')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: AppTheme.formPadding,
                  child: ErrorBanner(message: _error!, onRetry: _load),
                )
              : ListView(
                  padding: AppTheme.formPadding,
                  children: [
                    StatusChip(status: doc?['status']?.toString()),
                    const SizedBox(height: 8),
                    Text('PO: ${doc?['purchase_order_number'] ?? doc?['ro_number'] ?? '—'}'),
                    Text('Vendor: ${labelOf(doc?['vendor'])}'),
                    Text('Site: ${labelOf(doc?['site'])}'),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(onPressed: _approve, child: const Text('Approve')),
                        OutlinedButton(onPressed: _reject, child: const Text('Reject')),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class RrStatusScreen extends StatelessWidget {
  const RrStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RrListScreen();
  }
}
