import 'package:flutter/material.dart';

/// Type scale.
///
/// On Web, [fontFamilySans] resolves to `AppCnSans`, our pyftsubset-built
/// subset of Noto Sans SC variable. The base subset is ~120 KB and loads
/// with the first paint; the extension subset (~1.7 MB) is lazy-loaded only
/// when a glyph outside the base set is rendered (free-text input, server
/// payload). On iOS / Android / Web-while-loading, [fontFamilyFallback]
/// hands rendering off to the platform CJK font so the user never sees
/// tofu while the woff2 is in flight or unavailable. See
/// `docs/design/13-web-fonts.md` for the pipeline.
///
/// `tabular` indicates lining tabular figures should be used (essential for
/// money columns).
class TypographyTokens {
  const TypographyTokens._();

  /// Font family used by every text style. Backed by the subset webfont on
  /// Web and falls through to [fontFamilyFallback] on iOS / Android.
  static const String fontFamilySans = 'AppCnSans';

  /// Resolved in order when [fontFamilySans] cannot render a glyph yet —
  /// covers offline / first-paint on Web and platforms where the bundled
  /// font isn't available. Mirrors the `<style>` font stack in
  /// `web/index.html`.
  static const List<String> fontFamilyFallback = <String>[
    'PingFang SC', // iOS / macOS
    'Hiragino Sans GB', // older macOS
    'Microsoft YaHei', // Windows
    'Source Han Sans SC', // Linux (Adobe / Google)
    'Noto Sans SC', // Linux generic fallback
    'sans-serif',
  ];

  static const String fontFamilyMono = 'monospace';

  // Lining tabular figures — keeps digits the same width across rows.
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
    FontFeature.liningFigures(),
  ];

  static TextStyle _t(
    double size, {
    double? height,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0,
    bool tabular = false,
  }) {
    return TextStyle(
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      fontFamily: fontFamilySans,
      fontFamilyFallback: fontFamilyFallback,
      fontFeatures: tabular ? tabularFigures : null,
    );
  }

  // Display — large numeric headlines (net worth, FIRE %).
  static final TextStyle displayLarge = _t(
    40,
    height: 1.1,
    weight: FontWeight.w700,
    letterSpacing: -0.5,
    tabular: true,
  );
  static final TextStyle displayMedium = _t(
    32,
    height: 1.15,
    weight: FontWeight.w700,
    letterSpacing: -0.25,
    tabular: true,
  );
  static final TextStyle displaySmall = _t(
    26,
    height: 1.2,
    weight: FontWeight.w600,
    tabular: true,
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

  // Numeric — money, percentages, charts axis labels.
  static final TextStyle numericDisplay = _t(
    32,
    height: 1.15,
    weight: FontWeight.w700,
    letterSpacing: -0.25,
    tabular: true,
  );
  static final TextStyle numericTitle = _t(
    20,
    height: 1.3,
    weight: FontWeight.w600,
    tabular: true,
  );
  static final TextStyle numericBody = _t(
    14,
    height: 1.4,
    weight: FontWeight.w500,
    tabular: true,
  );
  static final TextStyle numericCaption = _t(
    12,
    height: 1.3,
    weight: FontWeight.w500,
    tabular: true,
  );

  /// Material 3 [TextTheme] composed from the tokens above. Used by
  /// `AppTheme` so that `Theme.of(context).textTheme.titleMedium` resolves to
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
