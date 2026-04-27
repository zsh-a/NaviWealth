import 'package:flutter/material.dart';

import '../tokens/color_palette.dart';
import '../tokens/radius_tokens.dart';
import '../tokens/typography_tokens.dart';
import 'app_elevations.dart';
import 'market_color_mode.dart';
import 'market_colors.dart';
import 'semantic_colors.dart';

/// Builds the root [ThemeData] for both light and dark modes.
///
/// All visual tokens live under `lib/design_system/`; this file is just the
/// composition point that wires them onto Material 3.
class AppTheme {
  const AppTheme._();

  static const Color _seed = ColorPalette.brand500;

  static ThemeData light({
    MarketColorMode marketColorMode = MarketColorMode.redUpGreenDown,
  }) => _build(Brightness.light, marketColorMode);

  static ThemeData dark({
    MarketColorMode marketColorMode = MarketColorMode.redUpGreenDown,
  }) => _build(Brightness.dark, marketColorMode);

  static ThemeData _build(Brightness brightness, MarketColorMode marketMode) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final semantic = isDark ? SemanticColors.dark() : SemanticColors.light();
    final elevations = isDark ? AppElevations.dark() : AppElevations.light();
    final marketColors = MarketColors.fromMode(
      marketMode,
      brightness: brightness,
    );
    final textTheme = TypographyTokens.textTheme().apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      dividerTheme: DividerThemeData(
        color: semantic.divider,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: Radii.brLg),
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: Radii.brSm),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: Radii.brSm),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: Radii.brSm),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: Radii.brSm),
        side: BorderSide(color: semantic.divider),
        labelStyle: textTheme.labelMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(borderRadius: Radii.brSm),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.brSm,
          borderSide: BorderSide(color: semantic.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.brSm,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      extensions: <ThemeExtension<dynamic>>[semantic, marketColors, elevations],
    );
  }
}
