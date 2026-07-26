import 'package:flutter/widgets.dart';

/// Semantic motion categories used across the app.
///
/// A role makes intent explicit at every animation boundary, so continuous
/// decoration, status feedback, and navigational transitions can evolve
/// independently without scattering platform checks through feature code.
enum AppMotionRole { transition, decorative, status }

/// The single accessibility boundary for application-owned motion.
///
/// Under reduce-motion the three roles degrade differently (doc 11 §12):
///
/// * [AppMotionRole.transition] — stays enabled with **halved** durations,
///   so navigation and sheet chrome keep a legible cross-fade instead of
///   teleporting (the route builders already swap slides for fades).
/// * [AppMotionRole.decorative] — disabled outright (shimmer, staggers,
///   press scales, chart draw-ins).
/// * [AppMotionRole.status] — disabled; status is always double-encoded
///   (color + icon/text), so losing the pulse loses no information.
abstract final class AppMotionPolicy {
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  static bool isEnabled(BuildContext context, {required AppMotionRole role}) {
    if (!reduceMotion(context)) return true;
    return switch (role) {
      AppMotionRole.transition => true,
      AppMotionRole.decorative || AppMotionRole.status => false,
    };
  }

  static Duration duration(
    BuildContext context,
    Duration duration, {
    AppMotionRole role = AppMotionRole.transition,
  }) {
    if (!reduceMotion(context)) return duration;
    return switch (role) {
      AppMotionRole.transition => duration * 0.5,
      AppMotionRole.decorative || AppMotionRole.status => Duration.zero,
    };
  }
}
