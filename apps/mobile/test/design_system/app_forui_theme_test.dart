import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  test('buildAppForuiTheme applies brand colors in light and dark modes', () {
    for (final brightness in Brightness.values) {
      final isDark = brightness == Brightness.dark;
      for (final touch in <bool>[false, true]) {
        final theme = buildAppForuiTheme(brightness: brightness, touch: touch);

        expect(
          theme.buttonStyles.primary.md.contentStyle.constraints.minHeight,
          touch ? 44 : 36,
        );
        expect(theme.colors.primary, AccentColors.primary(brightness));
        expect(
          theme.colors.primaryForeground,
          AccentColors.onPrimary(brightness),
        );
        expect(
          theme.colors.background,
          isDark ? ColorPalette.navy950 : ColorPalette.surfaceBackground,
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
          isDark ? ColorPalette.navyGlass : ColorPalette.neutral0,
        );
        expect(
          theme.colors.border,
          isDark ? ColorPalette.navy800 : ColorPalette.surfaceHairline,
        );
        expect(
          theme.colors.muted,
          isDark ? ColorPalette.navyGlass : ColorPalette.surfaceOverlay,
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
    testWidgets(
      '${touch ? 'touch' : 'desktop'} theme preserves Forui button sizes',
      (tester) async {
        const mediumKey = ValueKey('medium-button');
        const largeKey = ValueKey('large-button');

        await tester.pumpWidget(
          MaterialApp(
            home: FTheme(
              data: buildAppForuiTheme(
                brightness: Brightness.dark,
                touch: touch,
              ),
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

        expect(tester.getSize(find.byKey(mediumKey)).height, touch ? 44 : 36);
        expect(tester.getSize(find.byKey(largeKey)).height, touch ? 48 : 40);
      },
    );
  }
}
