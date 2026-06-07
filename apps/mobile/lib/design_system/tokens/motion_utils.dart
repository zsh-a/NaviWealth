import 'package:flutter/widgets.dart';

/// Returns [Duration.zero] when the user has enabled "reduce motion" in
/// system accessibility settings, otherwise returns [duration].
///
/// Use this to wrap any animation duration so the app respects the
/// `MediaQueryData.disableAnimations` flag consistently:
///
/// ```dart
/// AnimatedOpacity(
///   opacity: visible ? 1 : 0,
///   duration: motionDuration(context, Motion.medium),
///   child: child,
/// )
/// ```
Duration motionDuration(BuildContext context, Duration duration) {
  return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
