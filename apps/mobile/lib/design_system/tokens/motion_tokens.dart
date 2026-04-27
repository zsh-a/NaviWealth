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
}
