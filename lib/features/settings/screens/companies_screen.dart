import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../services/settings_apis.dart';
import '../utils/permissions.dart';
import 'settings_form_widgets.dart';

class CompaniesScreen extends StatefulWidget {
  const CompaniesScreen({super.key});

  @override
  State<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends State<CompaniesScreen> {
  static const _permission = 'company';

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
      final res = await context.read<SettingsApis>().companies.list({
        'page': _page,
        'limit': 20,
        'search': _search,
        'sortBy': 'companyName',
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

    final nameCtrl =
        TextEditingController(text: row?['companyName']?.toString() ?? '');
    final codeCtrl = TextEditingController(text: row?['code']?.toString() ?? '');
    final contactCtrl =
        TextEditingController(text: row?['contact_person']?.toString() ?? '');
    final phoneCtrl =
        TextEditingController(text: row?['phone_number']?.toString() ?? '');
    final gstCtrl =
        TextEditingController(text: row?['gst_number']?.toString() ?? '');
    final panCtrl =
        TextEditingController(text: row?['pan_number']?.toString() ?? '');
    var address = addressFrom(row?['address']);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: AppTheme.sheetPadding(ctx),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEdit ? 'Edit Company' : 'Add Company',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Company name *'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'Code'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: contactCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Contact person'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration:
                      const InputDecoration(labelText: 'Phone number'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: gstCtrl,
                  decoration: const InputDecoration(labelText: 'GST number'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: panCtrl,
                  decoration: const InputDecoration(labelText: 'PAN number'),
                ),
                AddressFields(
                  values: address,
                  onChanged: (k, v) => address[k] = v,
                ),
                FilledButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) {
                      showPmsSnack(
                        context,
                        'Company name is required',
                        error: true,
                      );
                      return;
                    }
                    final payload = {
                      'companyName': nameCtrl.text.trim(),
                      'code': codeCtrl.text.trim(),
                      'contact_person': contactCtrl.text.trim(),
                      'phone_number': phoneCtrl.text.trim(),
                      'gst_number': gstCtrl.text.trim(),
                      'pan_number': panCtrl.text.trim(),
                      'address': address,
                    };
                    try {
                      final api = context.read<SettingsApis>().companies;
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

    nameCtrl.dispose();
    codeCtrl.dispose();
    contactCtrl.dispose();
    phoneCtrl.dispose();
    gstCtrl.dispose();
    panCtrl.dispose();
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (!_perms.can(_permission, 'delete') && !_perms.isSuperAdmin) {
      showPmsSnack(context, 'No delete permission', error: true);
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Delete company',
      message: 'Delete "${row['companyName'] ?? 'company'}"?',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await context.read<SettingsApis>().companies.delete(idOf(row)!);
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
      appBar: AppBar(title: const Text('Companies')),
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
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : _items.isEmpty
                      ? ListView(
                          children: const [
                            EmptyState(message: 'No companies found'),
                          ],
                        )
                      : ListView.separated(
                          padding: AppTheme.listPadding,
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
                            return Card(
                              child: ListTile(
                                title: Text(
                                  row['companyName']?.toString() ?? 'Company',
                                ),
                                subtitle: Text(
                                  [
                                    row['code']?.toString() ?? '',
                                    row['contact_person']?.toString() ?? '',
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
                                    if (_perms.can(_permission, 'delete') ||
                                        _perms.isSuperAdmin)
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
