import 'package:flutter/material.dart';

import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.label});

  final String? status;
  final String? label;

  Color _bg() {
    switch (status) {
      case 'completed':
      case 'Closed':
      case 'Approved':
        return const Color(0xFFB7EB8F);
      case 'Dispatched':
      case 'Partially Received':
      case 'in_progress':
        return const Color(0xFF91D5FF);
      case 'on_hold':
        return const Color(0xFFFFD666);
      case 'cancelled':
      case 'archived':
      case 'Rejected':
        return const Color(0xFFD9D9D9);
      case 'pending':
      case 'hold':
      case 'open':
      case 'Pending':
      case 'draft':
        return const Color(0xFFFFD666);
      case 'approved':
        return const Color(0xFFB7EB8F);
      case 'revision_requested':
        return const Color(0xFFFFADD2);
      case 'not_started':
        return const Color(0xFFE6F4FF);
      case 'partial':
        return const Color(0xFF91D5FF);
      case 'completion_requested':
      case 'pending_approval':
        return const Color(0xFFD3ADF7);
      case 'revise':
        return const Color(0xFFFFADD2);
      default:
        return const Color(0xFFE6F4FF);
    }
  }

  Color _fg() {
    switch (status) {
      case 'completed':
      case 'Closed':
      case 'Approved':
        return const Color(0xFF237804);
      case 'Dispatched':
      case 'Partially Received':
      case 'in_progress':
        return const Color(0xFF0050B3);
      case 'on_hold':
        return const Color(0xFFAD6800);
      case 'cancelled':
      case 'archived':
      case 'Rejected':
        return const Color(0xFF434343);
      case 'pending':
      case 'hold':
      case 'open':
      case 'Pending':
      case 'draft':
        return const Color(0xFFAD6800);
      case 'approved':
        return const Color(0xFF237804);
      case 'revision_requested':
        return const Color(0xFFC41D7F);
      case 'not_started':
        return AppTheme.brand;
      case 'partial':
        return const Color(0xFF0050B3);
      case 'completion_requested':
      case 'pending_approval':
        return const Color(0xFF531DAB);
      case 'revise':
        return const Color(0xFFC41D7F);
      default:
        return AppTheme.brand;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _bg(),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label ?? statusLabel(status),
        style: TextStyle(
          color: _fg(),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class PriorityChip extends StatelessWidget {
  const PriorityChip({super.key, required this.priority});

  final String? priority;

  @override
  Widget build(BuildContext context) {
    final p = (priority ?? 'medium').toLowerCase();
    final color = switch (p) {
      'urgent' => AppTheme.danger,
      'high' => AppTheme.warning,
      'low' => AppTheme.muted,
      _ => AppTheme.brand,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.softBg(color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        p,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
    this.icon,
    this.accentColor,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppTheme.brand;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
            boxShadow: AppTheme.cardShadow,
            border: Border.all(color: AppTheme.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  AppIconBadge(icon: icon!, color: color, size: 34, iconSize: 18),
                  const SizedBox(height: 8),
                ],
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.displaySmall.copyWith(
                    fontSize: 22,
                    height: 1.1,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.labelMedium.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.inbox_rounded, size: 40, color: AppTheme.brand.withValues(alpha: 0.45)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scrollable loader that sits in the middle of the remaining page.
class CenteredScrollLoader extends StatelessWidget {
  const CenteredScrollLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : 240.0;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: height,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ],
        );
      },
    );
  }
}

/// Empty message centered in the remaining page, still pull-to-refreshable.
class EmptyListBody extends StatelessWidget {
  const EmptyListBody({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : 320.0;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: height,
              child: EmptyState(message: message, icon: icon),
            ),
          ],
        );
      },
    );
  }
}

class ListPaginationRow extends StatelessWidget {
  const ListPaginationRow({
    super.key,
    required this.page,
    required this.totalPages,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int totalPages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(onPressed: onPrev, child: const Text('Prev')),
          Text('$page / $totalPages', style: const TextStyle(color: AppTheme.muted)),
          TextButton(onPressed: onNext, child: const Text('Next')),
        ],
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFEE2E2),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: const TextStyle(color: AppTheme.danger)),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

Future<void> showPmsSnack(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? AppTheme.danger : AppTheme.brand,
      duration: Duration(seconds: error ? 5 : 3),
    ),
  );
  return Future.value();
}

Future<void> showSavedConfirmation(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Saved'),
      content: Text(message),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}

/// Inline banner listing field validation errors at the top of a form.
class ValidationSummaryBanner extends StatelessWidget {
  const ValidationSummaryBanner({super.key, required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, color: AppTheme.danger, size: 20),
              SizedBox(width: 8),
              Text(
                'Please fix the following:',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final msg in messages)
            Padding(
              padding: const EdgeInsets.only(left: 28, bottom: 4),
              child: Text(
                '• $msg',
                style: const TextStyle(color: Color(0xFF991B1B), height: 1.35),
              ),
            ),
        ],
      ),
    );
  }
}

class NamedItemLines extends StatelessWidget {
  const NamedItemLines({super.key, required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Items', style: TextStyle(fontWeight: FontWeight.w700)),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No line items'),
          )
        else
          for (final line in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(itemLabel(line)),
              subtitle: Text(
                itemQtySubtitle(line).isEmpty ? '—' : itemQtySubtitle(line),
              ),
            ),
      ],
    );
  }
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

class ListDeleteMenu extends StatelessWidget {
  const ListDeleteMenu({super.key, required this.onDelete});

  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'delete') onDelete?.call();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: AppTheme.danger)),
        ),
      ],
    );
  }
}
