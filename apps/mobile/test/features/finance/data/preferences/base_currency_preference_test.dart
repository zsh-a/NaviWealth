import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container(SharedPreferences prefs) {
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  group('BaseCurrencyController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to CNY when nothing is persisted', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _container(prefs);
      addTearDown(c.dispose);
      expect(c.read(baseCurrencyProvider), 'CNY');
    });

    test('persists changes and round-trips them on next start', () async {
      var prefs = await SharedPreferences.getInstance();
      final c = _container(prefs);
      await c.read(baseCurrencyProvider.notifier).set('USD');
      expect(c.read(baseCurrencyProvider), 'USD');
      c.dispose();

      // Simulate process restart — re-read the same SharedPreferences and
      // confirm the controller hydrates from the stored value.
      prefs = await SharedPreferences.getInstance();
      final c2 = _container(prefs);
      addTearDown(c2.dispose);
      expect(c2.read(baseCurrencyProvider), 'USD');
    });

    test('normalises whitespace + lowercase input', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _container(prefs);
      addTearDown(c.dispose);
      await c.read(baseCurrencyProvider.notifier).set('  hkd ');
      expect(c.read(baseCurrencyProvider), 'HKD');
    });

    test('ignores empty input rather than wiping the preference', () async {
      final prefs = await SharedPreferences.getInstance();
      final c = _container(prefs);
      addTearDown(c.dispose);
      await c.read(baseCurrencyProvider.notifier).set('USD');
      await c.read(baseCurrencyProvider.notifier).set('');
      expect(c.read(baseCurrencyProvider), 'USD');
    });
  });
}
