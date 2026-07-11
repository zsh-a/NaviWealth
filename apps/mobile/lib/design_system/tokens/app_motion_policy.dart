import 'package:flutter/widgets.dart';

/// Semantic motion categories used across the app.
///
/// A role makes intent explicit at every animation boundary, so continuous
/// decoration, status feedback, and navigational transitions can evolve
/// independently without scattering platform checks through feature code.
enum AppMotionRole { transition, decorative, status }

/// The single accessibility boundary for application-owned motion.
abstract final class AppMotionPolicy {
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  static bool isEnabled(BuildContext context, {required AppMotionRole role}) {
    if (!reduceMotion(context)) return true;
    return switch (role) {
      AppMotionRole.transition ||
      AppMotionRole.decorative ||
      AppMotionRole.status => false,
    };
  }

  static Duration duration(
    BuildContext context,
    Duration duration, {
    AppMotionRole role = AppMotionRole.transition,
  }) => isEnabled(context, role: role) ? duration : Duration.zero;
}
