import 'package:flutter/widgets.dart';

import '../tokens/dimens_tokens.dart';
import 'accent_colors.dart';
import 'accent_seed.dart';
import 'app_categorical.dart';
import 'app_theme_data.dart';
import 'app_type_scale.dart';
import 'app_visual_style.dart';
import 'component_specs.dart';
import 'market_color_mode.dart';
import 'market_colors.dart';
import 'semantic_colors.dart';
import 'surface_ladder.dart';

/// Density axis, replacing Forui's implicit touch/desktop fork with an
/// explicit resolver input. Consumed by the semantic type scale (phase P5);
/// carried from day one so the input shape stays stable.
enum AppDensity { touch, desktop }

/// Everything the theme depends on, gathered once at the app root.
///
/// Adding a preference axis (visual style, accent seed, …) means extending
/// this class and `resolveAppTheme` — never a component.
@immutable
class ThemeInputs {
  const ThemeInputs({
    required this.brightness,
    required this.marketMode,
    this.highContrast = false,
    this.accentSeed = AppAccentSeed.cyan,
    this.density = AppDensity.touch,
    this.visualStyle = AppVisualStyle.classic,
    this.materialStyle = AppMaterialStyle.solid,
  });

  final Brightness brightness;
  final MarketColorMode marketMode;

  /// Platform accessibility state, never persisted as an appearance preference.
  final bool highContrast;
  final AppAccentSeed accentSeed;
  final AppDensity density;
  final AppVisualStyle visualStyle;
  final AppMaterialStyle materialStyle;

  @override
  bool operator ==(Object other) =>
      other is ThemeInputs &&
      other.brightness == brightness &&
      other.marketMode == marketMode &&
      other.highContrast == highContrast &&
      other.accentSeed == accentSeed &&
      other.density == density &&
      other.visualStyle == visualStyle &&
      other.materialStyle == materialStyle;

  @override
  int get hashCode => Object.hash(
    brightness,
    marketMode,
    highContrast,
    accentSeed,
    density,
    visualStyle,
    materialStyle,
  );
}

/// Pure resolver: [ThemeInputs] → [AppThemeData].
///
/// No BuildContext, no side effects — contrast invariants are asserted over
/// every input combination in `theme_contrast_test.dart`.
///
/// Phase P1 note: values are sourced from the legacy [SemanticColors] /
/// [MarketColors] / [AccentColors] tables so adopting `context.appTheme`
/// changes no pixels. Those tables fold into this file in phase P5.
/// Hue-preserving contrast boost for the platform's high-contrast preference:
/// foregrounds: darkens on light surfaces, lightens on dark ones. Values are
/// verified by theme_contrast_test.dart's raised per-style thresholds.
Color _boostFg(Color c, {required bool isDark}) {
  final hsl = HSLColor.fromColor(c);
  final l = hsl.lightness;
  return hsl
      .withLightness((isDark ? l * 1.25 + 0.06 : l * 0.72).clamp(0.0, 1.0))
      .toColor();
}

ColorRole _boostRoleFg(ColorRole role, {required bool isDark}) => ColorRole(
  fg: _boostFg(role.fg, isDark: isDark),
  container: role.container,
  onContainer: role.onContainer,
  onFg: role.onFg,
);

AppThemeData resolveAppTheme(ThemeInputs inputs) {
  final isDark = inputs.brightness == Brightness.dark;
  final semantic = isDark ? SemanticColors.dark : SemanticColors.light;
  final legacyMarket = MarketColors.fromMode(
    inputs.marketMode,
    brightness: inputs.brightness,
  );

  final highContrast = inputs.highContrast;

  final solid = inputs.materialStyle == AppMaterialStyle.solid;
  final glass = highContrast
      ? const GlassSpec(
          chrome: GlassMaterialSpec(
            blurSigma: AppBlur.chrome,
            fillOpacity: AppOpacity.opaque,
            borderOpacity: AppOpacity.emphasis,
            liveBlur: false,
          ),
          sticky: GlassMaterialSpec(
            blurSigma: AppBlur.chrome,
            fillOpacity: AppOpacity.opaque,
            borderOpacity: AppOpacity.emphasis,
            liveBlur: false,
          ),
          sheet: GlassMaterialSpec(
            blurSigma: AppBlur.sheet,
            fillOpacity: AppOpacity.opaque,
            borderOpacity: AppOpacity.emphasis,
            liveBlur: false,
          ),
          overlay: GlassMaterialSpec(
            blurSigma: AppBlur.sheet,
            fillOpacity: AppOpacity.opaque,
            borderOpacity: AppOpacity.emphasis,
            liveBlur: false,
          ),
        )
      : GlassSpec(
          chrome: GlassMaterialSpec(
            blurSigma: AppBlur.chrome,
            fillOpacity: solid ? AppOpacity.opaque : AppOpacity.overlay,
            borderOpacity: AppOpacity.strong,
            liveBlur: !solid,
          ),
          sticky: GlassMaterialSpec(
            blurSigma: AppBlur.chrome,
            fillOpacity: solid ? AppOpacity.opaque : AppOpacity.solidSurface,
            borderOpacity: AppOpacity.medium,
            liveBlur: !solid,
          ),
          sheet: GlassMaterialSpec(
            blurSigma: AppBlur.sheet,
            fillOpacity: solid ? AppOpacity.opaque : AppOpacity.overlay,
            borderOpacity: AppOpacity.medium,
            liveBlur: !solid,
          ),
          overlay: GlassMaterialSpec(
            blurSigma: AppBlur.sheet,
            fillOpacity: solid ? AppOpacity.opaque : AppOpacity.solidSurface,
            borderOpacity: AppOpacity.medium,
            liveBlur: !solid,
          ),
        );

  // Surface/content values come from the shared ladder in surface_ladder.dart
  // so Material and Forui themes resolve the identical ramp.
  final ladder = resolveSurfaceLadder(
    brightness: inputs.brightness,
    highContrast: highContrast,
    visualStyle: inputs.visualStyle,
  );
  final surfaces = AppSurfaces(
    canvas: ladder.canvas,
    card: ladder.card,
    raised: ladder.raised,
    hero: ladder.hero,
    border: ladder.border,
    scrim: ladder.scrim,
  );
  final content = AppContent(
    strong: ladder.contentStrong,
    body: ladder.contentBody,
    muted: ladder.contentMuted,
    faint: ladder.contentFaint,
  );

  final accent = ColorRole(
    fg: AccentColors.primary(inputs.brightness, seed: inputs.accentSeed),
    container: AccentColors.tint(inputs.brightness, seed: inputs.accentSeed),
    onContainer: AccentColors.onTint(
      inputs.brightness,
      seed: inputs.accentSeed,
    ),
    onFg: AccentColors.onPrimary(inputs.brightness),
  );

  ColorRole role(ColorRole r) =>
      highContrast ? _boostRoleFg(r, isDark: isDark) : r;

  final status = AppStatus(
    success: role(
      ColorRole(
        fg: semantic.success,
        container: semantic.successContainer,
        onContainer: semantic.onSuccessContainer,
        onFg: semantic.onSuccess,
      ),
    ),
    warning: role(
      ColorRole(
        fg: semantic.warning,
        container: semantic.warningContainer,
        onContainer: semantic.onWarningContainer,
        onFg: semantic.onWarning,
      ),
    ),
    danger: role(
      ColorRole(
        fg: semantic.danger,
        container: semantic.dangerContainer,
        onContainer: semantic.onDangerContainer,
        onFg: semantic.onDanger,
      ),
    ),
    info: role(
      ColorRole(
        fg: semantic.info,
        container: semantic.infoContainer,
        onContainer: semantic.onInfoContainer,
        onFg: semantic.onInfo,
      ),
    ),
  );

  final market = AppMarket(
    mode: inputs.marketMode,
    up: role(
      ColorRole(
        fg: legacyMarket.up,
        container: legacyMarket.upContainer,
        onContainer: legacyMarket.onUpContainer,
        onFg: legacyMarket.onUp,
      ),
    ),
    down: role(
      ColorRole(
        fg: legacyMarket.down,
        container: legacyMarket.downContainer,
        onContainer: legacyMarket.onDownContainer,
        onFg: legacyMarket.onDown,
      ),
    ),
    flat: role(
      ColorRole(
        fg: legacyMarket.flat,
        container: surfaces.raised,
        onContainer: legacyMarket.onFlat,
        onFg: legacyMarket.onFlat,
      ),
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
    type: AppTypeScale.resolve(inputs.density, visualStyle: inputs.visualStyle),
    categorical: AppCategorical(
      brightness: inputs.brightness,
      cardSurface: surfaces.card,
    ),
    glass: glass,
    visual: inputs.visualStyle.spec,
    card: inputs.visualStyle == AppVisualStyle.refined
        ? kRefinedCardSpec
        : kAppCardSpec,
  );
}
