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

class SubCategoriesScreen extends StatefulWidget {
  const SubCategoriesScreen({super.key});

  @override
  State<SubCategoriesScreen> createState() => _SubCategoriesScreenState();
}

class _SubCategoriesScreenState extends State<SubCategoriesScreen> {
  static const _permission = 'subcategory';

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
      final res = await context.read<SettingsApis>().subCategories.list({
        'page': _page,
        'limit': 20,
        'search': _search,
        'sortBy': 'subcategory_name',
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

  Future<List<OptionItem>> _loadCategories() async {
    final res = await context.read<SettingsApis>().categories.list({
      'limit': 200,
      'sortBy': 'name',
      'sortOrder': 'asc',
    });
    return mapToOptions(
      res.items,
      labelOfRow: (r) => r['name']?.toString() ?? labelOf(r),
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

    final nameCtrl = TextEditingController(
      text: row?['subcategory_name']?.toString() ?? '',
    );
    final codeCtrl = TextEditingController(
      text: row?['subcategory_code']?.toString() ?? '',
    );
    String? categoryId = refId(row?['category']);
    String categoryLabel = row?['category'] is Map
        ? (row!['category']['name']?.toString() ?? '')
        : '';
    List<OptionItem> categoryOptions = const [];
    var optionsLoaded = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            if (!optionsLoaded) {
              optionsLoaded = true;
              _loadCategories().then((opts) {
                if (!ctx.mounted) return;
                setLocal(() {
                  categoryOptions = opts;
                  if ((categoryId ?? '').isNotEmpty && categoryLabel.isEmpty) {
                    final match =
                        opts.where((o) => o.value == categoryId).toList();
                    if (match.isNotEmpty) categoryLabel = match.first.label;
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
                      isEdit ? 'Edit Sub Category' : 'Add Sub Category',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Subcategory name *',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Subcategory code *',
                      ),
                    ),
                    const SizedBox(height: 10),
                    PickerField(
                      label: 'Category',
                      required: true,
                      valueLabel: categoryLabel,
                      onTap: () async {
                        final picked = await showOptionPicker(
                          context,
                          title: 'Select category',
                          options: categoryOptions,
                          selected: categoryId,
                        );
                        if (picked == null) return;
                        setLocal(() {
                          categoryId = picked.value;
                          categoryLabel = picked.label;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        if (nameCtrl.text.trim().isEmpty) {
                          showPmsSnack(
                            context,
                            'Subcategory name is required',
                            error: true,
                          );
                          return;
                        }
                        if (codeCtrl.text.trim().isEmpty) {
                          showPmsSnack(
                            context,
                            'Subcategory code is required',
                            error: true,
                          );
                          return;
                        }
                        if (categoryId == null || categoryId!.isEmpty) {
                          showPmsSnack(
                            context,
                            'Category is required',
                            error: true,
                          );
                          return;
                        }
                        final payload = {
                          'subcategory_name': nameCtrl.text.trim(),
                          'subcategory_code': codeCtrl.text.trim(),
                          'category': categoryId,
                        };
                        try {
                          final api =
                              context.read<SettingsApis>().subCategories;
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
    codeCtrl.dispose();
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (!_perms.can(_permission, 'delete') && !_perms.isSuperAdmin) {
      showPmsSnack(context, 'No delete permission', error: true);
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Delete sub category',
      message: 'Delete "${row['subcategory_name'] ?? 'sub category'}"?',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await context.read<SettingsApis>().subCategories.delete(idOf(row)!);
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
      appBar: AppBar(title: const Text('Sub Categories')),
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
                            EmptyState(message: 'No sub categories found'),
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
                            final cat = row['category'] is Map
                                ? row['category']['name']?.toString()
                                : null;
                            return Card(
                              child: ListTile(
                                title: Text(
                                  row['subcategory_name']?.toString() ??
                                      'Sub category',
                                ),
                                subtitle: Text(
                                  [
                                    row['subcategory_code']?.toString() ?? '',
                                    if (cat != null && cat.isNotEmpty) cat,
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
