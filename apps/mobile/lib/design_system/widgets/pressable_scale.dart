import 'package:flutter/material.dart';

import 'app_interaction.dart';
import 'spring_press_scale.dart';

/// A lightweight tap-feedback wrapper that scales its child down on press.
///
/// Use for icons, chips, and small tappable surfaces where a full
/// [SoftCard] (tint + shadow) would be too heavy. Press-down is a fast
/// curve ([Motion.tapFeedback]); release rebounds with the shared
/// [Motion.springSnappy] spring via [SpringPressScale]. Under reduce-motion
/// the press scale is disabled entirely.
///
/// Haptics go through [AppInteraction] so the emotional grammar stays shared
/// with SoftCard / FAB / filters. Set [haptic] false for purely visual press.
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
    this.intent = AppInteractionIntent.select,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Whether to fire semantic haptics on tap-down.
  final bool haptic;

  /// Semantic intent when [haptic] is true.
  final AppInteractionIntent intent;

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
        if (widget.haptic) AppInteraction.signal(widget.intent);
      },
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      child: SpringPressScale(pressed: _pressed, child: widget.child),
    );
  }
}
