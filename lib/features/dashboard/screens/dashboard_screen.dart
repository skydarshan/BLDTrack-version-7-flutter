import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: auth.isBusy
                ? null
                : () async {
                    await auth.logout();
                    if (context.mounted) context.go('/login');
                  },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Welcome${user?.name.isNotEmpty == true ? ', ${user!.name}' : ''}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Flutter Phase 1 is connected to the same Avidus backend. '
            'Procurement modules will be added after you verify auth.',
            style: TextStyle(color: AppTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Signed-in profile',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 14),
                  _InfoRow(label: 'Name', value: user?.name ?? '—'),
                  _InfoRow(label: 'Email', value: user?.email ?? '—'),
                  _InfoRow(label: 'Role', value: user?.displayRole ?? '—'),
                  _InfoRow(
                    label: 'Organisation',
                    value: user?.organisation?.toString() ?? '—',
                  ),
                  _InfoRow(
                    label: 'Sites',
                    value: '${user?.sites.length ?? 0}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'API connection',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    ApiConfig.apiV1Base,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Override with:\nflutter run --dart-define=API_BASE_URL=https://your-api-host',
                    style: TextStyle(fontSize: 13, color: AppTheme.muted, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Next steps (after your check)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  SizedBox(height: 10),
                  Text('• Requisition Requests'),
                  Text('• Rate Comparatives & Approvals'),
                  Text('• Purchase Orders'),
                  Text('• Settings / Notification Email'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
