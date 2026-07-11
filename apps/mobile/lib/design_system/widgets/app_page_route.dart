import 'package:flutter/widgets.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/motion_tokens.dart';

/// Builds an imperative page route that shares the app motion policy.
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
    transitionsBuilder: transitionsBuilder ?? (_, _, _, child) => child,
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
