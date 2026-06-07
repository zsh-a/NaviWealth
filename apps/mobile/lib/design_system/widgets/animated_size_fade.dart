import 'package:flutter/material.dart';

import '../tokens/motion_tokens.dart';
import '../tokens/motion_utils.dart';

/// Combines [AnimatedSize] and [AnimatedOpacity] for content that
/// expands/collapses with a smooth height animation and fade.
///
/// When [visible] is `false`, the child is replaced by
/// [SizedBox.shrink()] with opacity 0 — the height animates to zero
/// and the content fades out simultaneously.
///
/// ```dart
/// AnimatedSizeFade(
///   visible: _expanded,
///   child: DetailSection(data),
/// )
/// ```
///
/// The animation respects [MediaQueryData.disableAnimations].
class AnimatedSizeFade extends StatelessWidget {
  const AnimatedSizeFade({
    super.key,
    required this.visible,
    required this.child,
    this.duration = Motion.medium,
    this.curve = Motion.standard,
    this.alignment = Alignment.topCenter,
  });

  /// Whether the child is visible. When toggled from `true` to `false`,
  /// the content fades out and the height collapses to zero.
  final bool visible;

  /// The content to show when [visible] is `true`.
  final Widget child;

  /// Duration for both the size and opacity transitions.
  final Duration duration;

  /// Easing curve for the [AnimatedSize] transition.
  final Curve curve;

  /// Alignment for the [AnimatedSize] expansion. Defaults to
  /// [Alignment.topCenter] so content grows downward.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final effectiveDuration = motionDuration(context, duration);

    return AnimatedSize(
      duration: effectiveDuration,
      curve: curve,
      alignment: alignment,
      child: AnimatedOpacity(
        duration: effectiveDuration,
        curve: curve,
        opacity: visible ? 1 : 0,
        child: visible ? child : const SizedBox.shrink(),
      ),
    );
  }
}
