import 'package:flutter/widgets.dart';

import '../theme/app_page_transitions.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/motion_tokens.dart';

/// Builds an imperative page route that shares the app motion policy.
///
/// The default transition is the same width-aware fade + slide declarative
/// routes get from [AppPageTransitionsBuilder] — imperative pushes no longer
/// teleport. Pass [transitionsBuilder] only for surfaces that genuinely need
/// a bespoke enter animation.
PageRouteBuilder<T> buildAppPageRoute<T>({
  required BuildContext context,
  required RoutePageBuilder pageBuilder,
  RouteTransitionsBuilder? transitionsBuilder,
  bool fullscreenDialog = false,
  Duration transitionDuration = Motion.pageTransition,
  Duration reverseTransitionDuration = Motion.componentChange,
}) {
  return PageRouteBuilder<T>(
    fullscreenDialog: fullscreenDialog,
    pageBuilder: pageBuilder,
    transitionsBuilder:
        transitionsBuilder ??
        (context, animation, _, child) =>
            AppPageTransitionsBuilder.buildAppTransition(
              context,
              animation,
              child,
            ),
    transitionDuration: AppMotionPolicy.duration(
      context,
      transitionDuration,
      role: AppMotionRole.transition,
    ),
    reverseTransitionDuration: AppMotionPolicy.duration(
      context,
      reverseTransitionDuration,
      role: AppMotionRole.transition,
    ),
  );
}
