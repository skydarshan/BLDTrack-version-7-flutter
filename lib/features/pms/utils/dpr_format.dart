import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_helpers.dart';
import '../../../core/org/org_modules.dart';
import '../../auth/providers/auth_provider.dart';
import '../../org/org_session.dart';
import '../../settings/utils/permissions.dart';

bool canDpr(BuildContext context, String action) {
  return Permissions(context.read<AuthProvider>().user).can('dpr', action);
}

bool isDprEditable(String? status) =>
    status == 'draft' || status == 'revision_requested';

String apiDay(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

DateTime? parseApiDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

String formatCalendarDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

bool dprHasNextPage(Map<String, dynamic>? pagination, int page) {
  if (pagination == null) return false;
  final flag = pagination['hasNextPage'];
  if (flag is bool) return flag;
  final totalPages = pagination['totalPages'];
  return totalPages is num && page < totalPages.toInt();
}

String formatDprDate(dynamic value) {
  final parsed = parseApiDate(value)?.toUtc();
  if (parsed == null) return '—';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
}

String formatDprDateTime(dynamic value) {
  final parsed = parseApiDate(value);
  if (parsed == null) return '—';
  return DateFormat('d MMM yyyy, h:mm a').format(parsed.toLocal());
}

String dprStatusLabel(String? status) {
  switch (status) {
    case 'draft':
      return 'Draft';
    case 'pending':
      return 'Awaiting approval';
    case 'approved':
      return 'Approved';
    case 'revision_requested':
      return 'Sent back';
    case 'not_started':
      return 'Not started';
    default:
      if (status == null || status.trim().isEmpty) return '—';
      return status.replaceAll('_', ' ');
  }
}

String personName(dynamic value) {
  if (value is Map) {
    for (final key in ['name', 'email']) {
      final text = value[key]?.toString().trim() ?? '';
      if (text.isNotEmpty && !looksLikeObjectId(text)) return text;
    }
  }
  final labeled = labelOf(value, fallback: '');
  return labeled.isEmpty ? '—' : labeled;
}

String dprSiteLabel(dynamic value) {
  if (value is Map) {
    final name = value['site_name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
  }
  return labelOf(value);
}

const dprWeatherLabels = {
  'clear': 'Clear',
  'cloudy': 'Cloudy',
  'rain': 'Rain',
  'heavy_rain': 'Heavy rain',
  'storm': 'Storm',
  'fog': 'Fog',
  'extreme_heat': 'Extreme heat',
  'other': 'Other',
};

const dprSeverityLabels = {
  'near_miss': 'Near miss',
  'minor': 'Minor',
  'major': 'Major',
  'critical': 'Critical',
};

String? approvalStepLabel(Map<String, dynamic>? report) {
  if (report == null || report['status']?.toString() != 'pending') return null;
  final approval = report['approval'];
  if (approval is! Map) return null;
  final level = (approval['current_level'] as num?)?.toInt() ?? 0;
  final steps = (approval['required_steps'] as num?)?.toInt() ??
      (approval['steps'] as num?)?.toInt() ??
      0;
  if (steps <= 0) return null;
  return 'Step ${level + 1} of $steps';
}

const dprActivityLabels = {
  'dpr_created': 'Report created',
  'dpr_submitted': 'Submitted for approval',
  'dpr_submitted_auto_approved': 'Submitted and approved',
  'dpr_step_approved': 'Approved (pending next step)',
  'dpr_approved': 'Approved',
  'dpr_revision_requested': 'Sent back for revision',
  'dpr_updated': 'Report updated',
  'dpr_work_summary_prefilled': 'Work summary filled from tasks',
  'dpr_media_removed': 'Media removed',
};

String dprActivityLabel(String? action) {
  if (action == null || action.isEmpty) return 'Update';
  return dprActivityLabels[action] ?? action.replaceAll('_', ' ');
}

String _roleIdOf(dynamic raw) {
  if (raw is Map) return (raw['_id'] ?? raw['id'] ?? '').toString();
  return raw?.toString() ?? '';
}

/// Matches the website: Super Admin, or a user whose role is Step 1 / Step 2.
bool canAccessDprApprovals(BuildContext context) {
  if (!canDpr(context, 'approve')) return false;
  final user = context.read<AuthProvider>().user;
  if (user == null) return false;
  if (Permissions(user).isSuperAdmin) return true;
  final org = context.read<OrgSession>().organization;
  final pm = org?['project_management_config'];
  final cfg = pm is Map ? pm['dpr_approval'] : null;
  if (cfg is! Map) return false;
  final steps = (cfg['steps'] as num?)?.toInt() ?? 0;
  if (cfg['enabled'] != true || steps <= 0) return false;
  final roleId = _roleIdOf(user.role);
  if (roleId.isEmpty) return false;
  final approvers = cfg['approvers'];
  if (approvers is! Map) return false;
  final step1 = _roleIdOf(approvers['step1']);
  final step2 = _roleIdOf(approvers['step2']);
  if (step1.isNotEmpty && step1 == roleId) return true;
  if (steps == 2 && step2.isNotEmpty && step2 == roleId) return true;
  return false;
}

/// Submitter cannot approve their own report. Super Admin can.
bool canActOnDprApproval(BuildContext context, Map<String, dynamic> report) {
  if (!canDpr(context, 'approve')) return false;
  final user = context.read<AuthProvider>().user;
  if (user == null) return false;
  if (Permissions(user).isSuperAdmin) return true;
  final author = idOf(report['prepared_by']) ??
      idOf(report['created_by']) ??
      idOf(report['approval'] is Map ? (report['approval'] as Map)['requested_by'] : null);
  return author == null || author.isEmpty || author != user.id;
}

bool orgHasTaskProgress(BuildContext context) {
  return orgHasModule(
    context.read<OrgSession>().organization,
    'project_management',
    'task_progress',
  );
}

int dprMediaCount(Map<String, dynamic> row) {
  final photos = row['photos'] is List ? (row['photos'] as List).length : 0;
  final videos = row['videos'] is List ? (row['videos'] as List).length : 0;
  final files = row['attachments'] is List ? (row['attachments'] as List).length : 0;
  return photos + videos + files;
}
