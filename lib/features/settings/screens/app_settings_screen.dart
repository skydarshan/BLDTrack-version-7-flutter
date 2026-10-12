import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/form_validation_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../pms/widgets/pickers.dart';
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
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _statusMessage;
  final _fieldErrors = FieldErrors();

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
    _hostCtrl.dispose();
    _portCtrl.dispose();
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
      _hostCtrl.text = cfg?['smtpHost']?.toString() ?? '';
      _portCtrl.text = cfg?['smtpPort']?.toString() ?? '';
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

  Map<String, dynamic>? _smtpPayload() {
    final provider = _providerCtrl.text.trim();
    final user = _userCtrl.text.trim();
    _fieldErrors.clear();
    _fieldErrors.set('provider', requiredText(provider, 'SMTP provider'));
    _fieldErrors.set('user', requiredText(user, 'SMTP user'));
    if (provider == 'custom') {
      if (_hostCtrl.text.trim().length < 3) {
        _fieldErrors.set('host', 'SMTP host is required for custom provider');
      }
      final port = int.tryParse(_portCtrl.text.trim());
      if (port == null || port < 1 || port > 65535) {
        _fieldErrors.set('port', 'SMTP port must be between 1 and 65535');
      }
    }
    if (_fieldErrors.hasErrors) {
      setState(() {});
      showPmsSnack(context, _fieldErrors.messages.first, error: true);
      return null;
    }
    final payload = <String, dynamic>{
      'smtpProvider': provider,
      'smtpUser': user,
      'senderEmail': user,
      'recipientEmail': user,
    };
    if (provider == 'custom') {
      payload['smtpHost'] = _hostCtrl.text.trim();
      payload['smtpPort'] = int.parse(_portCtrl.text.trim());
    }
    final pwd = _passwordCtrl.text;
    if (pwd.trim().isNotEmpty) payload['smtpPassword'] = pwd;
    return payload;
  }

  Future<void> _save() async {
    final payload = _smtpPayload();
    if (payload == null) return;
    setState(() => _busy = true);
    try {
      await context.read<SettingsApis>().updateNotificationEmail(payload);
      if (!mounted) return;
      await showSavedConfirmation(context, 'Notification email saved');
      if (!mounted) return;
      setState(() => _statusMessage = 'Notification email saved');
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      _fieldErrors.merge(apiFieldErrors(e));
      setState(() {});
      showPmsSnack(context, formatApiErrorSummary(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                      if (_fieldErrors.hasErrors)
                        ValidationSummaryBanner(messages: _fieldErrors.messages),
                      AppDropdownFormField<String>(
                        initialValue: ['gmail', 'outlook', 'custom']
                                .contains(_providerCtrl.text)
                            ? _providerCtrl.text
                            : 'gmail',
                        decoration: InputDecoration(
                          labelText: 'SMTP provider *',
                          errorText: _fieldErrors['provider'],
                        ),
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
                      if (_providerCtrl.text.trim() == 'custom') ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _hostCtrl,
                          enabled: !_busy,
                          decoration: InputDecoration(
                            labelText: 'SMTP host *',
                            errorText: _fieldErrors['host'],
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _portCtrl,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'SMTP port *',
                            errorText: _fieldErrors['port'],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _userCtrl,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'SMTP user *',
                          errorText: _fieldErrors['user'],
                        ),
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
                            : () {
                                final payload = _smtpPayload();
                                if (payload == null) return;
                                _run(
                                  () => context
                                      .read<SettingsApis>()
                                      .verifyNotificationEmail(payload),
                                  'Verification started',
                                );
                              },
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
