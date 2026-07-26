import 'package:flutter/material.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/motion_tokens.dart';
import 'app_interaction.dart';

/// A lightweight tap-feedback wrapper that scales its child down on press.
///
/// Use for icons, chips, and small tappable surfaces where a full
/// [SoftCard] (tint + shadow) would be too heavy. The scale animation
/// is 120ms ([Motion.fast]) with [Motion.standardDecelerate] so it
/// feels immediate and settles quickly.
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
      child: AnimatedScale(
        scale: _pressed ? context.appTheme.press.scale : 1,
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
