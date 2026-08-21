import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/data/preferences/finance_amount_privacy_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container(SharedPreferences preferences) {
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
  );
}

void main() {
  group('FinanceAmountsHiddenController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('shows amounts by default', () async {
      final preferences = await SharedPreferences.getInstance();
      final container = _container(preferences);
      addTearDown(container.dispose);

      expect(container.read(financeAmountsHiddenProvider), isFalse);
    });

    test('persists visibility across provider containers', () async {
      var preferences = await SharedPreferences.getInstance();
      final first = _container(preferences);

      await first.read(financeAmountsHiddenProvider.notifier).toggle();
      expect(first.read(financeAmountsHiddenProvider), isTrue);
      first.dispose();

      preferences = await SharedPreferences.getInstance();
      final second = _container(preferences);
      addTearDown(second.dispose);
      expect(second.read(financeAmountsHiddenProvider), isTrue);
    });
  });
}
