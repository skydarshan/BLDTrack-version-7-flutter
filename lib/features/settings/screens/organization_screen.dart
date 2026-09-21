import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/org/org_modules.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../org/org_session.dart';
import '../../org/widgets/module_entitlements_editor.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../services/settings_apis.dart';
import '../utils/permissions.dart';

class OrganizationScreen extends StatefulWidget {
  const OrganizationScreen({super.key});

  @override
  State<OrganizationScreen> createState() => _OrganizationScreenState();
}

class _OrganizationScreenState extends State<OrganizationScreen> {
  static const _permission = 'organization';

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _modules = buildDefaultModules();
  Map<String, dynamic> _savedModules = buildDefaultModules();
  Map<String, dynamic>? _org;
  List<Map<String, dynamic>> _roles = [];

  int _rrSteps = 0;
  String _rrStep1 = '';
  String _rrStep2 = '';
  int _rateSteps = 0;
  String _rateStep1 = '';
  String _rateStep2 = '';
  int _taskSteps = 0;
  String _taskStep1 = '';
  String _taskStep2 = '';

  Permissions get _perms => Permissions(context.read<AuthProvider>().user);

  String _roleId(dynamic raw) {
    if (raw == null) return '';
    if (raw is Map) {
      return (raw['_id'] ?? raw['id'] ?? '').toString();
    }
    return raw.toString();
  }

  void _loadApprovalsFromOrg(Map<String, dynamic>? org) {
    final rr = org?['procurement_config'] is Map
        ? org!['procurement_config']['rr_approval']
        : null;
    final rate = org?['procurement_config'] is Map
        ? org!['procurement_config']['rate_approval']
        : null;
    final task = org?['project_management_config'] is Map
        ? org!['project_management_config']['task_approval']
        : null;

    _rrSteps = rr is Map ? (rr['steps'] as num?)?.toInt() ?? 0 : 0;
    _rrStep1 = rr is Map ? _roleId(rr['approvers'] is Map ? rr['approvers']['step1'] : null) : '';
    _rrStep2 = rr is Map ? _roleId(rr['approvers'] is Map ? rr['approvers']['step2'] : null) : '';

    _rateSteps = rate is Map ? (rate['steps'] as num?)?.toInt() ?? 0 : 0;
    _rateStep1 =
        rate is Map ? _roleId(rate['approvers'] is Map ? rate['approvers']['step1'] : null) : '';
    _rateStep2 =
        rate is Map ? _roleId(rate['approvers'] is Map ? rate['approvers']['step2'] : null) : '';

    _taskSteps = task is Map ? (task['steps'] as num?)?.toInt() ?? 0 : 0;
    _taskStep1 =
        task is Map ? _roleId(task['approvers'] is Map ? task['approvers']['step1'] : null) : '';
    _taskStep2 =
        task is Map ? _roleId(task['approvers'] is Map ? task['approvers']['step2'] : null) : '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_perms.can(_permission, 'read') &&
        !_perms.can(_permission, 'update') &&
        !_perms.isSuperAdmin) {
      setState(() {
        _loading = false;
        _error = 'You do not have permission to view this.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apis = context.read<SettingsApis>();
      final org = await apis.getOrganization();
      List<Map<String, dynamic>> roles = [];
      try {
        final rolePage = await apis.roles.list({'limit': 200, 'isActive': true});
        roles = rolePage.items;
      } catch (_) {
        // Roles are optional for viewing; needed for approval dropdowns.
      }
      if (!mounted) return;
      _org = org;
      _nameCtrl.text = org?['name']?.toString() ?? '';
      _emailCtrl.text = org?['contactEmail']?.toString() ?? '';
      _phoneCtrl.text = org?['contactPhone']?.toString() ?? '';
      final address = org?['address'];
      if (address is Map) {
        _addressCtrl.text = [
          address['street_address'],
          address['city'],
          address['state'],
          address['zip_code'],
          address['country'],
        ].where((e) => e != null && e.toString().trim().isNotEmpty).join(', ');
      } else {
        _addressCtrl.text = address?.toString() ?? '';
      }
      _loadApprovalsFromOrg(org);
      setState(() {
        _modules = normalizeOrgModules(org?['modules']);
        _savedModules = normalizeOrgModules(org?['modules']);
        _roles = roles;
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

  String? _validateApproval(String label, int steps, String step1, String step2) {
    if (steps == 1 && step1.trim().isEmpty) {
      return '$label approver role is required';
    }
    if (steps == 2) {
      if (step1.trim().isEmpty) return '$label step 1 role is required';
      if (step2.trim().isEmpty) return '$label step 2 role is required';
      if (step1.trim() == step2.trim()) {
        return '$label step 2 role must be different from step 1';
      }
    }
    return null;
  }

  bool get _canEditModules => _perms.isSuperAdmin;

  bool get _modulesDirty =>
      _canEditModules &&
      normalizeOrgModules(_modules).toString() != normalizeOrgModules(_savedModules).toString();

  Future<void> _save({bool modulesOnly = false}) async {
    if (!_perms.can(_permission, 'update') && !_perms.isSuperAdmin) {
      showPmsSnack(context, 'No update permission', error: true);
      return;
    }
    if (!modulesOnly) {
      if (_nameCtrl.text.trim().isEmpty) {
        showPmsSnack(context, 'Name is required', error: true);
        return;
      }
    }
    if (_canEditModules && !anyModuleEnabled(_modules)) {
      showPmsSnack(context, 'Select at least one product module', error: true);
      return;
    }

    final modules = _canEditModules
        ? normalizeOrgModules(_modules)
        : normalizeOrgModules(_org?['modules']);
    final procurementOn = modules['procurement'] is Map &&
        (modules['procurement'] as Map)['enabled'] == true;
    final pmOn = modules['project_management'] is Map &&
        (modules['project_management'] as Map)['enabled'] == true;

    if (procurementOn) {
      final rr = _validateApproval('RR approval', _rrSteps, _rrStep1, _rrStep2);
      if (rr != null) {
        showPmsSnack(context, rr, error: true);
        return;
      }
      final rate = _validateApproval('Rate approval', _rateSteps, _rateStep1, _rateStep2);
      if (rate != null) {
        showPmsSnack(context, rate, error: true);
        return;
      }
    }
    if (pmOn) {
      final task = _validateApproval('Task progress approval', _taskSteps, _taskStep1, _taskStep2);
      if (task != null) {
        showPmsSnack(context, task, error: true);
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        if (!modulesOnly) ...{
          'name': _nameCtrl.text.trim(),
          'contactEmail': _emailCtrl.text.trim(),
          'contactPhone': _phoneCtrl.text.trim(),
          'address': _addressCtrl.text.trim(),
        },
        if (_canEditModules) ...{
          'modules': modules,
          'procurement_config': procurementOn
              ? {
                  'rr_approval': buildApprovalPayload(_rrSteps, _rrStep1, _rrStep2),
                  'rate_approval': buildApprovalPayload(_rateSteps, _rateStep1, _rateStep2),
                }
              : {
                  'rr_approval': emptyApprovalPayload(),
                  'rate_approval': emptyApprovalPayload(),
                },
          'project_management_config': pmOn
              ? {
                  'task_approval': buildApprovalPayload(_taskSteps, _taskStep1, _taskStep2),
                  'dpr_approval': emptyApprovalPayload(),
                }
              : {
                  'task_approval': emptyApprovalPayload(),
                  'dpr_approval': emptyApprovalPayload(),
                },
        },
      };

      await context.read<SettingsApis>().updateOrganization(payload);
      if (!mounted) return;

      // Refresh workspace entitlements + Super Admin permission sync.
      final orgSession = context.read<OrgSession>();
      final auth = context.read<AuthProvider>();
      await orgSession.refresh();
      if (!mounted) return;
      await auth.refreshMe();
      if (!mounted) return;

      showPmsSnack(
        context,
        modulesOnly ? 'Module access updated' : 'Organization updated',
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUpdate = _perms.can(_permission, 'update') || _perms.isSuperAdmin;
    final canEditModules = _canEditModules;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Organization'),
        actions: [
          if (canUpdate && !_modulesDirty)
            TextButton(
              onPressed: _saving ? null : () => _save(),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    ErrorBanner(message: _error!, onRetry: _load),
                    const SizedBox(height: 12),
                  ],
                  if (_org == null && _error == null)
                    const EmptyState(message: 'No organization found')
                  else ...[
                    TextFormField(
                      controller: _nameCtrl,
                      enabled: canUpdate,
                      decoration: const InputDecoration(labelText: 'Name *'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _emailCtrl,
                      enabled: canUpdate,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Contact email'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _phoneCtrl,
                      enabled: canUpdate,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Contact phone'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _addressCtrl,
                      enabled: canUpdate,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Address'),
                    ),
                    const SizedBox(height: 20),
                    if (!canEditModules)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.brandLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.brand.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_outline, color: AppTheme.brand, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Product module access is read-only. Only Super Admin can enable or disable modules for this organization.',
                                style: AppTheme.bodySmall.copyWith(color: AppTheme.primary),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_modulesDirty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: AppTheme.warning, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'You have unsaved module changes. Tap "Save module access" below to apply.',
                                style: AppTheme.bodySmall.copyWith(color: AppTheme.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ModuleEntitlementsEditor(
                      modules: _modules,
                      enabled: canEditModules && !_saving,
                      editableModuleKeys: canEditModules ? null : const {},
                      approverMode: ModuleApproverMode.roleIds,
                      roles: _roles,
                      rrSteps: _rrSteps,
                      rrStep1: _rrStep1,
                      rrStep2: _rrStep2,
                      rateSteps: _rateSteps,
                      rateStep1: _rateStep1,
                      rateStep2: _rateStep2,
                      taskSteps: _taskSteps,
                      taskStep1: _taskStep1,
                      taskStep2: _taskStep2,
                      onModulesChanged: (next) => setState(() => _modules = next),
                      onApprovalChanged: ({
                        int? rrSteps,
                        String? rrStep1,
                        String? rrStep2,
                        int? rateSteps,
                        String? rateStep1,
                        String? rateStep2,
                        int? taskSteps,
                        String? taskStep1,
                        String? taskStep2,
                      }) {
                        setState(() {
                          if (rrSteps != null) _rrSteps = rrSteps;
                          if (rrStep1 != null) _rrStep1 = rrStep1;
                          if (rrStep2 != null) _rrStep2 = rrStep2;
                          if (rateSteps != null) _rateSteps = rateSteps;
                          if (rateStep1 != null) _rateStep1 = rateStep1;
                          if (rateStep2 != null) _rateStep2 = rateStep2;
                          if (taskSteps != null) _taskSteps = taskSteps;
                          if (taskStep1 != null) _taskStep1 = taskStep1;
                          if (taskStep2 != null) _taskStep2 = taskStep2;
                        });
                      },
                    ),
                    if (canEditModules) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _saving || !_modulesDirty ? null : () => _save(modulesOnly: true),
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save module access'),
                      ),
                    ],
                    if (canUpdate) ...[
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _save(),
                        icon: const Icon(Icons.business_rounded),
                        label: const Text('Save organization details'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}
