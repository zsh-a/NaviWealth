import 'package:flutter/widgets.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/motion_tokens.dart';

/// Crossfades between mutually-exclusive action affordances that occupy one
/// slot — e.g. the chat composer's send ↔ stop button.
///
/// Extracted from the AI chat composer so any surface with a state-dependent
/// trailing action gets the same morph instead of hand-rolling an
/// `AnimatedSwitcher`:
///
/// ```dart
/// AppMorphingAction(
///   child: isBusy
///       ? AppIconButton(key: const ValueKey('stop'), ...)
///       : AppIconButton(key: const ValueKey('send'), ...),
/// )
/// ```
///
/// Key the child by state ([ValueKey]) so the switcher can tell the two
/// affordances apart. The default transition is a plain crossfade; pass a
/// custom [transitionBuilder] (e.g. fade + scale) for a heavier morph.
///
/// Duration is routed through [AppMotionPolicy], so reduce-motion contexts
/// get the policy-adjusted switch with no call-site `MediaQuery` check.
class AppMorphingAction extends StatelessWidget {
  const AppMorphingAction({
    super.key,
    required this.child,
    this.duration = Motion.fast,
    this.transitionBuilder = _crossfade,
  });

  /// The currently active affordance. Callers must key it by state so
  /// switching states triggers the transition.
  final Widget child;

  /// Duration of the morph. → [Motion.fast] (tap-feedback tier)
  final Duration duration;

  /// How the outgoing child is replaced. Defaults to a crossfade.
  final AnimatedSwitcherTransitionBuilder transitionBuilder;

  static Widget _crossfade(Widget child, Animation<double> animation) {
    return FadeTransition(opacity: animation, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotionPolicy.duration(context, duration),
      transitionBuilder: transitionBuilder,
      child: child,
    );
  }
}
