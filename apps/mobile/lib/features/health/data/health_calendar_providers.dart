import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/current_time_provider.dart';
import 'health_series.dart';

final healthClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Date-window reads follow the shell's existing foreground clock, including
/// resume after midnight. Keep the injectable Health clock for deterministic
/// domain projections without introducing a second timer or lifecycle driver.
final healthCalendarDayProvider = Provider.autoDispose<DateTime>((ref) {
  ref.watch(currentLocalDayProvider);
  return healthDay(ref.watch(healthClockProvider)());
});
