import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/finance/fire/data/fire_plan_preferences.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'extras start at the documented defaults when nothing is persisted',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final extras = container.read(firePlanExtrasProvider);
      expect(extras.safeWithdrawalRate, FirePlan.defaultSafeWithdrawalRate);
      expect(extras.targetCashBucketMonths, FirePlan.defaultCashBucketMonths);
      expect(extras.lifestyleMode, FireLifestyleMode.standard);
      expect(extras.reserves, isEmpty);
      expect(extras.riskSettings, const FireRiskSettings());
    },
  );

  test(
    'save + reload round-trips every field across container instances',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final write = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(write.dispose);

      final reserve = FireReserve(
        id: 'r1',
        label: 'Medical',
        amount: Money(Decimal.parse('30000'), 'CNY'),
        kind: FireReserveKind.medical,
      );
      final updated = FirePlanExtras(
        safeWithdrawalRate: 0.035,
        targetCashBucketMonths: 18,
        lifestyleMode: FireLifestyleMode.fat,
        reserves: [reserve],
        riskSettings: const FireRiskSettings(
          marketDrawdownPct: 0.45,
          expenseShockPct: 0.25,
          fxShockPct: 0.12,
          oneOffShockAmount: 80000,
        ),
      );
      await write.read(firePlanExtrasProvider.notifier).save(updated);

      // Fresh container: re-read off SharedPreferences end-to-end.
      final reload = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(reload.dispose);
      final restored = reload.read(firePlanExtrasProvider);
      expect(restored.safeWithdrawalRate, 0.035);
      expect(restored.targetCashBucketMonths, 18);
      expect(restored.lifestyleMode, FireLifestyleMode.fat);
      expect(restored.reserves, [reserve]);
      expect(restored.riskSettings, updated.riskSettings);
    },
  );

  test('clear() resets to defaults', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await container
        .read(firePlanExtrasProvider.notifier)
        .save(FirePlanExtras.defaults().copyWith(safeWithdrawalRate: 0.05));
    await container.read(firePlanExtrasProvider.notifier).clear();
    expect(
      container.read(firePlanExtrasProvider).safeWithdrawalRate,
      FirePlan.defaultSafeWithdrawalRate,
    );
  });

  test('corrupt JSON falls back to defaults without throwing', () async {
    SharedPreferences.setMockInitialValues({
      'naviwealth.fire.reserves_json': '{not valid json',
      'naviwealth.fire.risk_settings_json': '!!',
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final extras = container.read(firePlanExtrasProvider);
    expect(extras.reserves, isEmpty);
    expect(extras.riskSettings, const FireRiskSettings());
  });
}
