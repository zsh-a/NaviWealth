import 'package:flutter/widgets.dart';

import '../tokens/typography_tokens.dart';
import 'theme_resolver.dart';

/// The single semantic type scale (blueprint doc 15, §4).
///
/// One authored value table — [TypographyTokens] — feeds three consumers:
///
/// * `context.appTheme.type` (this class) for semantic reads,
/// * the Forui `FTypography` slots via [buildAppTypeface] so the ~900
///   existing preset call sites resolve to the same values,
/// * the Material `TextTheme` via [TypographyTokens.textTheme].
///
/// Density note: the legacy Forui fork rendered every slot ~2px larger on
/// touch than on desktop, undocumented. That fork is deliberately removed —
/// glyph sizes are density-invariant (the mobile ladder converges on the
/// documented scale) and [AppDensity] only affects component chrome
/// (padding, hit targets) through Forui's touch/desktop styles.
@immutable
class AppTypeScale {
  const AppTypeScale._();

  static const AppTypeScale _instance = AppTypeScale._();

  /// Pure resolver hook. Sizes are density-invariant by decision (see class
  /// doc); the input keeps the resolver signature stable if that decision
  /// is ever revisited.
  static AppTypeScale resolve(AppDensity density) => _instance;

  // ── Display ────────────────────────────────────────────────────────────
  /// 40px Outfit — reserved for the page-level hero number.
  TextStyle get display => TypographyTokens.displayLarge;

  /// 32px — secondary marquee numbers and page heroes.
  TextStyle get displaySmall => TypographyTokens.displayMedium;

  // ── Headings ───────────────────────────────────────────────────────────
  /// 24px w600 — page titles, empty-state titles.
  TextStyle get heading => TypographyTokens.headlineLarge;

  /// 20px w600 — prominent section titles, sheet titles.
  TextStyle get headingSmall => TypographyTokens.headlineMedium;

  // ── Titles / body ──────────────────────────────────────────────────────
  /// 16px w600 — card titles, row heroes.
  TextStyle get title => TypographyTokens.titleLarge;

  /// 14px w600 — compact row titles, list labels.
  TextStyle get titleSmall => TypographyTokens.titleMedium;

  /// 16px w400 — long-form body copy.
  TextStyle get body => TypographyTokens.bodyLarge;

  /// 14px w400 — default body copy.
  TextStyle get bodySmall => TypographyTokens.bodyMedium;

  // ── Labels / captions ──────────────────────────────────────────────────
  /// 14px w600 +0.1 — buttons and emphasized labels.
  TextStyle get label => TypographyTokens.labelLarge;

  /// 12px w600 +0.4 — chips, overlines, dense labels.
  TextStyle get labelSmall => TypographyTokens.labelMedium;

  /// 12px w500 — metadata, timestamps, secondary captions. Pair with
  /// `content.muted` for the canonical caption read.
  TextStyle get caption => TypographyTokens.numericCaption;

  /// 11px w600 +0.5 — micro status tags.
  TextStyle get micro => TypographyTokens.labelSmall;

  /// 11px w500 — chart-internal annotations only.
  TextStyle get chartCaption => TypographyTokens.chartCaption;

  // ── Numerics (tabular by construction) ─────────────────────────────────
  TextStyle get numericDisplay => TypographyTokens.numericDisplay;
  TextStyle get numericTitle => TypographyTokens.numericTitle;
  TextStyle get numericTitleStrong => TypographyTokens.numericTitleStrong;
  TextStyle get numericBody => TypographyTokens.numericBody;
  TextStyle get numericBodyStrong => TypographyTokens.numericBodyStrong;
  TextStyle get numericCaption => TypographyTokens.numericCaption;
  TextStyle get numericCaptionStrong => TypographyTokens.numericCaptionStrong;
  TextStyle get numericMono => TypographyTokens.numericMono;
}

/// The Forui slot table, authored from the same scale.
///
/// Slot → semantic mapping (weights are applied by the preset extensions):
///
/// | slot | px / line-height | semantic |
/// |------|------------------|----------|
/// | xs3  | 10 / 1.3  | (legacy Forui slot — no design-system token maps here) |
/// | xs2  | 11 / 1.3  | micro / chartCaption |
/// | xs   | 12 / 1.35 | caption / labelSmall |
/// | sm   | 14 / 1.5  | bodySmall / titleSmall / label |
/// | md   | 16 / 1.5  | body / title |
/// | lg   | 18 / 1.35 | headline-small |
/// | xl   | 20 / 1.3  | headingSmall |
/// | xl2  | 24 / 1.25 | heading |
/// | xl3  | 32 / 1.15 | displaySmall |
/// | xl4  | 40 / 1.1  | display |
const List<({double size, double height})> kAppTypefaceSlots = [
  (size: 10, height: 1.3), // xs3
  (size: 11, height: 1.3), // xs2
  (size: 12, height: 1.35), // xs
  (size: 14, height: 1.5), // sm
  (size: 16, height: 1.5), // md
  (size: 18, height: 1.35), // lg
  (size: 20, height: 1.3), // xl
  (size: 24, height: 1.25), // xl2
  (size: 32, height: 1.15), // xl3
  (size: 40, height: 1.1), // xl4
  (size: 48, height: 1.05), // xl5
  (size: 60, height: 1), // xl6
  (size: 72, height: 1), // xl7
  (size: 96, height: 1), // xl8
];
