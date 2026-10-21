import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/form_validation_helpers.dart';
import '../../auth/providers/auth_provider.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../services/settings_apis.dart';
import '../utils/permissions.dart';
import 'settings_form_widgets.dart';

/// Permission-module catalog. Mirrors the website Modules page
/// (list + create). Product on/off stays on Organization.
class ModulesScreen extends StatefulWidget {
  const ModulesScreen({super.key});

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  static const _permission = 'module';
  static final _namePattern = RegExp(r'^[a-z][a-z0-9_-]*$');

  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _pagination;
  bool _loading = true;
  String? _error;
  int _page = 1;

  Permissions get _perms => Permissions(context.read<AuthProvider>().user);

  bool get _canRead => _perms.can(_permission, 'read') || _perms.isSuperAdmin;

  bool get _canCreate => _perms.can(_permission, 'create') || _perms.isSuperAdmin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!_canRead) {
      setState(() {
        _loading = false;
        _error = null;
        _items = [];
        _pagination = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await context.read<SettingsApis>().modules.list({
        'page': _page,
        'limit': 20,
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

  String? _validateName(String raw) {
    final name = raw.trim().toLowerCase();
    if (name.isEmpty) return 'Module name is required';
    if (!_namePattern.hasMatch(name)) {
      return 'Must start with letter, lowercase letters, numbers, hyphens or underscores only';
    }
    if (name.length > 64) return 'Max 64 characters';
    return null;
  }

  String? _validateDisplayName(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'Display name is required';
    if (value.length < 2) return 'Min 2 characters';
    if (value.length > 120) return 'Max 120 characters';
    return null;
  }

  String? _validateDescription(String raw) {
    if (raw.trim().length > 2000) return 'Description is too long';
    return null;
  }

  Future<void> _openCreate() async {
    if (!_canCreate) {
      showPmsSnack(context, 'No create permission', error: true);
      return;
    }

    final nameCtrl = TextEditingController();
    final displayCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    final fieldErrors = <String, String>{};

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
                    const Text(
                      'Add Module',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Module Name *',
                        hintText: 'e.g. invoice',
                        errorText: fieldErrors['name'],
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: displayCtrl,
                      decoration: InputDecoration(
                        labelText: 'Display Name *',
                        hintText: 'e.g. Invoices',
                        errorText: fieldErrors['displayName'],
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: descriptionCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        hintText: 'Optional description',
                        errorText: fieldErrors['description'],
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        fieldErrors
                          ..clear()
                          ..['name'] = _validateName(nameCtrl.text) ?? ''
                          ..['displayName'] = _validateDisplayName(displayCtrl.text) ?? ''
                          ..['description'] = _validateDescription(descriptionCtrl.text) ?? '';
                        fieldErrors.removeWhere((_, message) => message.isEmpty);
                        if (fieldErrors.isNotEmpty) {
                          setLocal(() {});
                          showPmsSnack(context, fieldErrors.values.first, error: true);
                          return;
                        }
                        try {
                          await context.read<SettingsApis>().modules.create({
                            'name': nameCtrl.text.trim().toLowerCase(),
                            'displayName': displayCtrl.text.trim(),
                            'description': descriptionCtrl.text.trim(),
                          });
                          if (!context.mounted) return;
                          await showSavedConfirmation(context, 'Module created successfully');
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } on ApiException catch (e) {
                          if (!context.mounted) return;
                          setLocal(() {
                            fieldErrors
                              ..clear()
                              ..addAll(apiFieldErrors(e));
                          });
                          showPmsSnack(context, formatApiErrorSummary(e), error: true);
                        }
                      },
                      child: const Text('Create'),
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
    displayCtrl.dispose();
    descriptionCtrl.dispose();
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = (_pagination?['totalPages'] as num?)?.toInt() ?? 1;
    final denied = !_canRead && !_canCreate;

    return Scaffold(
      appBar: AppBar(title: const Text('Modules')),
      floatingActionButton: _canCreate
          ? FloatingActionButton(
              onPressed: _openCreate,
              child: const Icon(Icons.add),
            )
          : null,
      body: denied
          ? const EmptyListBody(message: 'You do not have permission to view this.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: ErrorBanner(message: _error!, onRetry: _load),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: _loading
                        ? const CenteredScrollLoader()
                        : !_canRead
                            ? const EmptyListBody(message: 'No permission to view modules')
                            : _items.isEmpty
                                ? const EmptyListBody(message: 'No modules yet')
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
                                      final name = row['name']?.toString() ?? '—';
                                      final display = row['displayName']?.toString().trim();
                                      final description = row['description']?.toString().trim();
                                      return Card(
                                        child: ListTile(
                                          title: Text(
                                            display == null || display.isEmpty ? name : display,
                                          ),
                                          subtitle: Text(
                                            [
                                              name,
                                              if (description != null && description.isNotEmpty)
                                                description,
                                            ].join('\n'),
                                          ),
                                          isThreeLine: description != null && description.isNotEmpty,
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
