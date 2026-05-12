/// Wave 36 — motion tokens for AI surfaces.
///
/// Material's `easeOut` is right for general UI but feels "springy" on
/// AI panels (bottom sheet entrance, chip pop-in, undo banner reveal).
/// We adopt Linear's near-Bezier curve `cubicBezier(0.32, 0.72, 0, 1)`
/// — quick start, drawn-out tail — which reads as "calm computation"
/// rather than "snappy app".
///
/// Durations are tight: AI surfaces should feel *immediate*, not
/// animated. 120ms for micro transitions (hover, expand), 200ms for
/// container reveal (sheet, banner).
library;

import 'package:flutter/animation.dart';

class AiMotion {
  AiMotion._();

  /// Micro transitions: expand chevron, ripple, hover tint.
  static const Duration short = Duration(milliseconds: 120);

  /// Container reveal: bottom sheet entrance, banner fade, drawer slide.
  static const Duration medium = Duration(milliseconds: 200);

  /// Streaming "fade in next chunk" timing. Just barely perceptible
  /// so text reads naturally as it streams in.
  static const Duration tokenFade = Duration(milliseconds: 80);

  /// Linear-style ease-out. Quicker start, longer tail than Material
  /// easeOut. Use everywhere on AI surfaces.
  static const Curve standard = Cubic(0.32, 0.72, 0, 1);
}
