import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/time/current_time_provider.dart';
import 'package:naviwealth/features/health/data/health_calendar_providers.dart';

void main() {
  testWidgets(
    'calendar windows advance while mounted and refresh after background midnight',
    (tester) async {
      var now = DateTime(2026, 10, 1, 23, 59, 59);
      final container = ProviderContainer(
        overrides: [
          healthClockProvider.overrideWithValue(() => now),
          currentTimeProvider.overrideWith(() => CurrentTime(now: () => now)),
        ],
      );
      final subscription = container.listen(
        healthCalendarDayProvider,
        (_, _) {},
      );
      expect(
        container.read(healthCalendarDayProvider),
        DateTime.utc(2026, 10, 1),
      );
      now = DateTime(2026, 10, 2);
      await tester.pump(const Duration(minutes: 1));
      expect(
        container.read(healthCalendarDayProvider),
        DateTime.utc(2026, 10, 2),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = DateTime(2026, 10, 3, 8);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        container.read(healthCalendarDayProvider),
        DateTime.utc(2026, 10, 3),
      );
      subscription.close();
      container.dispose();
      await tester.pump();
    },
  );
}
