import 'package:flutter/widgets.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/motion_tokens.dart';

/// One-shot fade + slide-up entrance for content that mounts into an
/// already-visible surface — chat messages, list rows, inline results.
///
/// Extracted from the AI chat message bubble so any surface can adopt the
/// same micro-interaction instead of hand-rolling a `TweenAnimationBuilder`:
///
/// ```dart
/// AppEntrance(child: MessageRow(entry))
/// ```
///
/// Motion is routed through [AppMotionPolicy] with [role]
/// ([AppMotionRole.transition] by default): under reduce-motion the duration
/// is policy-adjusted, so there is no bespoke `MediaQuery` check at the call
/// site. Pass [AppMotionRole.decorative] for purely presentational entrances
/// that should be skipped outright under reduce-motion.
///
/// Unlike [FadeSlideIn] (controller-driven, decorative, supports stagger
/// delays), this widget is stateless and transition-scoped — the right fit
/// for items inserted into a live list where each insertion should animate
/// exactly once.
class AppEntrance extends StatelessWidget {
  const AppEntrance({
    super.key,
    required this.child,
    this.enabled = true,
    this.duration = Motion.medium,
    this.curve = Motion.standardDecelerate,
    this.slideDistance = 8,
    this.role = AppMotionRole.transition,
  });

  final Widget child;

  /// Set to `false` to render [child] directly with no entrance animation.
  /// Bulk-mounted historical content (e.g. a restored chat timeline) should
  /// opt out so it doesn't compete with the surrounding surface transition.
  final bool enabled;

  /// Duration of the fade + slide animation. → [Motion.medium]
  final Duration duration;

  /// Easing curve for the animation. → [Motion.standardDecelerate]
  final Curve curve;

  /// Vertical distance (dp) the child slides up from. → 8
  final double slideDistance;

  /// Motion role used for the [AppMotionPolicy] reduce-motion decision.
  final AppMotionRole role;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotionPolicy.duration(context, duration, role: role),
      curve: curve,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, slideDistance * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
