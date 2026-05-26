/// Agent scheduling primitives (`docs/lifeos-shell.md` §7.3, D-2.5).
///
/// MVP keeps this pure-Dart: an interval ("every 24h") + an optional
/// preferred hour ("around 07:00 local") + bookkeeping for the last
/// fire. Native cron / background-fetch wiring is a follow-up (the
/// runner offers a `tick(now)` entry point so the platform-side
/// driver can be swapped without touching agent code).
library;

import 'package:flutter/foundation.dart';

@immutable
class AgentSchedule {
  const AgentSchedule({
    required this.interval,
    this.preferredHourLocal,
    this.jitter = const Duration(minutes: 5),
  });

  /// Build a daily schedule.
  factory AgentSchedule.daily({int hourLocal = 7}) =>
      AgentSchedule(
        interval: const Duration(days: 1),
        preferredHourLocal: hourLocal,
      );

  /// Build an N-hours-apart schedule with no preferred wall-clock
  /// anchor. Useful for non-user-facing maintenance agents.
  factory AgentSchedule.everyHours(int hours) =>
      AgentSchedule(interval: Duration(hours: hours));

  /// Minimum gap between fires. The runner gates `shouldFire` so two
  /// ticks inside this window won't both run.
  final Duration interval;

  /// Local-time anchor (0–23). When set, `shouldFire` won't fire until
  /// `now`'s local hour reaches this value AND [interval] has elapsed
  /// since the last fire. `null` ⇒ no hour gate.
  final int? preferredHourLocal;

  /// Tolerance window on the preferred hour. Without this, an app
  /// opened at 06:55 wouldn't fire today's briefing. Default ±5min.
  final Duration jitter;

  /// True iff the agent should fire right now given the last
  /// successful run.
  ///
  /// - `lastRunAt == null` → fire on the first tick that passes the
  ///   preferred-hour gate (or immediately when no hour anchor is set)
  /// - `lastRunAt != null` → must have at least [interval] elapsed
  ///   AND we're inside the preferred-hour window (if set)
  bool shouldFire({required DateTime now, DateTime? lastRunAt}) {
    if (lastRunAt != null && now.difference(lastRunAt) < interval) {
      return false;
    }
    final hour = preferredHourLocal;
    if (hour == null) return true;
    // `now.hour` is already local time; jitter expands the hit window
    // symmetrically. A `jitter == 5min` schedule for hour=7 fires for
    // local 06:55–07:05.
    final localHour = now.toLocal().hour;
    final localMinute = now.toLocal().minute;
    final secondsFromTarget =
        ((localHour - hour) * 3600 + localMinute * 60).abs();
    return secondsFromTarget <= jitter.inSeconds;
  }

  @override
  bool operator ==(Object other) =>
      other is AgentSchedule &&
      other.interval == interval &&
      other.preferredHourLocal == preferredHourLocal &&
      other.jitter == jitter;

  @override
  int get hashCode => Object.hash(interval, preferredHourLocal, jitter);
}
