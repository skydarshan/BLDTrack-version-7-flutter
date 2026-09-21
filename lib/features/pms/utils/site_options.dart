import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_helpers.dart';
import '../../auth/providers/auth_provider.dart';
import '../../settings/utils/permissions.dart';
import '../services/pms_services.dart';
import '../widgets/pickers.dart';

/// Assigned sites from auth profile (GET /auth/me `user.sites`).
List<Map<String, dynamic>> sitesFromAuthProfile(List<dynamic> raw) {
  final docs = <Map<String, dynamic>>[];
  for (final entry in raw) {
    if (entry == null) continue;
    if (entry is String && entry.trim().isNotEmpty) {
      docs.add({'_id': entry.trim(), 'site_name': entry.trim()});
      continue;
    }
    if (entry is Map) {
      final m = Map<String, dynamic>.from(entry);
      final id = idOf(m);
      if (id == null || id.isEmpty) continue;
      docs.add({...m, '_id': id});
    }
  }
  docs.sort((a, b) {
    final la = (a['site_name'] ?? a['name'] ?? '').toString();
    final lb = (b['site_name'] ?? b['name'] ?? '').toString();
    return la.toLowerCase().compareTo(lb.toLowerCase());
  });
  return docs;
}

List<OptionItem> mapSiteRowsToOptions(List<Map<String, dynamic>> rows) {
  return mapToOptions(
    rows,
    labelOfRow: (r) => r['site_name']?.toString() ?? labelOf(r),
  );
}

List<Map<String, dynamic>> filterSitesByKeyword(
  List<Map<String, dynamic>> sites,
  String keyword,
) {
  final q = keyword.trim().toLowerCase();
  if (q.isEmpty) return sites;
  return sites.where((site) {
    final haystack = [
      site['site_name'],
      site['name'],
      site['code'],
      site['location'],
    ]
        .whereType<String>()
        .where((v) => v.trim().isNotEmpty)
        .join(' ')
        .toLowerCase();
    return haystack.contains(q);
  }).toList();
}

/// Site dropdown options — mirrors React `loadSiteOptions`.
/// Non–Super Admin → assigned sites from auth profile only.
/// Super Admin → GET `/sites`.
Future<List<OptionItem>> loadSiteOptions(
  BuildContext context, {
  String? search,
  int limit = 100,
}) async {
  final auth = context.read<AuthProvider>();
  final user = auth.user;
  final perms = Permissions(user);

  if (!perms.isSuperAdmin) {
    final rows = filterSitesByKeyword(
      sitesFromAuthProfile(user?.sites ?? const []),
      search ?? '',
    );
    return mapSiteRowsToOptions(rows);
  }

  try {
    final rows = await context.read<PmsServices>().masters.listSites(
          search: search,
          limit: limit,
        );
    return mapSiteRowsToOptions(rows);
  } catch (_) {
    return mapSiteRowsToOptions(
      sitesFromAuthProfile(user?.sites ?? const []),
    );
  }
}
