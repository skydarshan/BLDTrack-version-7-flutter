import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motion.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.animateEntrance = false,
  });

  final String title;
  final String subtitle;
  final Widget child;

  /// Page-entry fade and rise. Off for screens that share this shell.
  final bool animateEntrance;

  Widget _slot(int index, Widget child) {
    if (!animateEntrance) return child;
    return EntranceItem(index: index, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _slot(
          0,
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.apartment_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BldTrack',
                    style: AppTheme.headlineSmall.copyWith(
                      color: Colors.white,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Build smarter',
                    style: AppTheme.bodySmall.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _slot(
          1,
          Text(
            title,
            style: AppTheme.displaySmall.copyWith(
              color: Colors.white,
              fontSize: 32,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _slot(
          2,
          Text(
            subtitle,
            style: AppTheme.bodySmall.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _slot(
          3,
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                  boxShadow: AppTheme.elevatedShadow,
                ),
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: AppTheme.authGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: animateEntrance
                    ? StaggeredEntrance(maxIndex: 3, slide: 28, child: column)
                    : column,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoadingButton extends StatelessWidget {
  const LoadingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(label),
    );
  }
}
