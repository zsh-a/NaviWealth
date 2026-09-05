import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/time/current_time_provider.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/execution/data/execution_daily_focus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('minute ticks advance local day and reset persisted focus', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 5, 23, 59);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        currentTimeProvider.overrideWith(() => CurrentTime(now: () => now)),
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
    );
    final subscription = container.listen(
      executionDailyFocusProvider,
      (_, _) {},
    );
    await container.read(executionDailyFocusProvider.notifier).set(['focus']);
    expect(container.read(executionDailyFocusProvider), ['focus']);
    now = DateTime(2026, 9, 6, 0, 0);
    await tester.pump(const Duration(minutes: 1));
    expect(container.read(currentLocalDayProvider), DateTime(2026, 9, 6));
    expect(container.read(executionDailyFocusProvider), isEmpty);
    subscription.close();
    container.dispose();
  });

  testWidgets('resume refreshes time immediately without waiting for a tick', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 5, 12);
    final container = ProviderContainer(
      overrides: [
        currentTimeProvider.overrideWith(() => CurrentTime(now: () => now)),
      ],
    );
    final subscription = container.listen(currentTimeProvider, (_, _) {});
    expect(subscription.read(), now);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(2026, 9, 6, 8);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(subscription.read(), now);
    subscription.close();
    container.dispose();
  });
}
