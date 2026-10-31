import 'package:flutter/widgets.dart';

import '../tokens/typography_tokens.dart';
import 'app_visual_style.dart';
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
  const AppTypeScale._(this._visualStyle);

  final AppVisualStyle _visualStyle;

  static const AppTypeScale _classic = AppTypeScale._(AppVisualStyle.classic);
  static const AppTypeScale _refined = AppTypeScale._(AppVisualStyle.refined);

  /// Pure resolver hook. Sizes are density-invariant by decision (see class
  /// doc); the input keeps the resolver signature stable if that decision
  /// is ever revisited.
  static AppTypeScale resolve(
    AppDensity density, {
    AppVisualStyle visualStyle = AppVisualStyle.refined,
  }) => visualStyle == AppVisualStyle.refined ? _refined : _classic;

  TextStyle _style(TextStyle style) => appVisualTextStyle(style, _visualStyle);

  // ── Display ────────────────────────────────────────────────────────────
  /// 48px — measured, medium-weight Inter for page-level amounts.
  TextStyle get display => _style(TypographyTokens.displayLarge);

  /// 32px — secondary marquee numbers and page heroes.
  TextStyle get displaySmall => _style(TypographyTokens.displayMedium);

  /// 26px — compact verdicts and chart-center values.
  TextStyle get displayCompact => _style(TypographyTokens.displaySmall);

  // ── Headings ───────────────────────────────────────────────────────────
  /// 26px w600 — page titles.
  TextStyle get heading => _style(TypographyTokens.headlineLarge);

  /// 20px w600 — prominent section titles, sheet titles.
  TextStyle get headingSmall => _style(TypographyTokens.headlineMedium);

  // ── Titles / body ──────────────────────────────────────────────────────
  /// 16px w500 — card titles, row heroes.
  TextStyle get title => _style(TypographyTokens.titleLarge);

  /// 14px w600 — compact row titles, list labels.
  TextStyle get titleSmall => _style(TypographyTokens.titleMedium);

  /// 16px w400 — long-form body copy.
  TextStyle get body => _style(TypographyTokens.bodyLarge);

  /// 14px w400 — default body copy.
  TextStyle get bodySmall => _style(TypographyTokens.bodyMedium);

  // ── Labels / captions ──────────────────────────────────────────────────
  /// 14px w600 +0.1 — buttons and emphasized labels.
  TextStyle get label => _style(TypographyTokens.labelLarge);

  /// 12px w600 +0.4 — chips, overlines, dense labels.
  TextStyle get labelSmall => _style(TypographyTokens.labelMedium);

  /// 12px w500 — metadata, timestamps, secondary captions. Pair with
  /// `content.muted` for the canonical caption read.
  TextStyle get caption => _style(TypographyTokens.numericCaption);

  /// 11px w600 +0.5 — micro status tags.
  TextStyle get micro => _style(TypographyTokens.labelSmall);

  /// 11px w500 — chart-internal annotations only.
  TextStyle get chartCaption => _style(TypographyTokens.chartCaption);

  // ── Numerics (tabular by construction) ─────────────────────────────────
  TextStyle get numericDisplay => _style(TypographyTokens.numericDisplay);
  TextStyle get numericTitle => _style(TypographyTokens.numericTitle);
  TextStyle get numericTitleStrong =>
      _style(TypographyTokens.numericTitleStrong);
  TextStyle get numericBody => _style(TypographyTokens.numericBody);
  TextStyle get numericBodyStrong => _style(TypographyTokens.numericBodyStrong);
  TextStyle get numericCaption => _style(TypographyTokens.numericCaption);
  TextStyle get numericCaptionStrong =>
      _style(TypographyTokens.numericCaptionStrong);
  TextStyle get numericMono => _style(TypographyTokens.numericMono);
}

/// Keep type sizes and tabular figures stable when switching presets.
TextStyle appVisualTextStyle(TextStyle style, AppVisualStyle visualStyle) =>
    visualStyle == AppVisualStyle.classic
    ? style
    : style.copyWith(
        fontFamily: style.fontFamily == TypographyTokens.fontFamilyDisplay
            ? TypographyTokens.fontFamilySans
            : style.fontFamily,
        letterSpacing: (style.fontSize ?? 0) >= 26 ? style.letterSpacing : 0,
        height: style.height == null ? null : style.height! * 0.96,
      );

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
