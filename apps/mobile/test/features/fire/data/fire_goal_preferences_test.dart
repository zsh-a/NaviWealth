import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/fire/data/fire_goal_preferences.dart';
import 'package:naviwealth/features/fire/domain/fire_goal.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container(SharedPreferences prefs) {
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('initial state is the unset goal when no preferences exist', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = _container(prefs);
    addTearDown(container.dispose);

    final goal = container.read(fireGoalProvider);
    expect(goal.isConfigured, isFalse);
    expect(goal.targetAmount, Decimal.zero);
    expect(goal.inflationRate, FireGoal.defaultInflationRate);
  });

  test('save persists each field and updates state', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = _container(prefs);
    addTearDown(container.dispose);

    final ctrl = container.read(fireGoalProvider.notifier);
    final goal = FireGoal(
      targetAmount: Decimal.parse('1500000.50'),
      monthlyExpenses: Decimal.parse('5000'),
      monthlySurplus: Decimal.parse('8000'),
      inflationRate: 0.025,
    );
    await ctrl.save(goal);

    expect(container.read(fireGoalProvider), goal);

    // Re-read from a fresh container (same prefs) — survives a "process
    // restart" in test land.
    final container2 = _container(prefs);
    addTearDown(container2.dispose);
    expect(container2.read(fireGoalProvider), goal);
  });

  test('clear restores the unset goal and removes the keys', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = _container(prefs);
    addTearDown(container.dispose);

    await container.read(fireGoalProvider.notifier).save(
          FireGoal(
            targetAmount: Decimal.parse('500000'),
            monthlyExpenses: Decimal.zero,
            monthlySurplus: Decimal.zero,
            inflationRate: 0.03,
          ),
        );
    await container.read(fireGoalProvider.notifier).clear();

    expect(container.read(fireGoalProvider).isConfigured, isFalse);
    final container2 = _container(prefs);
    addTearDown(container2.dispose);
    expect(container2.read(fireGoalProvider).isConfigured, isFalse);
  });

  test('corrupt decimal in storage falls back to zero rather than throwing',
      () async {
    SharedPreferences.setMockInitialValues({
      'naviwealth.fire.target_amount': 'not-a-number',
    });
    final prefs = await SharedPreferences.getInstance();
    final container = _container(prefs);
    addTearDown(container.dispose);

    final goal = container.read(fireGoalProvider);
    expect(goal.targetAmount, Decimal.zero);
    expect(goal.isConfigured, isFalse);
  });
}
