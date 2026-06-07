import 'package:flutter/animation.dart';

/// Duration + easing scale for animations.
///
/// Exposed so screens use the same micro-interaction feel (e.g. number
/// tickers, page transitions, sheet enters) instead of inventing one-off
/// durations.
class Motion {
  const Motion._();

  // Durations.
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration medium = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 360);
  static const Duration ticker = Duration(milliseconds: 800);

  // Easings — Material 3 emphasized + decelerate.
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve standardDecelerate = Cubic(0.0, 0.0, 0.0, 1.0);
  static const Curve standardAccelerate = Cubic(0.3, 0.0, 1.0, 1.0);

  /// Linear fallback for reduced-motion contexts where [Duration.zero]
  /// is too abrupt but a cubic ease would feel wrong.
  static const Curve reducedMotion = Curves.linear;

  // --- Semantic aliases (scenario → duration) ---
  // Map UX intent to the right tier. Adjust the underlying constants
  // above to shift the app's overall feel without touching call sites.

  /// Button/icon press, hover tint. → [fast]
  static const Duration tapFeedback = fast;

  /// Content expand/collapse, filter panel toggle. → [medium]
  static const Duration componentChange = medium;

  /// List item enter, cross-fade between states. → [medium]
  static const Duration contentTransition = medium;

  /// Page route transition. → [slow]
  static const Duration pageTransition = slow;
}
