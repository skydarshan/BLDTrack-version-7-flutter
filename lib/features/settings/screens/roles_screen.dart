import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/widgets/sort_menu.dart';
import '../../../core/utils/form_validation_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../org/org_session.dart';
import '../../pms/utils/structure_access.dart';
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
  'dpr',
  'projectstructure',
  'projectmodel',
];

const _crudActions = ['create', 'read', 'update', 'delete'];

const _dprPermissionHints = {
  'create': 'Start a new daily report draft for a site and date.',
  'read': 'Open history, today, missing boards, and read-only detail.',
  'update': 'Edit draft or sent-back reports; save sections and media.',
  'delete': 'Remove draft reports only (submitted reports stay locked).',
  'submit': 'File a report for approval after the draft is complete.',
  'approve': 'Use the DPR approval inbox, approve/revise, and remind missing sites.',
};

String? _dprPermissionHint(String action) => _dprPermissionHints[action];

String _actionLabel(String action) {
  switch (action) {
    case 'read':
      return 'Read';
    case 'create':
      return 'Create';
    case 'update':
      return 'Update';
    case 'delete':
      return 'Delete';
    case 'submit':
      return 'Submit';
    case 'approve':
      return 'Approve';
    default:
      return action;
  }
}

/// Notes from the Project Structure guide for the role matrix.
String? _moduleHint(String module) {
  switch (module) {
    case 'projectstructure':
      return 'Read, create, update and delete buildings, floors and units.';
    case 'projectmodel':
      return 'Read opens the 3D viewer. Create, update and delete are not used.';
    case 'activity':
      return 'Granted with Project Management. Activities are also task work types.';
    default:
      return null;
  }
}

List<String> _actionsForModule(String module) {
  if (module == 'dpr') {
    return const ['create', 'read', 'update', 'delete', 'submit', 'approve'];
  }
  // Progress Model only checks read. Create, update and delete are unused.
  if (module == 'projectmodel') return const ['read'];
  return _crudActions;
}

Map<String, bool> _parseModulePermissions(Map<String, dynamic> mp) {
  return Map<String, bool>.from(
    (mp['permissions'] as Map).map(
      (k, v) => MapEntry(k.toString(), v == true),
    ),
  );
}

bool _moduleFullySelected(String module, Map<String, bool> perms) =>
    _actionsForModule(module).every((a) => perms[a] == true);

bool _modulePartiallySelected(String module, Map<String, bool> perms) {
  final actions = _actionsForModule(module);
  final selected = actions.where((a) => perms[a] == true).length;
  return selected > 0 && selected < actions.length;
}

bool _allPermissionsSelected(List<Map<String, dynamic>> matrix) {
  if (matrix.isEmpty) return false;
  return matrix.every((mp) {
    final module = mp['module']?.toString() ?? '';
    return _moduleFullySelected(module, _parseModulePermissions(mp));
  });
}

bool _somePermissionsSelected(List<Map<String, dynamic>> matrix) {
  var any = false;
  for (final mp in matrix) {
    final module = mp['module']?.toString() ?? '';
    final perms = _parseModulePermissions(mp);
    if (_actionsForModule(module).any((a) => perms[a] == true)) {
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
  final module = next[index]['module']?.toString() ?? '';
  next[index] = {
    'module': module,
    'permissions': {for (final a in _actionsForModule(module)) a: checked},
  };
  return next;
}

List<Map<String, dynamic>> _setAllPermissions(
  List<Map<String, dynamic>> matrix,
  bool checked,
) {
  return matrix
      .map(
        (mp) {
          final module = mp['module']?.toString() ?? '';
          return {
            'module': module,
            'permissions': {for (final a in _actionsForModule(module)) a: checked},
          };
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
  String _sortBy = 'name';
  String _sortOrder = 'asc';
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
        'sortBy': _sortBy,
        'sortOrder': _sortOrder,
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

  Map<String, bool> _blankPerms(String module) => {
        for (final a in _actionsForModule(module)) a: false,
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
    final candidates = (_perms.isSuperAdmin
            ? <String>{..._modules, ...byModule.keys}
            : editable.intersection({..._modules, ...byModule.keys}.toSet()))
        .where(
          (module) => offerRolePermissionModule(
            module,
            org,
            alreadyOnRole: byModule.containsKey(module),
          ),
        )
        .toList()
      ..sort();
    final visibleModules = candidates;
    return visibleModules.map((m) {
      final existingMp = byModule[m];
      final perms = _blankPerms(m);
      final raw = existingMp?['permissions'];
      if (raw is Map) {
        for (final a in _actionsForModule(m)) {
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
    final fieldErrors = FieldErrors();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return Padding(
              padding: AppTheme.sheetPadding(ctx),
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
                      decoration: InputDecoration(
                        labelText: 'Name *',
                        errorText: fieldErrors['name'],
                      ),
                    ),
                    const SizedBox(height: 8),
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
                          final actions = _actionsForModule(module);
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
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              formatModuleLabel(module),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (_moduleHint(module) != null)
                                              Text(
                                                _moduleHint(module)!,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppTheme.muted,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Checkbox(
                                        tristate: true,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        value: _moduleFullySelected(module, perms)
                                            ? true
                                            : (_modulePartiallySelected(module, perms)
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
                                              !_moduleFullySelected(module, perms);
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
                                      for (final action in actions)
                                        FilterChip(
                                          label: Text(_actionLabel(action)),
                                          tooltip: module == 'dpr' ? _dprPermissionHint(action) : null,
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
                        fieldErrors.clear();
                        fieldErrors.set('name', requiredText(nameCtrl.text, 'Name'));
                        if (fieldErrors.hasErrors) {
                          setLocal(() {});
                          showPmsSnack(context, fieldErrors.messages.first, error: true);
                          return;
                        }
                        final name = nameCtrl.text.trim();
                        final description = descCtrl.text.trim();
                        final permissions = _mergeMatrixForSave(matrix, existing);
                        try {
                          final api = context.read<SettingsApis>().roles;
                          if (isEdit) {
                            await api.update(idOf(row)!, {
                              'name': name,
                              'description': description,
                              'modulePermissions': permissions,
                            });
                          } else {
                            final created = await api.create({
                              'name': name,
                              'description': description,
                            });
                            final createdId = idOf(created);
                            if (createdId != null && permissions.isNotEmpty) {
                              await api.update(createdId, {
                                'modulePermissions': permissions,
                              });
                            }
                          }
                          if (!context.mounted) return;
                          await showSavedConfirmation(
                            context,
                            isEdit ? 'Role updated' : 'Role created',
                          );
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } on ApiException catch (e) {
                          if (!context.mounted) return;
                          setLocal(() {
                            for (final entry in apiFieldErrors(e).entries) {
                              fieldErrors.set(entry.key, entry.value);
                            }
                          });
                          showPmsSnack(context, formatApiErrorSummary(e), error: true);
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
      appBar: AppBar(
        title: const Text('Roles & Permissions'),
        actions: [
          SortMenuButton(
            choices: nameSortChoices('name', 'Role'),
            sortBy: _sortBy,
            sortOrder: _sortOrder,
            onSelected: (by, order) {
              setState(() {
                _sortBy = by;
                _sortOrder = order;
                _page = 1;
              });
              _load();
            },
          ),
        ],
      ),
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
                  ? const CenteredScrollLoader()
                  : _items.isEmpty
                      ? EmptyListBody(message: 'No roles found')
                      : ListView.separated(
                          padding: AppTheme.listPadding,
                          itemCount: _items.length + 1,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
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
