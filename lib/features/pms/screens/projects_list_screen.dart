import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/modern_widgets.dart';
import '../services/pms_services.dart';
import '../utils/pms_constants.dart';
import '../widgets/pickers.dart';
import '../widgets/pms_widgets.dart';

class ProjectsListScreen extends StatefulWidget {
  const ProjectsListScreen({super.key});

  @override
  State<ProjectsListScreen> createState() => _ProjectsListScreenState();
}

class _ProjectsListScreenState extends State<ProjectsListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _search = '';
  String? _status;
  String? _priority;
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

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await context.read<PmsServices>().projects.list({
        'page': _page,
        'limit': 20,
        'search': _search,
        'status': _status,
        'priority': _priority,
        'sortBy': 'createdAt',
        'sortOrder': 'desc',
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

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search = value.trim();
      _load(reset: true);
    });
  }

  Future<void> _archive(Map<String, dynamic> project, {required bool archive}) async {
    final id = idOf(project);
    if (id == null) return;
    final ok = await confirmAction(
      context,
      title: archive ? 'Archive project?' : 'Unarchive project?',
      message: project['project_name']?.toString() ?? id,
      confirmLabel: archive ? 'Archive' : 'Unarchive',
    );
    if (!ok || !mounted) return;
    try {
      final api = context.read<PmsServices>().projects;
      if (archive) {
        await api.archive(id);
      } else {
        await api.unarchive(id);
      }
      if (!mounted) return;
      showPmsSnack(context, archive ? 'Project archived' : 'Project restored');
      await _load(reset: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> project) async {
    final id = idOf(project);
    if (id == null) return;
    final ok = await confirmAction(
      context,
      title: 'Delete project?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<PmsServices>().projects.delete(id);
      if (!mounted) return;
      showPmsSnack(context, 'Project deleted');
      await _load(reset: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      showPmsSnack(context, e.message, error: true);
    }
  }

  Future<void> _pickFilter({
    required String title,
    required List<(String, String)> options,
    required String? current,
    required ValueChanged<String?> onPicked,
  }) async {
    final items = [
      const OptionItem(value: '', label: 'All'),
      for (final o in options) OptionItem(value: o.$1, label: o.$2),
    ];
    final picked = await showOptionPicker(
      context,
      title: title,
      options: items,
      selected: current ?? '',
    );
    if (picked == null) return;
    onPicked(picked.value.isEmpty ? null : picked.value);
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: const ModernAppBar(title: 'Projects'),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await context.push<bool>('/pms/projects/new');
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
                hintText: 'Search projects…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: Text(
                    _status == null
                        ? 'Status'
                        : PmsConstants.labelFor(PmsConstants.projectStatuses, _status),
                  ),
                  selected: _status != null,
                  onSelected: (_) => _pickFilter(
                    title: 'Status',
                    options: [
                      ...PmsConstants.projectStatuses,
                      ('archived', 'Archived'),
                    ],
                    current: _status,
                    onPicked: (v) => setState(() => _status = v),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(
                    _priority == null
                        ? 'Priority'
                        : PmsConstants.labelFor(PmsConstants.priorities, _priority),
                  ),
                  selected: _priority != null,
                  onSelected: (_) => _pickFilter(
                    title: 'Priority',
                    options: PmsConstants.priorities,
                    current: _priority,
                    onPicked: (v) => setState(() => _priority = v),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ErrorBanner(message: _error!, onRetry: () => _load(reset: true)),
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
                            EmptyState(message: 'No projects found'),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
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
                            final p = _items[i];
                            final id = idOf(p);
                            final archived = p['status']?.toString() == 'archived';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                color: Colors.white,
                                boxShadow: AppTheme.cardShadow,
                              ),
                              child: ListTile(
                                title: Text(
                                  p['project_name']?.toString() ?? 'Project',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  [
                                    if ((p['code']?.toString() ?? '').isNotEmpty) p['code'],
                                    labelOf(p['site']),
                                    PmsConstants.labelFor(
                                      PmsConstants.priorities,
                                      p['priority']?.toString(),
                                    ),
                                  ].whereType<String>().where((s) => s != '—').join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    StatusChip(status: p['status']?.toString()),
                                    PopupMenuButton<String>(
                                      onSelected: (v) {
                                        if (v == 'archive') {
                                          _archive(p, archive: true);
                                        } else if (v == 'unarchive') {
                                          _archive(p, archive: false);
                                        } else if (v == 'delete') {
                                          _delete(p);
                                        } else if (v == 'edit' && id != null) {
                                          context.push('/pms/projects/$id/edit');
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit'),
                                        ),
                                        if (archived)
                                          const PopupMenuItem(
                                            value: 'unarchive',
                                            child: Text('Unarchive'),
                                          )
                                        else
                                          const PopupMenuItem(
                                            value: 'archive',
                                            child: Text('Archive'),
                                          ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text(
                                            'Delete',
                                            style: TextStyle(color: AppTheme.danger),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                onTap: id == null
                                    ? null
                                    : () => context.push('/pms/projects/$id'),
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
