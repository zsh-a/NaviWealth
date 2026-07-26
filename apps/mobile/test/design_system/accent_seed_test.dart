import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppAccentSeed resolution', () {
    test('cyan (default) stays pixel-identical to the legacy brand accent', () {
      final theme = resolveAppTheme(
        const ThemeInputs(
          brightness: Brightness.light,
          marketMode: MarketColorMode.redUpGreenDown,
        ),
      );
      expect(theme.accent.fg, ColorPalette.cyanBrand800);
      expect(theme.accent.container, ColorPalette.surfaceOverlay);
    });

    test('each seed swaps the accent role in both brightnesses', () {
      for (final seed in AppAccentSeed.values) {
        for (final b in [Brightness.light, Brightness.dark]) {
          final theme = resolveAppTheme(
            ThemeInputs(
              brightness: b,
              marketMode: MarketColorMode.redUpGreenDown,
              accentSeed: seed,
            ),
          );
          final slots = AccentSeedSlots.of(seed);
          expect(
            theme.accent.fg,
            b == Brightness.dark ? slots.darkPrimary : slots.lightPrimary,
            reason: '${seed.name}/${b.name} fg',
          );
        }
      }
    });

    test('seed changes accent only — status and market stay put', () {
      ThemeInputs inputs(AppAccentSeed seed) => ThemeInputs(
        brightness: Brightness.dark,
        marketMode: MarketColorMode.redUpGreenDown,
        accentSeed: seed,
      );
      final cyan = resolveAppTheme(inputs(AppAccentSeed.cyan));
      final violet = resolveAppTheme(inputs(AppAccentSeed.violet));
      expect(violet.accent.fg, isNot(cyan.accent.fg));
      expect(violet.status.success.fg, cyan.status.success.fg);
      expect(violet.market.up.fg, cyan.market.up.fg);
      expect(violet.surfaces.card, cyan.surfaces.card);
    });

    test('forui and Material primaries follow the seed', () {
      final fTheme = buildAppForuiTheme(
        brightness: Brightness.dark,
        touch: true,
        accentSeed: AppAccentSeed.indigo,
      );
      expect(fTheme.colors.primary, ColorPalette.indigo400);

      final material = AppTheme.light(accentSeed: AppAccentSeed.violet);
      expect(material.colorScheme.primary, ColorPalette.violet700);
    });
  });

  group('AccentSeedController', () {
    test('persists and restores the preference', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AccentSeedController(prefs);
      expect(controller.state, AppAccentSeed.cyan);

      await controller.set(AppAccentSeed.indigo);
      expect(prefs.getString('naviwealth.theme.accent_seed'), 'indigo');
      expect(AccentSeedController(prefs).state, AppAccentSeed.indigo);
    });

    test('unknown persisted keys fall back to cyan', () {
      expect(AppAccentSeed.fromKey('nope'), AppAccentSeed.cyan);
      expect(AppAccentSeed.fromKey(null), AppAccentSeed.cyan);
    });
  });
}
