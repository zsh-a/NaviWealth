import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  group('AiPrivacySettings', () {
    test('defaults to amountsAllowed with no account masking', () {
      const s = AiPrivacySettings.defaults;
      expect(s.mode, AiPrivacyMode.amountsAllowed);
      expect(s.maskAccountNames, isFalse);
      expect(s.maxBudgetTier, BudgetTier.large);
    });

    test('amountsBucketed caps at standard tier', () {
      const s = AiPrivacySettings(
        mode: AiPrivacyMode.amountsBucketed,
        maskAccountNames: false,
      );
      expect(s.maxBudgetTier, BudgetTier.standard);
    });

    test('amountsLocal caps at small tier', () {
      const s = AiPrivacySettings(
        mode: AiPrivacyMode.amountsLocal,
        maskAccountNames: true,
      );
      expect(s.maxBudgetTier, BudgetTier.small);
    });
  });

  group('AiPrivacyController', () {
    test('reads defaults when no prefs are written', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      final s = c.read(aiPrivacySettingsProvider);
      expect(s.mode, AiPrivacyMode.amountsAllowed);
      expect(s.maskAccountNames, isFalse);
    });

    test('setMode persists across container rebuilds', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c1 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      await c1
          .read(aiPrivacySettingsProvider.notifier)
          .setMode(AiPrivacyMode.amountsLocal);
      expect(
        c1.read(aiPrivacySettingsProvider).mode,
        AiPrivacyMode.amountsLocal,
      );
      c1.dispose();

      // Fresh container — same shared prefs map — restores the choice.
      final c2 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c2.dispose);
      expect(
        c2.read(aiPrivacySettingsProvider).mode,
        AiPrivacyMode.amountsLocal,
      );
    });

    test('setMaskAccountNames toggles the flag', () async {
      final c = await _makeContainer();
      addTearDown(c.dispose);
      expect(c.read(aiPrivacySettingsProvider).maskAccountNames, isFalse);
      await c
          .read(aiPrivacySettingsProvider.notifier)
          .setMaskAccountNames(true);
      expect(c.read(aiPrivacySettingsProvider).maskAccountNames, isTrue);
    });
  });

  group('onboarding seen flag', () {
    test('starts false and flips to true after mark', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c.dispose);
      expect(c.read(aiPrivacyOnboardingSeenProvider), isFalse);
      await markAiPrivacyOnboardingSeen(prefs);
      // Provider reads prefs on each lookup, so a fresh read picks up
      // the new value without an explicit invalidate.
      c.invalidate(aiPrivacyOnboardingSeenProvider);
      expect(c.read(aiPrivacyOnboardingSeenProvider), isTrue);
    });
  });

  group('wire round-trips', () {
    test('AiPrivacyMode wire form is stable', () {
      expect(AiPrivacyMode.amountsAllowed.wire, 'amounts_allowed');
      expect(AiPrivacyMode.amountsBucketed.wire, 'amounts_bucketed');
      expect(AiPrivacyMode.amountsLocal.wire, 'amounts_local');
    });

    test('parse falls back to amountsAllowed for unknown strings', () {
      expect(AiPrivacyModeWire.parse('nonsense'), AiPrivacyMode.amountsAllowed);
    });
  });
}
