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

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  static const _permission = 'item';

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
      final res = await context.read<SettingsApis>().items.list({
        'page': _page,
        'limit': 20,
        'search': _search,
        'sortBy': 'item_name',
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

  Future<List<OptionItem>> _loadSubCategories(String? categoryId) async {
    final res = await context.read<SettingsApis>().subCategories.list({
      'limit': 200,
      'sortBy': 'subcategory_name',
      'sortOrder': 'asc',
      if (categoryId != null && categoryId.isNotEmpty) 'category': categoryId,
    });
    var rows = res.items;
    if (categoryId != null && categoryId.isNotEmpty) {
      rows = rows.where((r) {
        final cid = refId(r['category']);
        return cid.isEmpty || cid == categoryId;
      }).toList();
    }
    return mapToOptions(
      rows,
      labelOfRow: (r) => r['subcategory_name']?.toString() ?? labelOf(r),
    );
  }

  Future<List<OptionItem>> _loadUoms() async {
    final res = await context.read<SettingsApis>().uoms.list({
      'limit': 200,
      'sortBy': 'uom_name',
      'sortOrder': 'asc',
    });
    return mapToOptions(
      res.items,
      labelOfRow: (r) =>
          r['uom_name']?.toString() ?? r['unit']?.toString() ?? labelOf(r),
    );
  }

  Future<List<OptionItem>> _loadGsts() async {
    final res = await context.read<SettingsApis>().gsts.list({
      'limit': 200,
      'sortBy': 'gst_name',
      'sortOrder': 'asc',
    });
    return mapToOptions(
      res.items,
      labelOfRow: (r) {
        final name = r['gst_name']?.toString() ?? 'GST';
        final pct = r['gst_percentage'];
        return pct == null ? name : '$name ($pct%)';
      },
    );
  }

  Future<List<OptionItem>> _loadBrands() async {
    final res = await context.read<SettingsApis>().brands.list({
      'limit': 200,
      'sortBy': 'brand_name',
      'sortOrder': 'asc',
    });
    return mapToOptions(
      res.items,
      labelOfRow: (r) => r['brand_name']?.toString() ?? labelOf(r),
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

    final nameCtrl =
        TextEditingController(text: row?['item_name']?.toString() ?? '');
    final hsnCtrl = TextEditingController(
      text: (row?['HSNcode'] ?? row?['HSNCode'])?.toString() ?? '',
    );
    final specCtrl =
        TextEditingController(text: row?['specification']?.toString() ?? '');

    String? categoryId = refId(row?['category']);
    String categoryLabel = row?['category'] is Map
        ? (row!['category']['name']?.toString() ?? '')
        : '';
    String? subCategoryId = refId(row?['sub_category']);
    String subCategoryLabel = row?['sub_category'] is Map
        ? (row!['sub_category']['subcategory_name']?.toString() ?? '')
        : '';
    String? uomId = refId(row?['uom']);
    String uomLabel = row?['uom'] is Map
        ? (row!['uom']['uom_name']?.toString() ?? '')
        : '';
    String? gstId = refId(row?['gst']);
    String gstLabel = row?['gst'] is Map
        ? (row!['gst']['gst_name']?.toString() ?? '')
        : '';
    var brandIds = idsFromRefs(row?['brands']);

    List<OptionItem> categoryOptions = const [];
    List<OptionItem> subCategoryOptions = const [];
    List<OptionItem> uomOptions = const [];
    List<OptionItem> gstOptions = const [];
    List<OptionItem> brandOptions = const [];
    var optionsLoaded = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            if (!optionsLoaded) {
              optionsLoaded = true;
              Future.wait([
                _loadCategories(),
                _loadSubCategories(categoryId),
                _loadUoms(),
                _loadGsts(),
                _loadBrands(),
              ]).then((lists) {
                if (!ctx.mounted) return;
                setLocal(() {
                  categoryOptions = lists[0];
                  subCategoryOptions = lists[1];
                  uomOptions = lists[2];
                  gstOptions = lists[3];
                  brandOptions = lists[4];
                });
              });
            }

            Future<void> onCategoryPicked(OptionItem picked) async {
              setLocal(() {
                categoryId = picked.value;
                categoryLabel = picked.label;
                subCategoryId = null;
                subCategoryLabel = '';
                subCategoryOptions = const [];
              });
              final subs = await _loadSubCategories(picked.value);
              if (!ctx.mounted) return;
              setLocal(() => subCategoryOptions = subs);
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
                      isEdit ? 'Edit Item' : 'Add Item',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Item name *'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: hsnCtrl,
                      decoration: const InputDecoration(labelText: 'HSN code'),
                    ),
                    const SizedBox(height: 10),
                    PickerField(
                      label: 'Category',
                      valueLabel: categoryLabel,
                      onTap: () async {
                        final picked = await showOptionPicker(
                          context,
                          title: 'Select category',
                          options: categoryOptions,
                          selected: categoryId,
                        );
                        if (picked != null) await onCategoryPicked(picked);
                      },
                    ),
                    const SizedBox(height: 10),
                    PickerField(
                      label: 'Sub category',
                      valueLabel: subCategoryLabel,
                      enabled: (categoryId ?? '').isNotEmpty,
                      onTap: () async {
                        final picked = await showOptionPicker(
                          context,
                          title: 'Select sub category',
                          options: subCategoryOptions,
                          selected: subCategoryId,
                        );
                        if (picked == null) return;
                        setLocal(() {
                          subCategoryId = picked.value;
                          subCategoryLabel = picked.label;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    PickerField(
                      label: 'UOM',
                      valueLabel: uomLabel,
                      onTap: () async {
                        final picked = await showOptionPicker(
                          context,
                          title: 'Select UOM',
                          options: uomOptions,
                          selected: uomId,
                        );
                        if (picked == null) return;
                        setLocal(() {
                          uomId = picked.value;
                          uomLabel = picked.label;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    PickerField(
                      label: 'GST',
                      valueLabel: gstLabel,
                      onTap: () async {
                        final picked = await showOptionPicker(
                          context,
                          title: 'Select GST',
                          options: gstOptions,
                          selected: gstId,
                        );
                        if (picked == null) return;
                        setLocal(() {
                          gstId = picked.value;
                          gstLabel = picked.label;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    MultiSelectField(
                      label: 'Brands',
                      options: brandOptions,
                      selectedIds: brandIds,
                      onChanged: (ids) => setLocal(() => brandIds = ids),
                    ),
                    TextFormField(
                      controller: specCtrl,
                      maxLines: 3,
                      decoration:
                          const InputDecoration(labelText: 'Specification'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        if (nameCtrl.text.trim().isEmpty) {
                          showPmsSnack(
                            context,
                            'Item name is required',
                            error: true,
                          );
                          return;
                        }
                        final payload = <String, dynamic>{
                          'item_name': nameCtrl.text.trim(),
                          'HSNcode': hsnCtrl.text.trim(),
                          'specification': specCtrl.text.trim(),
                          'brands': brandIds,
                          if ((categoryId ?? '').isNotEmpty)
                            'category': categoryId,
                          if ((subCategoryId ?? '').isNotEmpty)
                            'sub_category': subCategoryId,
                          if ((uomId ?? '').isNotEmpty) 'uom': uomId,
                          if ((gstId ?? '').isNotEmpty) 'gst': gstId,
                        };
                        try {
                          final api = context.read<SettingsApis>().items;
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
    hsnCtrl.dispose();
    specCtrl.dispose();
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (!_perms.can(_permission, 'delete') && !_perms.isSuperAdmin) {
      showPmsSnack(context, 'No delete permission', error: true);
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Delete item',
      message: 'Delete "${row['item_name'] ?? 'item'}"?',
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await context.read<SettingsApis>().items.delete(idOf(row)!);
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
      appBar: AppBar(title: const Text('Items')),
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
                            EmptyState(message: 'No items found'),
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
                                  row['item_name']?.toString() ?? 'Item',
                                ),
                                subtitle: Text(
                                  [
                                    (row['HSNcode'] ?? row['HSNCode'])
                                            ?.toString() ??
                                        '',
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
