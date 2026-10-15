import 'package:flutter/material.dart';

/// Short, layout-neutral motion for page entry and presses.
///
/// Transforms never change child constraints, so card size, spacing, and hit
/// targets stay the same once a move has settled. Reduced-motion users get the
/// resting UI immediately.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    super.key,
    required this.child,
    this.active = true,
    this.replayToken,
    this.maxIndex = 6,
    this.slide = 24,
  });

  final Widget child;

  /// When false, the entrance waits and does not replay a finished move.
  final bool active;

  /// Changing this replays the entrance the next time [active] is true.
  final Object? replayToken;

  final int maxIndex;
  final double slide;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  static const double _itemMs = 460;
  static const double _stepMs = 55;

  late final AnimationController _controller;
  bool _reduce = false;
  bool _started = false;
  Object? _token;

  double get _totalMs => _itemMs + widget.maxIndex * _stepMs;

  @override
  void initState() {
    super.initState();
    _token = widget.replayToken;
    _controller = AnimationController(vsync: this, duration: _duration);
  }

  Duration get _duration => Duration(milliseconds: _totalMs.round());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce != _reduce) {
      _reduce = reduce;
      if (reduce) {
        _controller.value = 1;
        _controller.stop();
      }
    }
    _maybePlay();
  }

  @override
  void didUpdateWidget(StaggeredEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.maxIndex != oldWidget.maxIndex) {
      _controller.duration = _duration;
    }
    if (widget.replayToken != _token) {
      _token = widget.replayToken;
      _started = false;
      if (!_reduce) _controller.value = 0;
    }
    _maybePlay();
  }

  void _maybePlay() {
    if (_reduce || !widget.active || _started) return;
    _started = true;
    // The emulator often drops the first frames of a new screen. The clock
    // would otherwise finish this motion before a single in-between frame
    // is drawn. Wait until a frame has been painted, then move.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _reduce) return;
        if (!widget.active) {
          _started = false;
          return;
        }
        _controller.forward(from: 0);
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _MotionScope(
      controller: _controller,
      reduced: _reduce,
      maxIndex: widget.maxIndex,
      itemMs: _itemMs,
      stepMs: _stepMs,
      totalMs: _totalMs,
      slide: widget.slide,
      child: widget.child,
    );
  }
}

class _MotionScope extends InheritedWidget {
  const _MotionScope({
    required this.controller,
    required this.reduced,
    required this.maxIndex,
    required this.itemMs,
    required this.stepMs,
    required this.totalMs,
    required this.slide,
    required super.child,
  });

  final AnimationController controller;
  final bool reduced;
  final int maxIndex;
  final double itemMs;
  final double stepMs;
  final double totalMs;
  final double slide;

  static _MotionScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_MotionScope>();
  }

  @override
  bool updateShouldNotify(_MotionScope oldWidget) {
    return controller != oldWidget.controller ||
        reduced != oldWidget.reduced ||
        maxIndex != oldWidget.maxIndex ||
        totalMs != oldWidget.totalMs ||
        slide != oldWidget.slide;
  }
}

/// Fades and rises into place. Index is capped so long lists stay snappy.
class EntranceItem extends StatefulWidget {
  const EntranceItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<EntranceItem> createState() => _EntranceItemState();
}

class _EntranceItemState extends State<EntranceItem> {
  _MotionScope? _scope;
  CurvedAnimation? _curved;
  int? _boundIndex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind(_MotionScope.maybeOf(context));
  }

  @override
  void didUpdateWidget(EntranceItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) _bind(_scope);
  }

  void _bind(_MotionScope? scope) {
    if (scope == null || scope.reduced || scope.totalMs <= 0) {
      _release();
      _scope = scope;
      _boundIndex = widget.index;
      return;
    }
    if (identical(scope, _scope) &&
        _curved != null &&
        _boundIndex == widget.index) {
      return;
    }
    _release();
    _scope = scope;
    _boundIndex = widget.index;
    final index = widget.index.clamp(0, scope.maxIndex);
    final start = index * scope.stepMs / scope.totalMs;
    final end = ((index * scope.stepMs) + scope.itemMs) / scope.totalMs;
    _curved = CurvedAnimation(
      parent: scope.controller,
      curve: Interval(start, end.clamp(0.0, 1.0), curve: Curves.easeOutCubic),
    );
  }

  void _release() {
    _curved?.dispose();
    _curved = null;
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _MotionScope.maybeOf(context);
    final curved = _curved;
    if (scope == null || scope.reduced || curved == null) return widget.child;
    return FadeTransition(
      opacity: curved,
      child: _Rise(
        animation: curved,
        distance: scope.slide,
        child: widget.child,
      ),
    );
  }
}

class _Rise extends AnimatedWidget {
  const _Rise({
    required Animation<double> animation,
    required this.distance,
    required this.child,
  }) : super(listenable: animation);

  final double distance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    return Transform.translate(
      offset: Offset(0, distance * (1 - t)),
      child: child,
    );
  }
}

/// One-shot fade and rise for content that appears after the page entrance.
class SoftAppear extends StatefulWidget {
  const SoftAppear({super.key, required this.child});

  final Widget child;

  @override
  State<SoftAppear> createState() => _SoftAppearState();
}

class _SoftAppearState extends State<SoftAppear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.forward(from: 0);
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: _Rise(animation: _controller, distance: 8, child: widget.child),
    );
  }
}

/// Scales slightly while a pointer is down. Layout size stays put.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled) value = false;
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(PressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pressed) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1,
        alignment: Alignment.center,
        duration: Duration(milliseconds: _pressed ? 140 : 220),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
