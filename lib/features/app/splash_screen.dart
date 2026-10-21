import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../auth/providers/auth_provider.dart';
import '../auth/widgets/auth_widgets.dart';

/// Covers the first screen with the BldTrack mark until sign-in state is known.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _exit;
  AuthProvider? _auth;
  bool _introDone = false;
  bool _leaving = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _exit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce && !_introDone) {
      _intro.value = 1;
      _introDone = true;
    } else if (!_intro.isAnimating && _intro.value == 0 && !_introDone) {
      _intro.forward().whenComplete(() {
        if (!mounted) return;
        setState(() => _introDone = true);
        _maybeExit();
      });
    }
    final auth = context.read<AuthProvider>();
    if (!identical(_auth, auth)) {
      _auth?.removeListener(_onAuth);
      _auth = auth;
      _auth!.addListener(_onAuth);
    }
    _maybeExit();
  }

  void _onAuth() => _maybeExit();

  void _maybeExit() {
    if (!_introDone || _leaving || _gone || !mounted) return;
    final status = _auth?.status;
    if (status == null || status == AuthStatus.unknown) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _gone) return;
      _exit.forward().whenComplete(() {
        if (mounted) setState(() => _gone = true);
      });
    });
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuth);
    _intro.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0).animate(
            CurvedAnimation(parent: _exit, curve: Curves.easeIn),
          ),
          child: BldTrackSplashView(progress: _intro),
        ),
      ],
    );
  }
}

/// Animated BldTrack mark used on the opening splash.
class BldTrackSplashView extends StatelessWidget {
  const BldTrackSplashView({super.key, required this.progress});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppTheme.authGradient),
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          final t = progress.value;
          final mark = Curves.easeOutBack.transform(_slice(t, 0.0, 0.42));
          final glow = Curves.easeOut.transform(_slice(t, 0.05, 0.5));
          final ring = Curves.easeOut.transform(_slice(t, 0.18, 0.62));
          final title = Curves.easeOutCubic.transform(_slice(t, 0.32, 0.62));
          final line = Curves.easeOutCubic.transform(_slice(t, 0.46, 0.72));
          final tag = Curves.easeOut.transform(_slice(t, 0.56, 0.82));

          return Stack(
            fit: StackFit.expand,
            children: [
              const _SplashWash(),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: (1 - ring) * 0.7,
                            child: Transform.scale(
                              scale: 0.72 + (ring * 0.55),
                              child: Container(
                                width: 168,
                                height: 168,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: 150 + (glow * 18),
                            height: 150 + (glow * 18),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.22 * glow),
                                  blurRadius: 48,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          Transform.scale(
                            scale: 0.84 + (0.16 * mark),
                            child: const _SplashMark(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Opacity(
                      opacity: title,
                      child: Transform.translate(
                        offset: Offset(0, (1 - title) * 14),
                        child: Text(
                          'BldTrack',
                          style: AppTheme.displaySmall.copyWith(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.1,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: 64 * line,
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0x00FFFFFF),
                            Color(0xFFF8FAFC),
                            Color(0xFFFBBF24),
                            Color(0xFFF8FAFC),
                            Color(0x00FFFFFF),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Opacity(
                      opacity: tag,
                      child: Text(
                        'Build smarter',
                        style: AppTheme.bodySmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 16,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _slice(double t, double start, double end) {
    if (t <= start) return 0;
    if (t >= end) return 1;
    return (t - start) / (end - start);
  }
}

class _SplashWash extends StatelessWidget {
  const _SplashWash();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned(
          top: -80,
          left: -60,
          child: _SoftOrb(size: 260, alpha: 0.16),
        ),
        Positioned(
          right: -90,
          bottom: -40,
          child: _SoftOrb(size: 320, alpha: 0.14),
        ),
      ],
    );
  }
}

class _SoftOrb extends StatelessWidget {
  const _SoftOrb({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.white.withValues(alpha: alpha),
              Colors.white.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Login mark, presented larger for the opening screen.
class _SplashMark extends StatelessWidget {
  const _SplashMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.34),
            Colors.white.withValues(alpha: 0.12),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E1B4B).withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: const Icon(
        Icons.apartment_rounded,
        color: Colors.white,
        size: 58,
      ),
    );
  }
}
