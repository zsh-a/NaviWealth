import 'package:flutter/widgets.dart';

import '../tokens/color_palette.dart';
import 'accent_colors.dart';
import 'app_theme_data.dart';
import 'market_color_mode.dart';
import 'market_colors.dart';
import 'semantic_colors.dart';

/// Density axis, replacing Forui's implicit touch/desktop fork with an
/// explicit resolver input. Consumed by the semantic type scale (phase P5);
/// carried from day one so the input shape stays stable.
enum AppDensity { touch, desktop }

/// Everything the theme depends on, gathered once at the app root.
///
/// Adding a preference axis (OLED surfaces, accent seed, …) means extending
/// this class and `resolveAppTheme` — never a component.
@immutable
class ThemeInputs {
  const ThemeInputs({
    required this.brightness,
    required this.marketMode,
    this.density = AppDensity.touch,
  });

  final Brightness brightness;
  final MarketColorMode marketMode;
  final AppDensity density;

  @override
  bool operator ==(Object other) =>
      other is ThemeInputs &&
      other.brightness == brightness &&
      other.marketMode == marketMode &&
      other.density == density;

  @override
  int get hashCode => Object.hash(brightness, marketMode, density);
}

/// Pure resolver: [ThemeInputs] → [AppThemeData].
///
/// No BuildContext, no side effects — contrast invariants are asserted over
/// every input combination in `theme_contrast_test.dart`.
///
/// Phase P1 note: values are sourced from the legacy [SemanticColors] /
/// [MarketColors] / [AccentColors] tables so adopting `context.appTheme`
/// changes no pixels. Those tables fold into this file in phase P5.
AppThemeData resolveAppTheme(ThemeInputs inputs) {
  final isDark = inputs.brightness == Brightness.dark;
  final semantic = isDark ? SemanticColors.dark : SemanticColors.light;
  final legacyMarket = MarketColors.fromMode(
    inputs.marketMode,
    brightness: inputs.brightness,
  );

  final surfaces = isDark
      ? const AppSurfaces(
          canvas: ColorPalette.navy950,
          card: ColorPalette.navyGlass,
          raised: ColorPalette.navyRaised,
          hero: ColorPalette.navyHero,
          border: ColorPalette.navy800,
          scrim: ColorPalette.scrimDark,
        )
      : const AppSurfaces(
          canvas: ColorPalette.surfaceBackground,
          card: ColorPalette.surface,
          raised: ColorPalette.surfaceRaised,
          hero: ColorPalette.surface,
          border: ColorPalette.surfaceHairline,
          scrim: ColorPalette.scrimLight,
        );

  final content = isDark
      ? const AppContent(
          strong: ColorPalette.neutral0,
          body: ColorPalette.navy50,
          muted: ColorPalette.navy300,
          faint: ColorPalette.navy400,
        )
      : const AppContent(
          strong: ColorPalette.neutral1000,
          body: ColorPalette.navy900,
          muted: ColorPalette.navy500,
          faint: ColorPalette.neutral400,
        );

  final accent = ColorRole(
    fg: AccentColors.primary(inputs.brightness),
    container: AccentColors.tint(inputs.brightness),
    onContainer: isDark ? ColorPalette.cyanBrand100 : ColorPalette.cyanBrand800,
    onFg: AccentColors.onPrimary(inputs.brightness),
  );

  final status = AppStatus(
    success: ColorRole(
      fg: semantic.success,
      container: semantic.successContainer,
      onContainer: semantic.onSuccessContainer,
      onFg: semantic.onSuccess,
    ),
    warning: ColorRole(
      fg: semantic.warning,
      container: semantic.warningContainer,
      onContainer: semantic.onWarningContainer,
      onFg: semantic.onWarning,
    ),
    danger: ColorRole(
      fg: semantic.danger,
      container: semantic.dangerContainer,
      onContainer: semantic.onDangerContainer,
      onFg: semantic.onDanger,
    ),
    info: ColorRole(
      fg: semantic.info,
      container: semantic.infoContainer,
      onContainer: semantic.onInfoContainer,
      onFg: semantic.onInfo,
    ),
  );

  final market = AppMarket(
    mode: inputs.marketMode,
    up: ColorRole(
      fg: legacyMarket.up,
      container: legacyMarket.upContainer,
      onContainer: legacyMarket.onUpContainer,
      onFg: legacyMarket.onUp,
    ),
    down: ColorRole(
      fg: legacyMarket.down,
      container: legacyMarket.downContainer,
      onContainer: legacyMarket.onDownContainer,
      onFg: legacyMarket.onDown,
    ),
    flat: ColorRole(
      fg: legacyMarket.flat,
      container: surfaces.raised,
      onContainer: legacyMarket.onFlat,
      onFg: legacyMarket.onFlat,
    ),
    upMuted: legacyMarket.upMuted,
    downMuted: legacyMarket.downMuted,
    profitGlow: legacyMarket.profitGlow,
  );

  return AppThemeData(
    brightness: inputs.brightness,
    surfaces: surfaces,
    content: content,
    accent: accent,
    status: status,
    market: market,
  );
}
