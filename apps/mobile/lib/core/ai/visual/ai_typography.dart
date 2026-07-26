/// Dense type scale for AI surfaces.
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

import 'package:flutter/widgets.dart';

import '../../../design_system/design_system.dart';
import 'ai_tone.dart';

class AiType {
  AiType._();

  /// Primary body text on AI surfaces (chat bubbles, timeline rows).
  static TextStyle body(BuildContext c) => TypographyTokens.bodySmall.copyWith(
    height: 1.45,
    color: AiTone.onSurface(c),
  );

  /// Knowledge / long-form reading (notes, rationale, method) — calmer than
  /// chat density so detail pages feel like documents, not bubbles.
  static TextStyle readingBody(BuildContext c) => TypographyTokens.bodyLarge
      .copyWith(height: 1.62, color: AiTone.onSurface(c));

  /// Strong body text for selected rows and AI-surface section labels.
  static TextStyle bodyStrong(BuildContext c) => strong(body(c));

  /// Subtle metadata: timestamps, durations, "x ms", chip values.
  static TextStyle meta(BuildContext c) =>
      TypographyTokens.labelSmall.copyWith(height: 1.3, color: AiTone.muted(c));

  /// Strong metadata for selected dense timeline labels.
  static TextStyle metaStrong(BuildContext c) => strong(meta(c));

  /// Pill / capsule / chip label. Slightly weightier than meta to
  /// signal interactivity.
  static TextStyle label(BuildContext c) =>
      TypographyTokens.labelMedium.copyWith(
        height: 1.3,
        fontWeight: FontWeight.w500,
        color: AiTone.onSurface(c),
      );

  /// Sheet / page headers. Kept at Material titleMedium size so
  /// transitions from non-AI pages don't jump.
  static TextStyle title(BuildContext c) => TypographyTokens.titleLarge
      .copyWith(fontWeight: FontWeight.w600, color: AiTone.onSurface(c));

  /// Inline emphasis for markdown strong text and other AI-rendered content.
  static TextStyle strong(TextStyle base) =>
      base.copyWith(fontWeight: FontWeight.w600);

  /// Markdown heading style derived from the active AI body style so custom
  /// base styles keep their scale relationship.
  ///
  /// Reading bodies (~16sp) get a clearer ladder than chat (~13sp).
  static TextStyle heading(BuildContext c, TextStyle base, int level) {
    final baseSize = base.fontSize ?? 13;
    final reading = baseSize >= 15;
    final fontSize = switch (level) {
      1 => reading ? baseSize + 6 : baseSize + 3,
      2 => reading ? baseSize + 4 : baseSize + 2,
      _ => reading ? baseSize + 2 : baseSize + 1,
    };
    return strong(base).copyWith(
      fontSize: fontSize,
      height: reading ? 1.3 : 1.35,
      color: AiTone.onSurface(c),
    );
  }

  /// Table header style for markdown tables.
  static TextStyle tableHeader(BuildContext c, TextStyle base) =>
      strong(base).copyWith(color: AiTone.onSurface(c));
}
