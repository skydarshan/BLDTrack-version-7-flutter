import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../pms/widgets/pickers.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../services/settings_apis.dart';
import '../utils/permissions.dart';
import 'settings_form_widgets.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  static const _permission = 'user';

  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _pagination;
  bool _loading = true;
  String? _error;
  int _page = 1;
  String _search = '';

  Permissions get _perms => Permissions(context.read<AuthProvider>().user);
  String? get _selfId => context.read<AuthProvider>().user?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
      final api = context.read<SettingsApis>();
      final res = await api.users.list({
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

  Future<List<OptionItem>> _loadRoles() async {
    final res = await context.read<SettingsApis>().roles.list({
      'limit': 200,
      'sortBy': 'name',
      'sortOrder': 'asc',
    });
    final isSa = _perms.isSuperAdmin;
    return mapToOptions(
      res.items.where((r) {
        final name = (r['name']?.toString() ?? '').trim().toLowerCase();
        if (name == 'super admin' && !isSa) return false;
        return true;
      }).toList(),
      labelOfRow: (r) => r['name']?.toString() ?? 'Role',
    );
  }

  Future<List<OptionItem>> _loadSites() async {
    final res = await context.read<SettingsApis>().sites.list({
      'limit': 200,
      'sortBy': 'site_name',
      'sortOrder': 'asc',
    });
    return mapToOptions(
      res.items,
      labelOfRow: (r) => r['site_name']?.toString() ?? labelOf(r),
    );
  }

  Future<void> _openForm({Map<String, dynamic>? row}) async {
    final isEdit = row != null;
    if (isEdit && !_perms.can(_permission, 'update') && !_perms.isSuperAdmin) {
      showPmsSnack(context, 'No update permission', error: true);
      return;
    }
    if (!isEdit && !_perms.can(_permission, 'create') && !_perms.isSuperAdmin) {
      showPmsSnack(context, 'No create permission', error: true);
      return;
    }

    final nameCtrl = TextEditingController(text: row?['name']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: row?['phone']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: row?['email']?.toString() ?? '');
    final passwordCtrl = TextEditingController();
    String? roleId = refId(row?['role']);
    String roleLabel = row?['role'] is Map
        ? (row!['role']['name']?.toString() ?? '')
        : '';
    var siteIds = idsFromRefs(row?['sites']);

    List<OptionItem> roleOptions = const [];
    List<OptionItem> siteOptions = const [];
    var optionsLoaded = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            if (!optionsLoaded) {
              optionsLoaded = true;
              Future.wait([_loadRoles(), _loadSites()]).then((lists) {
                if (!ctx.mounted) return;
                setLocal(() {
                  roleOptions = lists[0];
                  siteOptions = lists[1];
                  if (roleId != null && roleId!.isNotEmpty && roleLabel.isEmpty) {
                    final match = roleOptions.where((o) => o.value == roleId);
                    if (match.isNotEmpty) roleLabel = match.first.label;
                  }
                });
              });
            }
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isEdit ? 'Edit User' : 'Add User',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name *'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone *'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email *'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: passwordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: isEdit
                            ? 'Password (optional)'
                            : 'Password *',
                      ),
                    ),
                    const SizedBox(height: 10),
                    PickerField(
                      label: 'Role',
                      required: true,
                      valueLabel: roleLabel,
                      onTap: () async {
                        final picked = await showOptionPicker(
                          context,
                          title: 'Select role',
                          options: roleOptions,
                          selected: roleId,
                        );
                        if (picked == null) return;
                        setLocal(() {
                          roleId = picked.value;
                          roleLabel = picked.label;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    MultiSelectField(
                      label: 'Sites',
                      options: siteOptions,
                      selectedIds: siteIds,
                      onChanged: (ids) => setLocal(() => siteIds = ids),
                    ),
                    FilledButton(
                      onPressed: () async {
                        if (nameCtrl.text.trim().isEmpty) {
                          showPmsSnack(context, 'Name is required', error: true);
                          return;
                        }
                        if (phoneCtrl.text.trim().isEmpty) {
                          showPmsSnack(context, 'Phone is required', error: true);
                          return;
                        }
                        if (emailCtrl.text.trim().isEmpty) {
                          showPmsSnack(context, 'Email is required', error: true);
                          return;
                        }
                        if (!isEdit && passwordCtrl.text.isEmpty) {
                          showPmsSnack(
                            context,
                            'Password is required',
                            error: true,
                          );
                          return;
                        }
                        if (roleId == null || roleId!.isEmpty) {
                          showPmsSnack(context, 'Role is required', error: true);
                          return;
                        }
                        final payload = <String, dynamic>{
                          'name': nameCtrl.text.trim(),
                          'phone': phoneCtrl.text.trim(),
                          'email': emailCtrl.text.trim().toLowerCase(),
                          'role': roleId,
                          'sites': siteIds,
                        };
                        final pwd = passwordCtrl.text;
                        if (!isEdit) {
                          payload['password'] = pwd;
                        } else if (pwd.trim().isNotEmpty) {
                          payload['password'] = pwd;
                        }
                        try {
                          final api = context.read<SettingsApis>().users;
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
    phoneCtrl.dispose();
    emailCtrl.dispose();
    passwordCtrl.dispose();
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (!_perms.can(_permission, 'delete') && !_perms.isSuperAdmin) {
      showPmsSnack(context, 'No delete permission', error: true);
      return;
    }
    final id = idOf(row);
    if (id != null && _selfId != null && id == _selfId) {
      showPmsSnack(context, 'You cannot delete your own account', error: true);
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Delete user',
      message: 'Delete "${row['name'] ?? 'user'}"?',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await context.read<SettingsApis>().users.delete(id!);
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
      appBar: AppBar(title: const Text('Users')),
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
                            EmptyState(message: 'No users found'),
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
                            final roleName = row['role'] is Map
                                ? row['role']['name']?.toString()
                                : row['roleName']?.toString();
                            final isSelf =
                                idOf(row) != null && idOf(row) == _selfId;
                            return Card(
                              child: ListTile(
                                title: Text(row['name']?.toString() ?? 'User'),
                                subtitle: Text(
                                  [
                                    row['email']?.toString() ?? '',
                                    if (roleName != null && roleName.isNotEmpty)
                                      roleName,
                                  ].where((e) => e.isNotEmpty).join(' · '),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') _openForm(row: row);
                                    if (v == 'delete') _delete(row);
                                  },
                                  itemBuilder: (_) => [
                                    if (_perms.can(_permission, 'update') ||
                                        _perms.isSuperAdmin)
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit'),
                                      ),
                                    if ((!isSelf) &&
                                        (_perms.can(_permission, 'delete') ||
                                            _perms.isSuperAdmin))
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text(
                                          'Delete',
                                          style:
                                              TextStyle(color: AppTheme.danger),
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
