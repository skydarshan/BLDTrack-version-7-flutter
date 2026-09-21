import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/api_config.dart';
import '../../../core/org/org_modules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/form_validators.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../../org/org_session.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _apiError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _apiError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    final ok = await auth.login(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (ok) {
      try {
        await context.read<OrgSession>().refresh();
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome back')),
      );
      final org = context.read<OrgSession>();
      context.go(workspaceHomePath(org.workspace));
    } else {
      final msg = auth.error ?? 'Login failed. Check your email and password.';
      setState(() => _apiError = msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return AuthScaffold(
      title: 'Sign in',
      subtitle: 'Use your organization admin or user account.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_apiError != null) ...[
              ValidationSummaryBanner(messages: [_apiError!]),
            ],
            if (ApiConfig.debugLabel.isNotEmpty) ...[
              Text(
                ApiConfig.debugLabel,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
            ],
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'you@company.com',
              ),
              validator: FormValidators.email,
              onChanged: (_) {
                if (_apiError != null) setState(() => _apiError = null);
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
              validator: FormValidators.password,
              onChanged: (_) {
                if (_apiError != null) setState(() => _apiError = null);
              },
            ),
            const SizedBox(height: 20),
            LoadingButton(
              label: 'Sign in',
              loading: auth.isBusy,
              onPressed: _submit,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: auth.isBusy ? null : () => context.go('/register'),
              child: const Text('Create an organization'),
            ),
          ],
        ),
      ),
    );
  }
}
