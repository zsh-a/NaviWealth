/// AI roles use the app's resolved type scale, including the active visual
/// preset. Reading, metadata and action labels retain their semantic roles.
library;

import 'package:flutter/widgets.dart';

import '../../../design_system/design_system.dart';
import 'ai_tone.dart';

class AiType {
  AiType._();

  /// Primary body text on AI surfaces (chat bubbles, timeline rows).
  static TextStyle body(BuildContext c) =>
      c.appTheme.type.bodySmall.copyWith(color: AiTone.onSurface(c));

  /// Knowledge / long-form reading (notes, rationale, method) — calmer than
  /// chat density so detail pages feel like documents, not bubbles.
  static TextStyle readingBody(BuildContext c) =>
      c.appTheme.type.body.copyWith(color: AiTone.onSurface(c));

  /// Strong body text for selected rows and AI-surface section labels.
  static TextStyle bodyStrong(BuildContext c) => strong(body(c));

  /// Subtle metadata: timestamps, durations, "x ms", chip values.
  static TextStyle meta(BuildContext c) =>
      c.appTheme.type.caption.copyWith(color: AiTone.muted(c));

  /// Strong metadata for selected dense timeline labels.
  static TextStyle metaStrong(BuildContext c) => strong(meta(c));

  /// Pill / capsule / chip label. Slightly weightier than meta to
  /// signal interactivity.
  static TextStyle label(BuildContext c) =>
      c.appTheme.type.labelSmall.copyWith(color: AiTone.onSurface(c));

  /// Sheet / page headers. Kept at Material titleMedium size so
  /// transitions from non-AI pages don't jump.
  static TextStyle title(BuildContext c) =>
      c.appTheme.type.title.copyWith(color: AiTone.onSurface(c));

  /// Inline emphasis for markdown strong text and other AI-rendered content.
  static TextStyle strong(TextStyle base) =>
      base.copyWith(fontWeight: FontWeight.w600);

  /// Markdown heading style derived from the active AI body style so custom
  /// base styles keep their scale relationship.
  ///
  /// Reading bodies (~16sp) get a clearer ladder than chat (~14sp).
  static TextStyle heading(BuildContext c, TextStyle base, int level) {
    final baseSize = base.fontSize ?? c.appTheme.type.bodySmall.fontSize!;
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
