/// Wave 36 — dense type scale for AI surfaces.
///
/// Material defaults are tuned for general-purpose UI; AI surfaces
/// (chat, bottom sheet, transparency timeline) are *information-dense
/// by nature* — they look right with 1px-smaller body text and tighter
/// labels. Forms / settings / dashboards still use the Material scale.
///
/// Hierarchy (vs Material):
///   - body    13 (vs 14 bodyMedium) — chat text, event titles
///   - meta    11 (vs 12 labelSmall) — timestamps, durations, ms badges
///   - label   12 (vs 14 labelMedium) — pill labels, chip text
///   - title   16 (vs 16 titleMedium) — sheet headers (kept large)
///
/// All variants pull color from [AiTone] so light/dark theme swap is
/// automatic.
library;

import 'package:flutter/material.dart';

import 'ai_tone.dart';

class AiType {
  AiType._();

  /// Primary body text on AI surfaces (chat bubbles, timeline rows).
  static TextStyle body(BuildContext c) =>
      Theme.of(c).textTheme.bodyMedium!.copyWith(
        fontSize: 13,
        height: 1.45,
        color: AiTone.onSurface(c),
      );

  /// Subtle metadata: timestamps, durations, "x ms", chip values.
  static TextStyle meta(BuildContext c) =>
      Theme.of(c).textTheme.labelSmall!.copyWith(
        fontSize: 11,
        height: 1.3,
        color: AiTone.muted(c),
      );

  /// Pill / capsule / chip label. Slightly weightier than meta to
  /// signal interactivity.
  static TextStyle label(BuildContext c) =>
      Theme.of(c).textTheme.labelMedium!.copyWith(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w500,
        color: AiTone.onSurface(c),
      );

  /// Sheet / page headers. Kept at Material titleMedium size so
  /// transitions from non-AI pages don't jump.
  static TextStyle title(BuildContext c) =>
      Theme.of(c).textTheme.titleMedium!.copyWith(
        fontWeight: FontWeight.w600,
        color: AiTone.onSurface(c),
      );
}
