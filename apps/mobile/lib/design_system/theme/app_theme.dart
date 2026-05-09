import 'package:flutter/material.dart';

import '../tokens/color_palette.dart';
import '../tokens/glass_tokens.dart';
import '../tokens/radius_tokens.dart';
import '../tokens/spacing_tokens.dart';
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
    bool compact = false,
  }) => _build(Brightness.light, marketColorMode, compact);

  static ThemeData dark({
    MarketColorMode marketColorMode = MarketColorMode.redUpGreenDown,
    bool compact = false,
  }) => _build(Brightness.dark, marketColorMode, compact);

  static ThemeData _build(
    Brightness brightness,
    MarketColorMode marketMode,
    bool compact,
  ) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    final semantic = isDark ? SemanticColors.dark() : SemanticColors.light();
    final elevations = isDark ? AppElevations.dark() : AppElevations.light();
    final glass = isDark ? GlassTokens.dark() : GlassTokens.light();
    final marketColors = MarketColors.fromMode(
      marketMode,
      brightness: brightness,
    );
    final textTheme = TypographyTokens.textTheme().apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    // Pointer hover and keyboard focus surfaces (FIR-106).
    //
    //  * Hover: a subtle primary tint at 4% alpha sits on top of any
    //    interactive surface a pointer enters. Material's default hover
    //    overlay is brand-neutral; tinting it primary makes mouse-driven
    //    surfaces feel actively clickable without adding visual noise.
    //  * Focus: a 1.5px brand-blue stroke wraps the focused element.
    //    Keyboard users get a deliberate ring instead of Material's
    //    default ghost-state highlight.
    final hoverOverlay = scheme.primary.withValues(alpha: 0.04);
    final focusOverlay = scheme.primary.withValues(alpha: 0.06);
    BorderSide? focusBorder(Set<WidgetState> states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: scheme.primary, width: 1.5);
      }
      return null;
    }

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: compact
          ? VisualDensity.compact
          : VisualDensity.adaptivePlatformDensity,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      // Global ripple removal — T11 item 1.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: hoverOverlay,
      focusColor: focusOverlay,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      dividerTheme: DividerThemeData(
        color: semantic.divider,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        // Glass-aware default: GlassAppBar paints its own backdrop, so
        // any plain Material AppBar still in the tree should sit on the
        // canvas surface and tint nothing on scroll.
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        // Cards get their depth from a 1-px hairline + a subtle surface
        // tint, not from a Material drop shadow. In dark mode we drop
        // shadows entirely; light mode keeps the hairline as a quiet
        // separator (Sheet/Modal still use AppElevations.level1 directly
        // when they need extra lift).
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.brLg,
          side: BorderSide(
            color: isDark
                ? const Color(0x0FFFFFFF) // rgba(255,255,255,0.06)
                : const Color(0x0F000000), // rgba(0,0,0,0.06)
            width: 1,
          ),
        ),
        color: isDark ? const Color(0xFF1C1C1E) : scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: Radii.brSm),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.s16,
            vertical: Spacing.s12,
          ),
          textStyle: textTheme.labelLarge,
        ).copyWith(
          side: WidgetStateProperty.resolveWith(focusBorder),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: Radii.brSm),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.s16,
            vertical: Spacing.s12,
          ),
          textStyle: textTheme.labelLarge,
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: scheme.primary, width: 1.5);
            }
            // Outlined buttons keep their standard 1px outline at rest.
            return BorderSide(color: scheme.outline);
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: Radii.brSm),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.s12,
            vertical: Spacing.s8,
          ),
          textStyle: textTheme.labelLarge,
        ).copyWith(
          side: WidgetStateProperty.resolveWith(focusBorder),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: Radii.brSm),
        side: BorderSide(color: semantic.divider),
        labelStyle: textTheme.labelMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        // T11 item 4: Stripe-style bottom-rule underline.
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: semantic.divider),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: semantic.divider),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: ColorPalette.green500, width: 1.5),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: ColorPalette.red500, width: 1),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: ColorPalette.red500, width: 1.5),
        ),
        contentPadding: const EdgeInsets.only(
          top: Spacing.s8,
          bottom: Spacing.s8,
        ),
        isDense: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        // T11 item 2: transparent indicator — custom lines drawn by
        // GlassNavigationBar instead of M3 capsule.
        indicatorColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            decoration: TextDecoration.none,
          );
        }),
      ),
      // T11 item 8: surfaceTintColor zeroed on all elevated surfaces.
      dialogTheme: const DialogThemeData(
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        selectedLabelTextStyle: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.none,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.none,
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: ListTileThemeData(
        // Pointer hover on rows reads as a 4% primary tint; pressed reads
        // as 8%. Matches the FIR-106 "interactive surface" overlay rules
        // so list rows feel responsive on web/desktop without Material's
        // brand-neutral grey wash.
        tileColor: Colors.transparent,
        selectedTileColor: scheme.primary.withValues(alpha: 0.10),
        selectedColor: scheme.primary,
      ),
      extensions: <ThemeExtension<dynamic>>[
        semantic,
        marketColors,
        elevations,
        glass,
      ],
    );
  }
}
