import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/form_validation_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../app/app_services.dart';
import '../../auth/providers/auth_provider.dart';
import '../../org/org_session.dart';
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
  String? _prefError;
  String _savingType = '';
  List<Map<String, dynamic>> _prefTypes = const [];
  final _fieldErrors = FieldErrors();

  Permissions get _perms => Permissions(context.read<AuthProvider>().user);

  bool get _canUpdate =>
      _perms.can('organization', 'update') || _perms.isSuperAdmin;

  bool _preferencesActive(OrgSession org) =>
      org.hasModule('project_management') && org.workspace == 'project_management';

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
    final org = context.read<OrgSession>();
    final loadPrefs = _preferencesActive(org) && _perms.isSuperAdmin;
    setState(() {
      _loading = true;
      _error = null;
      _prefError = null;
    });
    final jobs = <Future<void>>[
      if (_canUpdate) _loadEmail(),
      if (loadPrefs) _loadPreferences(),
    ];
    if (jobs.isNotEmpty) await Future.wait(jobs);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadEmail() async {
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
        _error = null;
        _statusMessage = cfg == null
            ? 'No notification email configured yet.'
            : (cfg['isVerified'] == true
                ? 'SMTP verified'
                : 'SMTP not verified');
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final types =
          await context.read<AppServices>().notifications.getPreferences();
      if (!mounted) return;
      setState(() {
        _prefTypes = types;
        _prefError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _prefError = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _prefError = e.toString());
    }
  }

  Map<String, dynamic> _withChannel(
    Map<String, dynamic> row,
    String channel,
    bool value,
  ) {
    final next = Map<String, dynamic>.from(row);
    next[channel] = value;
    return next;
  }

  Future<void> _updateChannel(String type, String channel, bool value) async {
    if (!_perms.isSuperAdmin || type.isEmpty || _savingType.isNotEmpty) return;
    final previous = _prefTypes
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    setState(() {
      _savingType = type;
      _prefTypes = [
        for (final row in _prefTypes)
          if (row['type']?.toString() == type)
            _withChannel(row, channel, value)
          else
            row,
      ];
    });
    try {
      final channelUpdate = <String, dynamic>{channel: value};
      final next = await context.read<AppServices>().notifications.updatePreferences(
        <String, dynamic>{type: channelUpdate},
      );
      if (!mounted) return;
      setState(() {
        if (next.isNotEmpty) _prefTypes = next;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _prefTypes = previous);
      showPmsSnack(context, e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _prefTypes = previous);
      showPmsSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _savingType = '');
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
    final org = context.watch<OrgSession>();
    return Scaffold(
      appBar: AppBar(title: const Text('App Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: AppTheme.formPadding,
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_canUpdate) ..._emailFields(),
                  if (!_canUpdate)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'You do not have permission to manage notification email settings.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  _preferencesBody(org),
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
    );
  }

  List<Widget> _emailFields() {
    return [
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
        'Notification email',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'SMTP is the shared sender. Email templates are the procurement and inventory copy.',
        style: TextStyle(color: AppTheme.muted),
      ),
      const SizedBox(height: 12),
      Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(Icons.mark_email_read_outlined, color: AppTheme.brand),
          title: Text('Email templates'),
          subtitle: Text('Edit procurement and inventory emails'),
          trailing: Icon(Icons.chevron_right),
          onTap: () => context.push('/pms/settings/email-templates'),
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'SMTP',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 12),
      if (_fieldErrors.hasErrors)
        ValidationSummaryBanner(messages: _fieldErrors.messages),
      AppDropdownFormField<String>(
        initialValue: ['gmail', 'outlook', 'custom'].contains(_providerCtrl.text)
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
                  () => context.read<SettingsApis>().verifyNotificationEmail(payload),
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
                  () => context.read<SettingsApis>().testNotificationEmail(),
                  'Test email sent',
                ),
        child: const Text('Test'),
      ),
    ];
  }

  Widget _preferencesBody(OrgSession org) {
    final active = _preferencesActive(org);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Notification preferences',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (!active)
          Text(
            org.hasModule('project_management')
                ? 'Project Management notification preferences are shown when that module is active.'
                : 'Notification preferences are available when Project Management is enabled for your organisation.',
            style: const TextStyle(color: AppTheme.muted, height: 1.4),
          )
        else if (!_perms.isSuperAdmin)
          const Text(
            'Organization notification rules are managed exclusively by Super Admin.',
            style: TextStyle(color: AppTheme.muted, height: 1.4),
          )
        else ...[
          const Text(
            'Organization-wide notification events. Turning a type off disables it for the whole organisation. Email still needs SMTP configured above.',
            style: TextStyle(color: AppTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (_prefError != null) ...[
            ErrorBanner(message: _prefError!, onRetry: _load),
            const SizedBox(height: 12),
          ],
          if (_prefTypes.isEmpty && _prefError == null)
            const Text(
              'No notification types available.',
              style: TextStyle(color: AppTheme.muted),
            )
          else
            for (final item in _prefTypes) _preferenceRow(item),
        ],
      ],
    );
  }

  Widget _preferenceRow(Map<String, dynamic> item) {
    final type = item['type']?.toString() ?? '';
    final busy = _savingType == type;
    final label = item['label']?.toString().trim();
    final description = item['description']?.toString().trim() ?? '';
    return Opacity(
      opacity: busy ? 0.72 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              (label == null || label.isEmpty) ? type : label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: AppTheme.muted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
            Row(
              children: [
                _channelSwitch(
                  label: 'Notifications',
                  value: item['inApp'] == true,
                  enabled: !busy && type.isNotEmpty,
                  onChanged: (value) => _updateChannel(type, 'inApp', value),
                ),
                _channelSwitch(
                  label: 'Email',
                  value: item['email'] == true,
                  enabled: !busy && type.isNotEmpty,
                  onChanged: (value) => _updateChannel(type, 'email', value),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelSwitch({
    required String label,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.muted,
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
