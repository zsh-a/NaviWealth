import 'package:flutter/material.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/motion_tokens.dart';

/// Scales [child] down while [pressed] and springs back to rest on release.
///
/// Press-down is a fast curve ([Motion.tapFeedback] +
/// [Motion.standardDecelerate]) so the touch feels immediate; the release is
/// a [Motion.springSnappy] simulation that inherits the press animation's
/// velocity, giving a physical rebound instead of a mirrored ease.
///
/// This is decorative-role motion: when AppMotionPolicy disables decoration
/// (reduce-motion), the scale stays at 1 instead of animating or snapping.
///
/// Shared by [PressableScale] and [SoftCard] so every pressable surface in
/// the app rebounds with the same spring.
class SpringPressScale extends StatefulWidget {
  const SpringPressScale({
    super.key,
    required this.pressed,
    required this.child,
    this.pressedScale,
  });

  /// Whether the press is currently held.
  final bool pressed;
  final Widget child;

  /// Scale applied while pressed. Defaults to the theme press spec
  /// (`context.appTheme.press.scale`).
  final double? pressedScale;

  @override
  State<SpringPressScale> createState() => _SpringPressScaleState();
}

class _SpringPressScaleState extends State<SpringPressScale>
    with SingleTickerProviderStateMixin {
  // Unbounded so the release spring can overshoot 1 without clamping.
  late final AnimationController _scale = AnimationController.unbounded(
    value: 1,
    vsync: this,
  );
  double _pressedScale = 1;
  bool _motionEnabled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pressedScale = widget.pressedScale ?? context.appTheme.press.scale;
    _motionEnabled = AppMotionPolicy.isEnabled(
      context,
      role: AppMotionRole.decorative,
    );
    if (!_motionEnabled) _snapToRest();
  }

  @override
  void didUpdateWidget(covariant SpringPressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pressed != widget.pressed) _animate();
  }

  void _animate() {
    if (!_motionEnabled) {
      _snapToRest();
      return;
    }
    if (widget.pressed) {
      _scale.animateTo(
        _pressedScale,
        duration: Motion.tapFeedback,
        curve: Motion.standardDecelerate,
      );
    } else {
      _scale.animateWithSpring(Motion.springSnappy, 1);
    }
  }

  void _snapToRest() {
    _scale
      ..stop()
      ..value = 1;
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: widget.child,
    );
  }
}
