import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../services/pms_services.dart';
import '../utils/site_options.dart';
import '../widgets/pickers.dart';
import '../widgets/pms_widgets.dart';

class TemplatesListScreen extends StatefulWidget {
  const TemplatesListScreen({super.key});

  @override
  State<TemplatesListScreen> createState() => _TemplatesListScreenState();
}

class _TemplatesListScreenState extends State<TemplatesListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  bool _inactiveOnly = false;
  String _search = '';
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  int _countTasks(dynamic tasks) {
    int walk(dynamic list) {
      if (list is! List) return 0;
      var n = list.length;
      for (final t in list) {
        if (t is Map) n += walk(t['children']);
      }
      return n;
    }

    return walk(tasks);
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
      final res = await context.read<PmsServices>().templates.list({
        'page': _page,
        'limit': 20,
        'search': _search,
        if (_inactiveOnly) 'inactiveOnly': true,
      });
      if (!mounted) return;
      final totalPages = res.pagination?['totalPages'];
      setState(() {
        _items = reset ? res.items : [..._items, ...res.items];
        _hasMore = totalPages is num && _page < totalPages;
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

  Future<void> _clone(Map<String, dynamic> tpl) async {
    final id = idOf(tpl);
    if (id == null) return;
    try {
      await context.read<PmsServices>().templates.clone(id);
      if (!mounted) return;
      showPmsSnack(context, 'Template cloned');
      await _load(reset: true);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> tpl) async {
    final id = idOf(tpl);
    if (id == null) return;
    final ok = await confirmAction(
      context,
      title: 'Deactivate template?',
      message: tpl['name']?.toString() ?? id,
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<PmsServices>().templates.delete(id);
      if (!mounted) return;
      showPmsSnack(context, 'Template deleted');
      await _load(reset: true);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _restore(Map<String, dynamic> tpl) async {
    final id = idOf(tpl);
    if (id == null) return;
    try {
      await context.read<PmsServices>().templates.restore(id);
      if (!mounted) return;
      showPmsSnack(context, 'Template restored');
      await _load(reset: true);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _createProject(Map<String, dynamic> tpl) async {
    final id = idOf(tpl);
    if (id == null) return;
    final nameCtrl = TextEditingController(text: tpl['name']?.toString() ?? '');
    final codeCtrl = TextEditingController();
    String? siteId;
    String siteLabel = '';
    List<OptionItem> sites = const [];
    try {
      sites = await loadSiteOptions(context);
    } catch (_) {}
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return AlertDialog(
              title: const Text('Create project from template'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Project name *',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(labelText: 'Code'),
                    ),
                    const SizedBox(height: 12),
                    PickerField(
                      label: 'Site',
                      required: true,
                      valueLabel: siteLabel,
                      onTap: () async {
                        final picked = await showOptionPicker(
                          context,
                          title: 'Select site',
                          options: sites,
                          selected: siteId,
                        );
                        if (picked == null) return;
                        setModal(() {
                          siteId = picked.value;
                          siteLabel = picked.label;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    if (nameCtrl.text.trim().isEmpty || siteId == null || siteId!.isEmpty) {
      showPmsSnack(context, 'Name and site are required', error: true);
      return;
    }
    try {
      final created = await context.read<PmsServices>().templates.createProject(
        id,
        {
          'project_name': nameCtrl.text.trim(),
          if (codeCtrl.text.trim().isNotEmpty) 'code': codeCtrl.text.trim(),
          'site': siteId,
        },
      );
      if (!mounted) return;
      showPmsSnack(context, 'Project created');
      final projectId = idOf(created);
      if (projectId != null) {
        context.push('/pms/projects/$projectId');
      }
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _applyToProject(Map<String, dynamic> tpl) async {
    final id = idOf(tpl);
    if (id == null) return;
    List<OptionItem> projects = const [];
    try {
      final res = await context.read<PmsServices>().projects.list({
        'page': 1,
        'limit': 100,
        'sortBy': 'project_name',
        'sortOrder': 'asc',
      });
      projects = res.items
          .map(
            (p) => OptionItem(
              value: idOf(p) ?? '',
              label: p['project_name']?.toString() ?? labelOf(p),
              raw: p,
            ),
          )
          .where((o) => o.value.isNotEmpty)
          .toList();
    } catch (_) {}
    if (!mounted) return;

    String? projectId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return AlertDialog(
              title: const Text('Apply template to project'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Template: ${tpl['name']}. Target project must have no existing tasks.',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  PickerField(
                    label: 'Project',
                    required: true,
                    valueLabel: projectId == null
                        ? ''
                        : projects
                            .firstWhere(
                              (p) => p.value == projectId,
                              orElse: () => const OptionItem(value: '', label: ''),
                            )
                            .label,
                    onTap: () async {
                      final picked = await showOptionPicker(
                        context,
                        title: 'Select project',
                        options: projects,
                        selected: projectId,
                      );
                      if (picked == null) return;
                      setModal(() => projectId = picked.value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    if (projectId == null || projectId!.isEmpty) {
      showPmsSnack(context, 'Select a project', error: true);
      return;
    }
    try {
      await context.read<PmsServices>().templates.apply(
        id,
        {'project_id': projectId},
      );
      if (!mounted) return;
      showPmsSnack(context, 'Template applied');
      context.push('/pms/projects/$projectId');
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Templates')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await context.push<bool>('/pms/templates/new');
          if (created == true && mounted) _load(reset: true);
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Search templates…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () {
                  _search = v.trim();
                  _load(reset: true);
                });
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Show inactive only'),
            value: _inactiveOnly,
            onChanged: (v) {
              setState(() => _inactiveOnly = v);
              _load(reset: true);
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ErrorBanner(
                message: _error!,
                onRetry: () => _load(reset: true),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: _loading && _items.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : _items.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 80),
                            EmptyState(message: 'No templates found'),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                          itemCount: _items.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i >= _items.length) {
                              return TextButton(
                                onPressed: () {
                                  _page += 1;
                                  _load();
                                },
                                child: const Text('Load more'),
                              );
                            }
                            final tpl = _items[i];
                            final id = idOf(tpl);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(tpl['name']?.toString() ?? 'Template'),
                                subtitle: Text(
                                  [
                                    tpl['scope']?.toString() ?? 'organization',
                                    '${_countTasks(tpl['tasks'])} tasks',
                                  ].join(' · '),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) async {
                                    switch (v) {
                                      case 'edit':
                                        if (id != null) {
                                          final updated = await context.push<bool>(
                                            '/pms/templates/$id/edit',
                                          );
                                          if (updated == true && mounted) {
                                            _load(reset: true);
                                          }
                                        }
                                      case 'clone':
                                        await _clone(tpl);
                                      case 'create_project':
                                        await _createProject(tpl);
                                      case 'apply':
                                        await _applyToProject(tpl);
                                      case 'restore':
                                        await _restore(tpl);
                                      case 'delete':
                                        await _delete(tpl);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    if (!_inactiveOnly) ...[
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'clone',
                                        child: Text('Clone'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'create_project',
                                        child: Text('Create project'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'apply',
                                        child: Text('Apply to project'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text(
                                          'Delete',
                                          style: TextStyle(color: AppTheme.danger),
                                        ),
                                      ),
                                    ] else
                                      const PopupMenuItem(
                                        value: 'restore',
                                        child: Text('Restore'),
                                      ),
                                  ],
                                ),
                                onTap: id == null || _inactiveOnly
                                    ? null
                                    : () => context.push('/pms/templates/$id/edit'),
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
