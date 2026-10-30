import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/design_system/theme/app_button_styles.dart'
    show buildAppButtonStyle;

void main() {
  test('all touch button variants retain a 48dp target', () {
    final theme = buildAppForuiTheme(brightness: Brightness.light, touch: true);
    for (final variant in [
      FButtonVariant.primary,
      FButtonVariant.secondary,
      FButtonVariant.outline,
      FButtonVariant.ghost,
      FButtonVariant.destructive,
    ]) {
      for (final size in [
        FButtonSizeVariant.xs,
        FButtonSizeVariant.sm,
        FButtonSizeVariant.md,
        FButtonSizeVariant.lg,
      ]) {
        final style = theme.buttonStyles.resolve({variant}).resolve({size});
        expect(
          style.contentStyle.constraints.minHeight,
          greaterThanOrEqualTo(48),
        );
        expect(
          style.iconContentStyle.constraints.minWidth,
          greaterThanOrEqualTo(48),
        );
      }
    }
  });

  test('active button labels retain AA contrast across themes and accents', () {
    for (final brightness in Brightness.values) {
      for (final visual in AppVisualStyle.values) {
        for (final highContrast in [false, true]) {
          for (final seed in AppAccentSeed.values) {
            final theme = buildAppForuiTheme(
              brightness: brightness,
              touch: true,
              highContrast: highContrast,
              accentSeed: seed,
              visualStyle: visual,
            );
            for (final variant in [
              FButtonVariant.primary,
              FButtonVariant.secondary,
              FButtonVariant.outline,
              FButtonVariant.ghost,
              FButtonVariant.destructive,
            ]) {
              for (final emphasis in AppButtonEmphasis.values) {
                final style = buildAppButtonStyle(
                  colors: theme.colors,
                  typography: theme.typography,
                  style: theme.style,
                  touch: true,
                  highContrast: highContrast,
                  visual: visual.spec,
                  variant: variant,
                  size: FButtonSizeVariant.md,
                  emphasis: emphasis,
                );
                for (final states in <Set<FTappableVariant>>[
                  {},
                  {FTappableVariant.hovered},
                  {FTappableVariant.pressed},
                  {FTappableVariant.selected},
                ]) {
                  final foreground = style.contentStyle.textStyle
                      .resolve(states)
                      .color!;
                  final background = Color.alphaBlend(
                    style.decoration.resolve(states).color ??
                        const Color(0x00000000),
                    theme.colors.card,
                  );
                  final a = foreground.computeLuminance();
                  final b = background.computeLuminance();
                  final ratio = a > b
                      ? (a + .05) / (b + .05)
                      : (b + .05) / (a + .05);
                  expect(
                    ratio,
                    greaterThanOrEqualTo(4.5),
                    reason:
                        '$brightness/$visual/$seed/highContrast=$highContrast/$variant/$emphasis/$states',
                  );
                }
              }
            }
          }
        }
      }
    }
  });

  test('buildAppForuiTheme applies brand colors in light and dark modes', () {
    for (final brightness in Brightness.values) {
      final isDark = brightness == Brightness.dark;
      for (final touch in <bool>[false, true]) {
        final theme = buildAppForuiTheme(brightness: brightness, touch: touch);

        expect(
          theme.buttonStyles.primary.md.contentStyle.constraints.minHeight,
          touch ? 48 : 36,
        );
        expect(theme.colors.primary, AccentColors.primary(brightness));
        expect(
          theme.colors.primaryForeground,
          AccentColors.onPrimary(brightness),
        );
        expect(
          theme.colors.background,
          isDark
              ? ColorPalette.surfaceBackgroundDark
              : ColorPalette.surfaceBackground,
        );
        expect(
          theme.colors.foreground,
          isDark ? ColorPalette.navy50 : ColorPalette.navy900,
        );
        expect(
          theme.colors.mutedForeground,
          isDark ? ColorPalette.navy300 : ColorPalette.navy500,
        );
        expect(
          theme.colors.card,
          isDark ? ColorPalette.surfaceDark : ColorPalette.neutral0,
        );
        expect(
          theme.colors.border,
          isDark
              ? ColorPalette.surfaceHairlineDark
              : ColorPalette.surfaceHairline,
        );
        expect(
          theme.colors.muted,
          isDark
              ? Color.alphaBlend(
                  ColorPalette.navy50.withValues(alpha: AppOpacity.whisper),
                  ColorPalette.surfaceDark,
                )
              : ColorPalette.surfaceOverlay,
        );
        for (final typeface in <FTypeface>[
          theme.typography.display,
          theme.typography.body,
        ]) {
          expect(typeface.fontFamily, TypographyTokens.fontFamilySans);
          expect(
            typeface.fontFamilyFallback,
            TypographyTokens.fontFamilyFallback,
          );
          expect(typeface.sm.fontFamily, TypographyTokens.fontFamilySans);
          expect(
            typeface.sm.fontFamilyFallback,
            TypographyTokens.fontFamilyFallback,
          );
        }
      }
    }
  });

  for (final touch in <bool>[false, true]) {
    testWidgets('${touch ? 'touch' : 'desktop'} buttons use app target sizes', (
      tester,
    ) async {
      const mediumKey = ValueKey('medium-button');
      const largeKey = ValueKey('large-button');

      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: buildAppForuiTheme(brightness: Brightness.dark, touch: touch),
            child: Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FButton(
                      key: mediumKey,
                      size: .md,
                      mainAxisSize: MainAxisSize.min,
                      onPress: () {},
                      child: const Text('Medium'),
                    ),
                    FButton(
                      key: largeKey,
                      size: .lg,
                      mainAxisSize: MainAxisSize.min,
                      onPress: () {},
                      child: const Text('Large'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byKey(mediumKey)).height, touch ? 48 : 36);
      expect(tester.getSize(find.byKey(largeKey)).height, touch ? 48 : 40);
    });
  }
}
