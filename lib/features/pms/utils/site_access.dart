import 'package:flutter/material.dart';

import '../../../core/network/api_exception.dart';

/// A 403 from an old project or task link. Lists never 403 for an off-site filter.
bool isSiteAccessDenied(ApiException error) {
  if (error.statusCode != 403) return false;
  final message = error.message.toLowerCase();
  return message.contains('not assigned');
}

/// No-access state for a 403 that arrived from a link or a save.
/// Returns true when the caller should stop and not show an error toast.
bool presentSiteAccessDenied(
  BuildContext context,
  ApiException error, {
  void Function(String message)? onNoAccess,
}) {
  if (!isSiteAccessDenied(error)) return false;
  final message = error.message.trim().isEmpty
      ? 'You are not assigned to this site'
      : error.message;
  if (onNoAccess != null) {
    onNoAccess(message);
    return true;
  }
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('No access'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  return true;
}
