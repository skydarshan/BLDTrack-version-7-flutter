import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../services/settings_apis.dart';
import '../utils/permissions.dart';

typedef MasterFieldBuilder = Widget Function(
  BuildContext context,
  Map<String, TextEditingController> controllers,
  Map<String, dynamic> extras,
  void Function(void Function()) setLocal,
);

typedef MasterPayloadBuilder = Map<String, dynamic> Function(
  Map<String, TextEditingController> controllers,
  Map<String, dynamic> extras,
);

typedef MasterHydrate = void Function(
  Map<String, dynamic> row,
  Map<String, TextEditingController> controllers,
  Map<String, dynamic> extras,
);

class MasterFieldDef {
  const MasterFieldDef({
    required this.key,
    required this.label,
    this.required = false,
    this.keyboardType,
    this.maxLines = 1,
    this.obscure = false,
  });

  final String key;
  final String label;
  final bool required;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool obscure;
}

/// Reusable searchable CRUD list for simple masters.
class MasterCrudScreen extends StatefulWidget {
  const MasterCrudScreen({
    super.key,
    required this.title,
    required this.permission,
    required this.api,
    required this.titleOf,
    required this.fields,
    this.subtitleOf,
    this.buildPayload,
    this.hydrate,
    this.extraFormBuilder,
    this.sortBy,
  });

  final String title;
  final String permission;
  final MasterResourceApi api;
  final String Function(Map<String, dynamic> row) titleOf;
  final String Function(Map<String, dynamic> row)? subtitleOf;
  final List<MasterFieldDef> fields;
  final MasterPayloadBuilder? buildPayload;
  final MasterHydrate? hydrate;
  final MasterFieldBuilder? extraFormBuilder;
  final String? sortBy;

  @override
  State<MasterCrudScreen> createState() => _MasterCrudScreenState();
}

class _MasterCrudScreenState extends State<MasterCrudScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _pagination;
  bool _loading = true;
  String? _error;
  int _page = 1;
  String _search = '';

  Permissions get _perms => Permissions(context.read<AuthProvider>().user);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _searchCtrl.addListener(() {
      // debounce via delayed
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_perms.can(widget.permission, 'read') && !_perms.isSuperAdmin) {
      setState(() {
        _loading = false;
        _error = 'You do not have permission to view this.';
        _items = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.list({
        'page': _page,
        'limit': 20,
        'search': _search,
        if (widget.sortBy != null) 'sortBy': widget.sortBy,
        if (widget.sortBy != null) 'sortOrder': 'asc',
      });
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _pagination = res.pagination;
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

  Future<void> _openForm({Map<String, dynamic>? row}) async {
    final isEdit = row != null;
    if (isEdit && !_perms.can(widget.permission, 'update') && !_perms.isSuperAdmin) {
      showPmsSnack(context, 'No update permission', error: true);
      return;
    }
    if (!isEdit && !_perms.can(widget.permission, 'create') && !_perms.isSuperAdmin) {
      showPmsSnack(context, 'No create permission', error: true);
      return;
    }

    final controllers = {
      for (final f in widget.fields) f.key: TextEditingController(),
    };
    final extras = <String, dynamic>{};
    if (row != null) {
      if (widget.hydrate != null) {
        widget.hydrate!(row, controllers, extras);
      } else {
        for (final f in widget.fields) {
          final v = row[f.key];
          controllers[f.key]!.text = v?.toString() ?? '';
        }
      }
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return Padding(
              padding: AppTheme.sheetPadding(ctx),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isEdit ? 'Edit ${widget.title}' : 'Add ${widget.title}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final f in widget.fields) ...[
                      TextFormField(
                        controller: controllers[f.key],
                        keyboardType: f.keyboardType,
                        maxLines: f.maxLines,
                        obscureText: f.obscure,
                        decoration: InputDecoration(
                          labelText: f.required ? '${f.label} *' : f.label,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (widget.extraFormBuilder != null)
                      widget.extraFormBuilder!(
                        context,
                        controllers,
                        extras,
                        setLocal,
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        for (final f in widget.fields) {
                          if (f.required &&
                              controllers[f.key]!.text.trim().isEmpty) {
                            showPmsSnack(
                              context,
                              '${f.label} is required',
                              error: true,
                            );
                            return;
                          }
                        }
                        final payload = widget.buildPayload != null
                            ? widget.buildPayload!(controllers, extras)
                            : {
                                for (final f in widget.fields)
                                  f.key: controllers[f.key]!.text.trim(),
                              };
                        try {
                          if (isEdit) {
                            await widget.api.update(idOf(row)!, payload);
                          } else {
                            await widget.api.create(payload);
                          }
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } on ApiException catch (e) {
                          if (context.mounted) {
                            showPmsSnack(context, e.message, error: true);
                          }
                        }
                      },
                      child: Text(isEdit ? 'Save' : 'Create'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    for (final c in controllers.values) {
      c.dispose();
    }
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (!_perms.can(widget.permission, 'delete') && !_perms.isSuperAdmin) {
      showPmsSnack(context, 'No delete permission', error: true);
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Delete',
      message: 'Delete "${widget.titleOf(row)}"?',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await widget.api.delete(idOf(row)!);
      showPmsSnack(context, 'Deleted');
      _load();
    } on ApiException catch (e) {
      showPmsSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        _perms.can(widget.permission, 'create') || _perms.isSuperAdmin;
    final totalPages = (_pagination?['totalPages'] as num?)?.toInt() ?? 1;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () => _openForm(),
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppTheme.filterPadding,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.tune),
                  onPressed: () {
                    setState(() {
                      _search = _searchCtrl.text.trim();
                      _page = 1;
                    });
                    _load();
                  },
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                setState(() {
                  _search = v.trim();
                  _page = 1;
                });
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
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const CenteredScrollLoader()
                  : _items.isEmpty
                      ? EmptyListBody(message: 'No ${widget.title.toLowerCase()} found')
                      : ListView.separated(
                          padding: AppTheme.listPadding,
                          itemCount: _items.length + 1,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            if (i == _items.length) {
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: _page > 1
                                        ? () {
                                            setState(() => _page -= 1);
                                            _load();
                                          }
                                        : null,
                                    child: const Text('Prev'),
                                  ),
                                  Text('$_page / $totalPages'),
                                  TextButton(
                                    onPressed: _page < totalPages
                                        ? () {
                                            setState(() => _page += 1);
                                            _load();
                                          }
                                        : null,
                                    child: const Text('Next'),
                                  ),
                                ],
                              );
                            }
                            final row = _items[i];
                            return Card(
                              child: ListTile(
                                title: Text(widget.titleOf(row)),
                                subtitle: widget.subtitleOf != null
                                    ? Text(widget.subtitleOf!(row))
                                    : null,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') _openForm(row: row);
                                    if (v == 'delete') _delete(row);
                                  },
                                  itemBuilder: (_) => [
                                    if (_perms.can(widget.permission, 'update') ||
                                        _perms.isSuperAdmin)
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit'),
                                      ),
                                    if (_perms.can(widget.permission, 'delete') ||
                                        _perms.isSuperAdmin)
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text(
                                          'Delete',
                                          style: TextStyle(color: AppTheme.danger),
                                        ),
                                      ),
                                  ],
                                ),
                                onTap: () => _openForm(row: row),
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
