import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart'
    show FAccessibilityMotion, FAccessibilityScope;

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
/// * [AppMotionRole.transition] — short fades under reduced motion.
/// * [AppMotionRole.decorative] — disabled outright (shimmer, staggers,
///   press scales, chart draw-ins).
/// * [AppMotionRole.status] — disabled; status is always double-encoded
///   (color + icon/text), so losing the pulse loses no information.
/// System "Remove animations" disables all three roles.
abstract final class AppMotionPolicy {
  static FAccessibilityMotion _platformMotion() {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    if (features.disableAnimations) return FAccessibilityMotion.disabled;
    if (features.reduceMotion) return FAccessibilityMotion.reduced;
    return FAccessibilityMotion.all;
  }

  static bool get platformReduceMotion =>
      _platformMotion() != FAccessibilityMotion.all;

  static FAccessibilityMotion _motion(BuildContext context) {
    // Forui observes accessibility changes, including the iOS-only
    // reduceMotion flag that MediaQuery.disableAnimations does not expose.
    if (context.findAncestorWidgetOfExactType<FAccessibilityScope>() != null) {
      return FAccessibilityScope.motionOf(context);
    }
    return _platformMotion();
  }

  static bool disableAnimations(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      _motion(context) == FAccessibilityMotion.disabled;

  static bool reduceMotion(BuildContext context) =>
      disableAnimations(context) ||
      _motion(context) == FAccessibilityMotion.reduced;

  static bool isEnabled(BuildContext context, {required AppMotionRole role}) {
    if (disableAnimations(context)) return false;
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
    if (disableAnimations(context)) return Duration.zero;
    if (!reduceMotion(context)) return duration;
    return switch (role) {
      AppMotionRole.transition => duration * 0.5,
      AppMotionRole.decorative || AppMotionRole.status => Duration.zero,
    };
  }

  /// Route duration getters have no BuildContext; use the same system flags.
  static Duration platformDuration(Duration duration) {
    return switch (_platformMotion()) {
      FAccessibilityMotion.disabled => Duration.zero,
      FAccessibilityMotion.reduced => duration * 0.5,
      FAccessibilityMotion.all => duration,
    };
  }
}
