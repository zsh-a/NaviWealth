import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;

/// A [Curve] backed by a [SpringSimulation] for liquid-glass-style
/// spring animations.
///
/// The curve evaluates a critically-damped or underdamped spring from 0→1,
/// producing the elastic overshoot characteristic of iOS 26 Liquid Glass.
class LiquidSpringCurve extends Curve {
  /// Creates a spring curve.
  ///
  /// [dampingRatio] controls oscillation:
  /// - 1.0 = critically damped (no overshoot)
  /// - 0.75 = underdamped (slight bounce — good for press feedback)
  /// - 0.5 = more elastic
  ///
  /// [response] is the natural period in seconds (e.g. 0.4 for 400ms).
  const LiquidSpringCurve({
    this.dampingRatio = 0.75,
    this.response = 0.4,
  });

  final double dampingRatio;
  final double response;

  @override
  double transformInternal(double t) {
    // Convert damping ratio + response to spring constants.
    final omega = 2 * math.pi / response;
    final spring = SpringDescription(
      mass: 1,
      stiffness: omega * omega,
      damping: 2 * dampingRatio * omega,
    );
    final simulation = SpringSimulation(spring, 0, 1, 0);
    return simulation.x(t);
  }
}

/// Predefined spring curves for common Liquid Glass interactions.
class LiquidSprings {
  const LiquidSprings._();

  /// Press feedback — slight overshoot on release.
  static const Curve press = LiquidSpringCurve(
    dampingRatio: 0.75,
    response: 0.4,
  );

  /// Element entrance — bouncy settle.
  static const Curve appear = LiquidSpringCurve(
    dampingRatio: 0.8,
    response: 0.5,
  );

  /// Drag release — more elastic.
  static const Curve drag = LiquidSpringCurve(
    dampingRatio: 0.6,
    response: 0.45,
  );

  /// Returns [liquid] when [reduceMotion] is false, otherwise [fallback].
  static Curve adaptive(
    Curve liquid,
    Curve fallback, {
    required bool reduceMotion,
  }) {
    return reduceMotion ? fallback : liquid;
  }
}
