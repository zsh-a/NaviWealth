import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('MarketColorModeController persists + reloads', () async {
    SharedPreferences.setMockInitialValues({
      'naviwealth.theme.market_color_mode':
          MarketColorMode.colorblind.persistedKey,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(container.read(marketColorModeProvider), MarketColorMode.colorblind);

    await container
        .read(marketColorModeProvider.notifier)
        .set(MarketColorMode.greenUpRedDown);
    expect(
      prefs.getString('naviwealth.theme.market_color_mode'),
      MarketColorMode.greenUpRedDown.persistedKey,
    );
  });

  test('ThemeModeController defaults to system', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.system);
    await container.read(themeModeProvider.notifier).set(ThemeMode.dark);
    expect(prefs.getString('naviwealth.theme.mode'), 'dark');
  });
}
