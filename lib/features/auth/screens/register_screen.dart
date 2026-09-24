import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/org/org_modules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/form_validators.dart';
import '../../org/org_session.dart';
import '../../org/widgets/module_entitlements_editor.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../models/auth_models.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _orgNameController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _adminPhoneController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _addressController = TextEditingController();

  int _step = 1;
  bool _obscurePassword = true;
  Map<String, dynamic> _modules = buildDefaultModules();

  int _rrSteps = 0;
  String _rrStep1 = '';
  String _rrStep2 = '';
  int _rateSteps = 0;
  String _rateStep1 = '';
  String _rateStep2 = '';
  int _taskSteps = 0;
  String _taskStep1 = '';
  String _taskStep2 = '';
  String? _stepError;

  @override
  void dispose() {
    _orgNameController.dispose();
    _adminNameController.dispose();
    _adminPhoneController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    _contactEmailController.dispose();
    _contactPhoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  bool get _procurementOn {
    final m = _modules['procurement'];
    return m is Map && m['enabled'] == true;
  }

  bool get _pmOn {
    final m = _modules['project_management'];
    return m is Map && m['enabled'] == true;
  }

  void _showError(String message) {
    setState(() => _stepError = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
    );
  }

  String? _validateApproval(String label, int steps, String step1, String step2) {
    if (steps == 1 && step1.trim().isEmpty) {
      return '$label approver role name is required';
    }
    if (steps == 2) {
      if (step1.trim().isEmpty) return '$label step 1 role name is required';
      if (step2.trim().isEmpty) return '$label step 2 role name is required';
      if (step1.trim() == step2.trim()) {
        return '$label step 2 role must be different from step 1';
      }
    }
    return null;
  }

  bool _validateCurrentStep() {
    setState(() => _stepError = null);
    if (_step == 1) {
      final err = FormValidators.minLength(_orgNameController.text, 2, 'Organization name');
      if (err != null) {
        _showError(err);
        return false;
      }
      final max = FormValidators.maxLength(_orgNameController.text, 200, 'Organization name');
      if (max != null) {
        _showError(max);
        return false;
      }
      return true;
    }

    if (_step == 2) {
      final nameErr = FormValidators.minLength(_adminNameController.text, 2, 'Admin name');
      if (nameErr != null) {
        _showError(nameErr);
        return false;
      }
      final phoneErr = FormValidators.requiredField(_adminPhoneController.text, 'Phone number');
      if (phoneErr != null) {
        _showError(phoneErr);
        return false;
      }
      final emailErr = FormValidators.email(_adminEmailController.text);
      if (emailErr != null) {
        _showError(emailErr);
        return false;
      }
      final passErr = FormValidators.strongPassword(_adminPasswordController.text);
      if (passErr != null) {
        _showError(passErr);
        return false;
      }
      return true;
    }

    if (_step == 3) {
      if (_contactEmailController.text.trim().isNotEmpty) {
        final emailErr = FormValidators.email(_contactEmailController.text);
        if (emailErr != null) {
          _showError(emailErr);
          return false;
        }
      }
      return true;
    }

    // Step 4 — modules
    if (!anyModuleEnabled(_modules)) {
      _showError('Select at least one product module');
      return false;
    }
    if (_procurementOn) {
      final rr = _validateApproval('RR approval', _rrSteps, _rrStep1, _rrStep2);
      if (rr != null) {
        _showError(rr);
        return false;
      }
      final rate = _validateApproval('Rate approval', _rateSteps, _rateStep1, _rateStep2);
      if (rate != null) {
        _showError(rate);
        return false;
      }
    }
    if (_pmOn) {
      final task = _validateApproval('Task progress approval', _taskSteps, _taskStep1, _taskStep2);
      if (task != null) {
        _showError(task);
        return false;
      }
    }
    return true;
  }

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    if (_step <= 3 && !(_formKey.currentState?.validate() ?? false)) return;
    if (!_validateCurrentStep()) return;
    if (_step < 4) {
      setState(() => _step += 1);
      return;
    }
    await _submit();
  }

  void _back() {
    if (_step <= 1) return;
    setState(() => _step -= 1);
  }

  Future<void> _submit() async {
    if (!_validateCurrentStep()) return;

    final auth = context.read<AuthProvider>();
    final request = RegisterOrganizationRequest(
      organizationName: _orgNameController.text.trim(),
      subdomain: buildSubdomain(_orgNameController.text),
      adminName: _adminNameController.text.trim(),
      adminEmail: _adminEmailController.text.trim().toLowerCase(),
      adminPassword: _adminPasswordController.text,
      adminPhone: _adminPhoneController.text.trim(),
      contactEmail: _contactEmailController.text.trim().isEmpty
          ? _adminEmailController.text.trim().toLowerCase()
          : _contactEmailController.text.trim().toLowerCase(),
      contactPhone: _contactPhoneController.text.trim().isEmpty
          ? null
          : _contactPhoneController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      modules: normalizeOrgModules(_modules),
      procurementConfig: _procurementOn
          ? {
              'rr_approval': buildApprovalPayload(_rrSteps, _rrStep1, _rrStep2),
              'rate_approval': buildApprovalPayload(_rateSteps, _rateStep1, _rateStep2),
            }
          : null,
      projectManagementConfig: _pmOn
          ? {
              'task_approval': buildApprovalPayload(_taskSteps, _taskStep1, _taskStep2),
              'dpr_approval': buildApprovalPayload(0, '', ''),
            }
          : null,
    );

    final ok = await auth.register(request);
    if (!mounted) return;

    if (ok) {
      try {
        await context.read<OrgSession>().refresh();
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Organization registered successfully')),
      );
      final org = context.read<OrgSession>();
      context.go(workspaceHomePath(org.workspace));
    } else {
      _showError(auth.error ?? 'Registration failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return AuthScaffold(
      title: 'Create organization',
      subtitle: 'Step $_step of 4 — same flow as the web app.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StepIndicator(step: _step),
            const SizedBox(height: 12),
            if (_stepError != null) ...[
              ValidationSummaryBanner(messages: [_stepError!]),
            ],
            if (_step == 1) ...[
              TextFormField(
                controller: _orgNameController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Organization name',
                  hintText: 'Acme Corp',
                ),
                validator: (v) => FormValidators.minLength(v, 2, 'Organization name'),
              ),
            ] else if (_step == 2) ...[
              TextFormField(
                controller: _adminNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Admin name'),
                validator: (v) => FormValidators.minLength(v, 2, 'Admin name'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _adminPhoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Phone number'),
                validator: (v) => FormValidators.requiredField(v, 'Phone number'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _adminEmailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Admin email'),
                validator: FormValidators.email,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _adminPasswordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Admin password',
                  helperText: 'Min 8 chars, upper, lower, and a number',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
                validator: FormValidators.strongPassword,
              ),
            ] else if (_step == 3) ...[
              TextFormField(
                controller: _contactEmailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Contact email (optional)',
                  hintText: 'Defaults to admin email',
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _contactPhoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Contact phone (optional)'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Address (optional)'),
              ),
            ] else ...[
              ModuleEntitlementsEditor(
                modules: _modules,
                enabled: !auth.isBusy,
                approverMode: ModuleApproverMode.names,
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
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (_step > 1)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: auth.isBusy ? null : _back,
                      child: const Text('Back'),
                    ),
                  ),
                if (_step > 1) const SizedBox(width: 12),
                Expanded(
                  child: LoadingButton(
                    label: _step == 4 ? 'Create account' : 'Next',
                    loading: auth.isBusy,
                    onPressed: _next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: auth.isBusy ? null : () => context.go('/login'),
              child: const Text('Already have an account? Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final n = index + 1;
        final active = n <= step;
        final color = AppTheme.colorAt(index);
        return Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? color : AppTheme.softBg(color),
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? color : color.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            '$n',
            style: TextStyle(
              color: active ? Colors.white : color,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }),
    );
  }
}
