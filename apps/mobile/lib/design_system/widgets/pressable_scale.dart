import 'package:flutter/material.dart';

import '../../core/haptics/haptics.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/motion_tokens.dart';

/// A lightweight tap-feedback wrapper that scales its child down on press.
///
/// Use for icons, chips, and small tappable surfaces where a full
/// [SoftCard] (tint + shadow) would be too heavy. The scale animation
/// is 120ms ([Motion.fast]) with [Motion.standardDecelerate] so it
/// feels immediate and settles quickly.
///
/// Pair with [Haptics.primaryPress] by default — set `haptic: false`
/// for secondary or non-primary interactions.
///
/// ```dart
/// PressableScale(
///   onTap: () => context.push('/detail'),
///   child: Icon(Icons.arrow_forward),
/// )
/// ```
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.haptic = true,
    this.scaleFactor = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Whether to fire [Haptics.primaryPress] on tap-down.
  final bool haptic;

  /// The scale factor applied when pressed. 0.97 gives a subtle
  /// "press in" feel without being distracting.
  final double scaleFactor;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _pressed = true);
        if (widget.haptic) Haptics.primaryPress();
      },
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      child: AnimatedScale(
        scale: _pressed ? widget.scaleFactor : 1,
        duration: AppMotionPolicy.duration(
          context,
          Motion.fast,
          role: AppMotionRole.decorative,
        ),
        curve: Motion.standardDecelerate,
        child: widget.child,
      ),
    );
  }
}
