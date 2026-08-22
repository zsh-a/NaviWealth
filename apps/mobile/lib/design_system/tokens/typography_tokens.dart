import 'package:flutter/material.dart';

/// Type scale.
///
/// Swapped the primary fontFamily from `AppCnSans` (the Noto Sans
/// SC subset) to **Inter** for Latin / numeric / English copy. Inter
/// brings the things a fintech UI needs out of the box:
///
///   * tabular figures + lining figures (no horizontal jitter when a money
///     ticker animates),
///   * a tight x-height, and
///   * a wide weight range (400 / 500 / 600 / 700) so we can hit the
///     "extreme contrast" the design vision asks for.
///
/// **Outfit** is reserved for the largest hero number ([displayLarge], aka
/// "Display 2XL"). Its taller proportions give the dashboard's net-worth
/// figure the marquee feel of Copilot Money / Stripe Dashboard without
/// requiring a custom variable axis.
///
/// CJK still goes through `AppCnSans` and the platform CJK fonts via
/// [fontFamilyFallback] — when a glyph isn't present in the Latin subset,
/// the renderer walks the fallback chain. That keeps Chinese text from
/// dropping to tofu while the Inter / Outfit subsets stay tiny (~200 KB
/// total).
///
/// Tabular figures are now applied **globally** via [tabularFigures] on
/// every text style so a money column never has to opt in by hand. Inter
/// supports tnum + lnum as native OpenType features; non-money copy is
/// unaffected because the substitution only fires for digit glyphs.
class TypographyTokens {
  const TypographyTokens._();

  /// Primary fontFamily. Maps to the self-hosted Inter Latin subset
  /// registered in pubspec.yaml.
  static const String fontFamilySans = 'Inter';

  /// Display family — only used by [displayLarge] (Display 2XL). Outfit's
  /// tall x-height and condensed digits give the hero net-worth figure
  /// the marquee read the design vision asks for.
  static const String fontFamilyDisplay = 'Outfit';

  /// Resolved in order when [fontFamilySans] cannot render a glyph yet —
  /// covers CJK and the long tail of system code points. The fallback
  /// stack mirrors the `<style>` font stack in `web/index.html` so native
  /// and web behave identically.
  static const List<String> fontFamilyFallback = <String>[
    'AppCnSans', // bundled CJK subset on web; absent on native (no-op)
    'PingFang SC', // iOS / macOS
    'Hiragino Sans GB', // older macOS
    'Microsoft YaHei', // Windows
    'Source Han Sans SC', // Linux (Adobe / Google)
    'Noto Sans SC', // Linux generic fallback
    'sans-serif',
  ];

  static const String fontFamilyMono = 'monospace';

  /// Lining tabular figures — applied to every text style
  /// so digits stay aligned across rows even in non-numeric contexts (a
  /// chart legend, a settings row with a count badge, …) without each
  /// site having to opt in.
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
    FontFeature.liningFigures(),
  ];

  static TextStyle _t(
    double size, {
    double? height,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0,
    String fontFamily = fontFamilySans,
  }) {
    return TextStyle(
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      fontFeatures: tabularFigures,
    );
  }

  // Display — large numeric headlines (net worth, FIRE %).
  // displayLarge ("Display 2XL") is the only style that uses Outfit; it's
  // reserved for the dashboard hero number. Anything below stays on Inter.
  static final TextStyle displayLarge = _t(
    40,
    height: 1.1,
    weight: FontWeight.w700,
    letterSpacing: -0.5,
    fontFamily: fontFamilyDisplay,
  );
  static final TextStyle displayMedium = _t(
    32,
    height: 1.15,
    weight: FontWeight.w700,
    letterSpacing: -0.25,
  );
  static final TextStyle displaySmall = _t(
    26,
    height: 1.2,
    weight: FontWeight.w600,
  );

  // Headline — section titles.
  static final TextStyle headlineLarge = _t(
    24,
    height: 1.25,
    weight: FontWeight.w600,
  );
  static final TextStyle headlineMedium = _t(
    20,
    height: 1.3,
    weight: FontWeight.w600,
  );
  static final TextStyle headlineSmall = _t(
    18,
    height: 1.35,
    weight: FontWeight.w600,
  );

  // Title — card titles, navigation labels.
  static final TextStyle titleLarge = _t(
    16,
    height: 1.4,
    weight: FontWeight.w600,
  );
  static final TextStyle titleMedium = _t(
    14,
    height: 1.4,
    weight: FontWeight.w600,
  );
  static final TextStyle titleSmall = _t(
    13,
    height: 1.4,
    weight: FontWeight.w600,
  );

  // Body.
  static final TextStyle bodyLarge = _t(16, height: 1.5);
  static final TextStyle bodyMedium = _t(14, height: 1.5);
  static final TextStyle bodySmall = _t(13, height: 1.45);

  // Label — buttons, chips, captions, metadata.
  static final TextStyle labelLarge = _t(
    14,
    height: 1.3,
    weight: FontWeight.w600,
    letterSpacing: 0.1,
  );
  static final TextStyle labelMedium = _t(
    12,
    height: 1.3,
    weight: FontWeight.w600,
    letterSpacing: 0.4,
  );
  static final TextStyle labelSmall = _t(
    11,
    height: 1.3,
    weight: FontWeight.w600,
    letterSpacing: 0.5,
  );
  static final TextStyle labelSmallMedium = _t(
    11,
    height: 1.3,
    weight: FontWeight.w500,
    letterSpacing: 0.5,
  );
  // Numeric — money, percentages, charts axis labels. These
  // are no longer the only carriers of `tabularFigures`; they remain a
  // semantic alias so call sites that explicitly want "this is a number"
  // can keep reading.
  //
  // Sizes are NOT re-authored here: each alias reuses the matching main-scale
  // style and only stacks the numeric-specific deltas (weight, letterSpacing,
  // height) on top, so a given size has exactly one source of truth.
  //
  // Secondary marquee (Wealth sub-metrics, plan secondary). Page-level
  // hero numbers should use [displayLarge] (Outfit 40) instead.
  static final TextStyle numericDisplay = displayMedium.copyWith(
    height: 1.12,
    letterSpacing: -0.4,
  );
  static final TextStyle numericTitle = headlineMedium;
  static final TextStyle numericTitleStrong = headlineMedium.copyWith(
    fontWeight: FontWeight.w700,
  );
  static final TextStyle numericBody = titleMedium.copyWith(
    fontWeight: FontWeight.w500,
  );
  static final TextStyle numericBodyStrong = titleMedium.copyWith(
    fontWeight: FontWeight.w700,
  );
  static final TextStyle numericCaption = labelMedium.copyWith(
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );
  static final TextStyle numericCaptionStrong = labelMedium.copyWith(
    letterSpacing: 0,
  );

  /// Chart-internal caption (axis annotations, slice labels, crosshair
  /// readouts). 11px — aligned with [labelSmall]; chart code must consume
  /// this token instead of a raw `fontSize` literal.
  static final TextStyle chartCaption = _t(
    11,
    height: 1.3,
    weight: FontWeight.w500,
  );

  /// §5.10.4 — true monospace numeral style for surfaces that explicitly
  /// want a "data-grid" read (structured answer tables in the command
  /// palette result pane, ingest preview rows, etc.). MoneyText keeps its
  /// proportional Inter + tabular-figures default; reach for
  /// this token only when a surface needs every character to occupy the
  /// same width.
  static final TextStyle numericMono = numericBody.copyWith(
    fontFamily: fontFamilyMono,
  );

  /// Relative emphasis — bumps any base style to semibold (w600) while
  /// keeping the base size/height/colour. Use for content-driven emphasis
  /// (markdown `strong`, table header cells) where the base style varies
  /// and a fixed-size preset cannot fit.
  static TextStyle semiboldEmphasis(TextStyle base) =>
      base.copyWith(fontWeight: FontWeight.w600);

  /// Section header title — neutral by default so accent remains reserved for
  /// actions, active state, and key metrics.
  static TextStyle sectionHeaderTitle(Color color) =>
      titleLarge.copyWith(color: color);

  /// Section header subtitle — muted secondary text.
  static TextStyle sectionHeaderSubtitle(Color onSurfaceVariant) =>
      bodyMedium.copyWith(color: onSurfaceVariant);

  /// Material 3 [TextTheme] composed from the tokens above. Used by
  /// `AppTheme` so that `context.theme.typography.body.md` resolves to
  /// the design-system value.
  static TextTheme textTheme() {
    return TextTheme(
      displayLarge: displayLarge,
      displayMedium: displayMedium,
      displaySmall: displaySmall,
      headlineLarge: headlineLarge,
      headlineMedium: headlineMedium,
      headlineSmall: headlineSmall,
      titleLarge: titleLarge,
      titleMedium: titleMedium,
      titleSmall: titleSmall,
      bodyLarge: bodyLarge,
      bodyMedium: bodyMedium,
      bodySmall: bodySmall,
      labelLarge: labelLarge,
      labelMedium: labelMedium,
      labelSmall: labelSmall,
    );
  }
}
