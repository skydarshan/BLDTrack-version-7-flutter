import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../org/org_session.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../services/settings_apis.dart';
import '../utils/permissions.dart';
import 'settings_form_widgets.dart';

const _defaultModules = [
  'user',
  'role',
  'organization',
  'location',
  'company',
  'site',
  'sitestaff',
  'contractor',
  'activity',
  'subactivity',
  'uom',
  'gst',
  'brand',
  'category',
  'subcategory',
  'vendor',
  'item',
  'miscellaneousconfig',
  'auditlog',
  'project',
  'task',
  'projecttemplate',
  'taskprogress',
];

const _crudActions = ['create', 'read', 'update', 'delete'];

Map<String, bool> _parseModulePermissions(Map<String, dynamic> mp) {
  return Map<String, bool>.from(
    (mp['permissions'] as Map).map(
      (k, v) => MapEntry(k.toString(), v == true),
    ),
  );
}

bool _moduleFullySelected(Map<String, bool> perms) =>
    _crudActions.every((a) => perms[a] == true);

bool _modulePartiallySelected(Map<String, bool> perms) {
  final selected = _crudActions.where((a) => perms[a] == true).length;
  return selected > 0 && selected < _crudActions.length;
}

bool _allPermissionsSelected(List<Map<String, dynamic>> matrix) {
  if (matrix.isEmpty) return false;
  return matrix.every((mp) => _moduleFullySelected(_parseModulePermissions(mp)));
}

bool _somePermissionsSelected(List<Map<String, dynamic>> matrix) {
  var any = false;
  for (final mp in matrix) {
    final perms = _parseModulePermissions(mp);
    if (_crudActions.any((a) => perms[a] == true)) {
      any = true;
      break;
    }
  }
  return any && !_allPermissionsSelected(matrix);
}

List<Map<String, dynamic>> _setModulePermissionsAll(
  List<Map<String, dynamic>> matrix,
  int index,
  bool checked,
) {
  final next = List<Map<String, dynamic>>.from(matrix);
  next[index] = {
    'module': next[index]['module'],
    'permissions': {for (final a in _crudActions) a: checked},
  };
  return next;
}

List<Map<String, dynamic>> _setAllPermissions(
  List<Map<String, dynamic>> matrix,
  bool checked,
) {
  return matrix
      .map(
        (mp) => {
          'module': mp['module'],
          'permissions': {for (final a in _crudActions) a: checked},
        },
      )
      .toList();
}

class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  static const _permission = 'role';

  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _pagination;
  bool _loading = true;
  String? _error;
  int _page = 1;
  String _search = '';
  List<String> _modules = List.of(_defaultModules);

  Permissions get _perms => Permissions(context.read<AuthProvider>().user);

  bool _isSuperAdminRole(Map<String, dynamic> role) {
    final name = (role['name']?.toString() ?? '').trim().toLowerCase();
    return name == 'super admin';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadModules();
      _load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadModules() async {
    try {
      final list = await context.read<SettingsApis>().listModules();
      final names = list
          .map((m) => (m['name'] ?? m['module'])?.toString().toLowerCase())
          .whereType<String>()
          .where((n) => n.isNotEmpty)
          .toList();
      if (names.isEmpty || !mounted) return;
      final merged = <String>{..._defaultModules, ...names}.toList()..sort();
      setState(() => _modules = merged);
    } catch (_) {
      // keep defaults
    }
  }

  Future<void> _load() async {
    if (!_perms.can(_permission, 'read') && !_perms.isSuperAdmin) {
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
      final res = await context.read<SettingsApis>().roles.list({
        'page': _page,
        'limit': 20,
        'search': _search,
        'sortBy': 'name',
        'sortOrder': 'asc',
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

  Map<String, bool> _blankPerms() => {
        for (final a in _crudActions) a: false,
      };

  List<Map<String, dynamic>> _initialMatrix([
    List<Map<String, dynamic>>? existing,
  ]) {
    final org = context.read<OrgSession>().organization;
    final editable = _perms.editablePermissionModules(org);
    final byModule = <String, Map<String, dynamic>>{};
    for (final mp in existing ?? const []) {
      final mod = mp['module']?.toString();
      if (mod == null || mod.isEmpty) continue;
      byModule[mod] = Map<String, dynamic>.from(mp);
    }
    final visibleModules = (_perms.isSuperAdmin
            ? <String>{..._modules, ...byModule.keys}
            : editable.intersection({..._modules, ...byModule.keys}.toSet()))
        .toList()
      ..sort();
    return visibleModules.map((m) {
      final existingMp = byModule[m];
      final perms = _blankPerms();
      final raw = existingMp?['permissions'];
      if (raw is Map) {
        for (final a in _crudActions) {
          perms[a] = raw[a] == true;
        }
      }
      return {'module': m, 'permissions': perms};
    }).toList();
  }

  List<Map<String, dynamic>> _mergeMatrixForSave(
    List<Map<String, dynamic>> edited,
    List<Map<String, dynamic>>? existing,
  ) {
    if (_perms.isSuperAdmin) return edited;
    final org = context.read<OrgSession>().organization;
    final editable = _perms.editablePermissionModules(org);
    final byModule = <String, Map<String, dynamic>>{};
    for (final mp in existing ?? const []) {
      final mod = mp['module']?.toString();
      if (mod != null && mod.isNotEmpty) {
        byModule[mod] = Map<String, dynamic>.from(mp);
      }
    }
    for (final mp in edited) {
      final mod = mp['module']?.toString();
      if (mod != null && editable.contains(mod)) {
        byModule[mod] = mp;
      }
    }
    return byModule.values.toList();
  }

  Future<void> _openForm({Map<String, dynamic>? row}) async {
    final isEdit = row != null;
    if (isEdit && _isSuperAdminRole(row)) {
      showPmsSnack(context, 'Super Admin role cannot be edited', error: true);
      return;
    }
    if (isEdit && !_perms.can(_permission, 'update') && !_perms.isSuperAdmin) {
      showPmsSnack(context, 'No update permission', error: true);
      return;
    }
    if (!isEdit && !_perms.can(_permission, 'create') && !_perms.isSuperAdmin) {
      showPmsSnack(context, 'No create permission', error: true);
      return;
    }

    final nameCtrl = TextEditingController(text: row?['name']?.toString() ?? '');
    final descCtrl =
        TextEditingController(text: row?['description']?.toString() ?? '');
    final existing = (row?['modulePermissions'] is List)
        ? (row!['modulePermissions'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : null;
    var matrix = _initialMatrix(existing);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.88,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      isEdit ? 'Edit Role' : 'Add Role',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Name *'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration:
                          const InputDecoration(labelText: 'Description'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Module permissions',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: const Text(
                        'Select all permissions',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      tristate: true,
                      value: _allPermissionsSelected(matrix)
                          ? true
                          : (_somePermissionsSelected(matrix) ? null : false),
                      onChanged: (v) {
                        setLocal(() {
                          matrix = _setAllPermissions(matrix, v == true);
                        });
                      },
                    ),
                    const Divider(height: 1),
                    const SizedBox(height: 4),
                    Expanded(
                      child: ListView.builder(
                        itemCount: matrix.length,
                        itemBuilder: (_, i) {
                          final mp = matrix[i];
                          final module = mp['module']?.toString() ?? '';
                          final perms = _parseModulePermissions(mp);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          formatModuleLabel(module),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Checkbox(
                                        tristate: true,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        value: _moduleFullySelected(perms)
                                            ? true
                                            : (_modulePartiallySelected(perms)
                                                ? null
                                                : false),
                                        onChanged: (v) {
                                          setLocal(() {
                                            matrix = _setModulePermissionsAll(
                                              matrix,
                                              i,
                                              v == true,
                                            );
                                          });
                                        },
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          final selectAll =
                                              !_moduleFullySelected(perms);
                                          setLocal(() {
                                            matrix = _setModulePermissionsAll(
                                              matrix,
                                              i,
                                              selectAll,
                                            );
                                          });
                                        },
                                        child: const Text(
                                          'Select all',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Wrap(
                                    children: [
                                      for (final action in _crudActions)
                                        FilterChip(
                                          label: Text(action),
                                          selected: perms[action] == true,
                                          onSelected: (v) {
                                            setLocal(() {
                                              final next = List<
                                                  Map<String, dynamic>>.from(
                                                matrix,
                                              );
                                              final p = Map<String, bool>.from(
                                                (next[i]['permissions'] as Map)
                                                    .map(
                                                  (k, val) => MapEntry(
                                                    k.toString(),
                                                    val == true,
                                                  ),
                                                ),
                                              );
                                              p[action] = v;
                                              next[i] = {
                                                'module': module,
                                                'permissions': p,
                                              };
                                              matrix = next;
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () async {
                        if (nameCtrl.text.trim().isEmpty) {
                          showPmsSnack(
                            context,
                            'Name is required',
                            error: true,
                          );
                          return;
                        }
                        final payload = <String, dynamic>{
                          'name': nameCtrl.text.trim(),
                          'description': descCtrl.text.trim(),
                          'modulePermissions': _mergeMatrixForSave(matrix, existing),
                        };
                        try {
                          final api = context.read<SettingsApis>().roles;
                          if (isEdit) {
                            await api.update(idOf(row)!, payload);
                          } else {
                            await api.create(payload);
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

    nameCtrl.dispose();
    descCtrl.dispose();
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (_isSuperAdminRole(row)) {
      showPmsSnack(context, 'Super Admin role cannot be deleted', error: true);
      return;
    }
    if (!_perms.can(_permission, 'delete') && !_perms.isSuperAdmin) {
      showPmsSnack(context, 'No delete permission', error: true);
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Delete role',
      message: 'Delete "${row['name'] ?? 'role'}"?',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await context.read<SettingsApis>().roles.delete(idOf(row)!);
      showPmsSnack(context, 'Deleted');
      _load();
    } on ApiException catch (e) {
      showPmsSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        _perms.can(_permission, 'create') || _perms.isSuperAdmin;
    final totalPages = (_pagination?['totalPages'] as num?)?.toInt() ?? 1;

    return Scaffold(
      appBar: AppBar(title: const Text('Roles & Permissions')),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () => _openForm(),
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
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
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : _items.isEmpty
                      ? ListView(
                          children: const [
                            EmptyState(message: 'No roles found'),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                          itemCount: _items.length + 1,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            if (i == _items.length) {
                              return settingsPaginationRow(
                                page: _page,
                                totalPages: totalPages,
                                onPrev: _page > 1
                                    ? () {
                                        setState(() => _page -= 1);
                                        _load();
                                      }
                                    : null,
                                onNext: _page < totalPages
                                    ? () {
                                        setState(() => _page += 1);
                                        _load();
                                      }
                                    : null,
                              );
                            }
                            final row = _items[i];
                            final isSa = _isSuperAdminRole(row);
                            final permsCount =
                                (row['modulePermissions'] is List)
                                    ? (row['modulePermissions'] as List).length
                                    : 0;
                            return Card(
                              child: ListTile(
                                title: Text(row['name']?.toString() ?? 'Role'),
                                subtitle: Text(
                                  [
                                    if ((row['description']?.toString() ?? '')
                                        .isNotEmpty)
                                      row['description'].toString(),
                                    '$permsCount modules',
                                  ].join(' · '),
                                ),
                                trailing: isSa
                                    ? const Chip(label: Text('Protected'))
                                    : PopupMenuButton<String>(
                                        onSelected: (v) {
                                          if (v == 'edit') _openForm(row: row);
                                          if (v == 'delete') _delete(row);
                                        },
                                        itemBuilder: (_) => [
                                          if (_perms.can(
                                                  _permission, 'update') ||
                                              _perms.isSuperAdmin)
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Edit'),
                                            ),
                                          if (_perms.can(
                                                  _permission, 'delete') ||
                                              _perms.isSuperAdmin)
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Text(
                                                'Delete',
                                                style: TextStyle(
                                                  color: AppTheme.danger,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                onTap: isSa ? null : () => _openForm(row: row),
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
