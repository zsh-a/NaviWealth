import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('document recognition is off until the user permits it', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final settings = container.read(aiPrivacySettingsProvider);
    expect(settings.allowDocumentRecognition, isFalse);
    expect(settings.maxBudgetTier, BudgetTier.small);
  });

  test('document permission persists and can be revoked', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer container() => ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    final first = container();
    await first
        .read(aiPrivacySettingsProvider.notifier)
        .setAllowDocumentRecognition(true);
    expect(
      first.read(aiPrivacySettingsProvider).maxBudgetTier,
      BudgetTier.large,
    );
    first.dispose();

    final restored = container();
    expect(
      restored.read(aiPrivacySettingsProvider).allowDocumentRecognition,
      isTrue,
    );
    await restored
        .read(aiPrivacySettingsProvider.notifier)
        .setAllowDocumentRecognition(false);
    restored.dispose();

    final revoked = container();
    addTearDown(revoked.dispose);
    expect(
      revoked.read(aiPrivacySettingsProvider).allowDocumentRecognition,
      isFalse,
    );
  });
}
