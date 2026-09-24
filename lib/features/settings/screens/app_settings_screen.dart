import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../pms/widgets/pms_widgets.dart';
import '../services/settings_apis.dart';
import '../utils/permissions.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  final _providerCtrl = TextEditingController(text: 'gmail');
  final _userCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _statusMessage;

  Permissions get _perms => Permissions(context.read<AuthProvider>().user);

  bool get _canUpdate =>
      _perms.can('organization', 'update') || _perms.isSuperAdmin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _providerCtrl.dispose();
    _userCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_canUpdate) {
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cfg = await context.read<SettingsApis>().getNotificationEmail();
      if (!mounted) return;
      _providerCtrl.text = cfg?['smtpProvider']?.toString() ?? 'gmail';
      _userCtrl.text = cfg?['smtpUser']?.toString() ??
          cfg?['senderEmail']?.toString() ??
          '';
      _passwordCtrl.clear();
      setState(() {
        _loading = false;
        _statusMessage = cfg == null
            ? 'No notification email configured yet.'
            : (cfg['isVerified'] == true
                ? 'SMTP verified'
                : 'SMTP not verified');
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

  Future<void> _run(Future<void> Function() action, String success) async {
    if (!_canUpdate) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showPmsSnack(context, success);
      setState(() => _statusMessage = success);
      if (success.toLowerCase().contains('saved')) {
        await _load();
      }
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showPmsSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final provider = _providerCtrl.text.trim();
    final user = _userCtrl.text.trim();
    if (provider.isEmpty) {
      showPmsSnack(context, 'SMTP provider is required', error: true);
      return;
    }
    if (user.isEmpty) {
      showPmsSnack(context, 'SMTP user is required', error: true);
      return;
    }
    final payload = <String, dynamic>{
      'smtpProvider': provider,
      'smtpUser': user,
      'senderEmail': user,
      'recipientEmail': user,
    };
    final pwd = _passwordCtrl.text;
    if (pwd.trim().isNotEmpty) payload['smtpPassword'] = pwd;
    await _run(
      () async {
        await context.read<SettingsApis>().updateNotificationEmail(payload);
      },
      'Notification email saved',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Settings')),
      body: !_canUpdate
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'You do not have permission to manage notification email settings.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: AppTheme.formPadding,
                    children: [
                      if (_error != null) ...[
                        ErrorBanner(message: _error!, onRetry: _load),
                        const SizedBox(height: 12),
                      ],
                      if (_statusMessage != null) ...[
                        Text(
                          _statusMessage!,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Text(
                        'Notification email (SMTP)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: ['gmail', 'outlook', 'custom']
                                .contains(_providerCtrl.text)
                            ? _providerCtrl.text
                            : 'gmail',
                        decoration:
                            const InputDecoration(labelText: 'SMTP provider'),
                        items: const [
                          DropdownMenuItem(
                            value: 'gmail',
                            child: Text('Gmail'),
                          ),
                          DropdownMenuItem(
                            value: 'outlook',
                            child: Text('Outlook'),
                          ),
                          DropdownMenuItem(
                            value: 'custom',
                            child: Text('Custom'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) {
                                setState(() {
                                  _providerCtrl.text = v ?? 'gmail';
                                });
                              },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _userCtrl,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        decoration:
                            const InputDecoration(labelText: 'SMTP user'),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _passwordCtrl,
                        enabled: !_busy,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'SMTP password',
                          hintText: 'Leave blank to keep existing',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : _save,
                        child: const Text('Save'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => context
                                      .read<SettingsApis>()
                                      .verifyNotificationEmail(),
                                  'Verification started',
                                ),
                        child: const Text('Verify'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => context
                                      .read<SettingsApis>()
                                      .testNotificationEmail(),
                                  'Test email sent',
                                ),
                        child: const Text('Test'),
                      ),
                      if (_busy) ...[
                        const SizedBox(height: 16),
                        const Center(child: CircularProgressIndicator()),
                      ],
                    ],
                  ),
                ),
    );
  }
}
