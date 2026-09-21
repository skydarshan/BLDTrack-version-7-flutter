/// Shared PMS option lists (match React / API enums).
class PmsConstants {
  static const projectStatuses = [
    ('not_started', 'Not started'),
    ('in_progress', 'In progress'),
    ('on_hold', 'On hold'),
    ('completed', 'Completed'),
  ];

  static const taskSettableStatuses = [
    ('not_started', 'Not started'),
    ('in_progress', 'In progress'),
    ('on_hold', 'On hold'),
    ('cancelled', 'Cancelled'),
  ];

  static const boardColumns = [
    ('not_started', 'Not started'),
    ('in_progress', 'In progress'),
    ('revise', 'Revise'),
    ('pending_approval', 'Pending approval'),
    ('on_hold', 'On hold'),
    ('completed', 'Completed'),
    ('cancelled', 'Cancelled'),
  ];

  static const taskBoardFilterStatuses = [
    ('not_started', 'Not started'),
    ('in_progress', 'In progress'),
    ('revise', 'Revise'),
    ('pending_approval', 'Pending approval'),
    ('on_hold', 'On hold'),
    ('completed', 'Completed'),
    ('cancelled', 'Cancelled'),
  ];

  static const priorities = [
    ('low', 'Low'),
    ('medium', 'Medium'),
    ('high', 'High'),
    ('urgent', 'Urgent'),
  ];

  static const templateScopes = [
    ('organization', 'Organization'),
    ('global', 'Global'),
  ];

  /// Map board chip → list API status (when not using /tasks/my).
  static String? toListApiStatus(String? boardStatus) {
    if (boardStatus == null || boardStatus.isEmpty) return null;
    if (boardStatus == 'pending_approval') return 'completion_requested';
    if (boardStatus == 'revise') return null;
    return boardStatus;
  }

  static String labelFor(
    List<(String, String)> options,
    String? value, {
    String fallback = '—',
  }) {
    if (value == null || value.isEmpty) return fallback;
    for (final o in options) {
      if (o.$1 == value) return o.$2;
    }
    return value.replaceAll('_', ' ');
  }
}
