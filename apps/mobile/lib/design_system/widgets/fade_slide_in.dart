import 'dart:async';

import 'package:flutter/material.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/motion_tokens.dart';

/// A reusable entrance animation: opacity 0 → 1 combined with a small
/// translate offset, driven by an [AnimationController].
///
/// Shared helper for widgets that should "appear" with a fade + slide rather
/// than popping in abruptly.
///
/// For staggered list entrances, wrap each item with a different [delay]:
///
/// ```dart
/// FadeSlideIn(
///   delay: Duration(milliseconds: index * 40),
///   child: MyCard(item),
/// )
/// ```
///
/// The animation respects [MediaQueryData.disableAnimations] — when
/// enabled, the child renders at full opacity with no offset.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = Motion.medium,
    this.curve = Motion.standardDecelerate,
    this.offset = const Offset(0, 6),
  });

  final Widget child;

  /// Delay before the animation starts. Useful for staggering a list
  /// of items so they cascade in rather than appearing all at once.
  final Duration delay;

  /// Duration of the fade + slide animation.
  final Duration duration;

  /// Easing curve for the animation.
  final Curve curve;

  /// The starting offset. The child slides from `offset` to
  /// [Offset.zero]. Default is 6dp downward (child slides up into place).
  final Offset offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delayTimer;
  bool? _motionEnabled;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = AppMotionPolicy.isEnabled(
      context,
      role: AppMotionRole.decorative,
    );
    _controller.duration = AppMotionPolicy.duration(
      context,
      widget.duration,
      role: AppMotionRole.decorative,
    );
    if (_motionEnabled == enabled) return;
    _motionEnabled = enabled;
    _delayTimer?.cancel();
    _controller.stop();
    if (!enabled) {
      _controller.value = 1;
      return;
    }

    _controller.value = 0;
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: widget.curve);

    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) {
          final t = 1 - curved.value;
          return Transform.translate(
            offset: Offset(widget.offset.dx * t, widget.offset.dy * t),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
