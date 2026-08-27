/// Agent scheduling primitives (`docs/architecture/lifeos-shell.md` §7.3, D-2.5).
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
  factory AgentSchedule.daily({int hourLocal = 7}) => AgentSchedule(
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
  /// `now` has reached this value's local-day catch-up window AND [interval]
  /// has elapsed since the last fire. `null` ⇒ no hour gate.
  final int? preferredHourLocal;

  /// Early tolerance window before the preferred hour. Without this, an app
  /// opened at 06:55 wouldn't fire today's 07:00 briefing. Once the preferred
  /// hour has passed, the schedule stays eligible for the rest of the local
  /// day, subject to [interval] and same-day duplicate gating.
  final Duration jitter;

  /// True iff the agent should fire right now given the last
  /// successful run.
  ///
  /// - `lastRunAt == null` → fire on the first tick that passes the
  ///   preferred-hour gate (or immediately when no hour anchor is set)
  /// - `lastRunAt != null` → must have at least [interval] elapsed, must not
  ///   have already run on the same local day, and must pass the
  ///   preferred-hour gate (if set)
  bool shouldFire({required DateTime now, DateTime? lastRunAt}) {
    if (lastRunAt != null && now.difference(lastRunAt) < interval) {
      return false;
    }
    final hour = preferredHourLocal;
    if (hour == null) return true;
    final localNow = now.toLocal();
    if (lastRunAt != null && _isSameLocalDay(localNow, lastRunAt.toLocal())) {
      return false;
    }
    final target = DateTime(localNow.year, localNow.month, localNow.day, hour);
    return !localNow.isBefore(target.subtract(jitter));
  }

  /// The next point at which this schedule is eligible to run.
  ///
  /// A schedule is evaluated by a foreground or platform tick, so a due
  /// schedule returns [now] rather than pretending that the app can execute
  /// at an exact wall-clock instant. Callers can use that value to explain
  /// "ready when the app opens" in the UI.
  ///
  /// `null` means there is no wall-clock prediction yet (for example, an
  /// interval-only schedule that has never run). Such schedules become due
  /// on the next tick.
  DateTime? nextRunAt({required DateTime now, DateTime? lastRunAt}) {
    final localNow = now.toLocal();
    if (shouldFire(now: now, lastRunAt: lastRunAt)) return localNow;

    final hour = preferredHourLocal;
    if (hour == null) {
      final last = lastRunAt?.toLocal();
      if (last == null) return null;
      return last.add(interval);
    }

    var candidate = DateTime(localNow.year, localNow.month, localNow.day, hour);
    if (!candidate.isAfter(localNow)) {
      candidate = _addLocalDays(candidate, 1);
    }

    final last = lastRunAt?.toLocal();
    if (last != null) {
      final minimum = last.add(interval);
      if (minimum.isAfter(candidate)) candidate = minimum;
      if (_isSameLocalDay(candidate, last)) {
        candidate = _addLocalDays(candidate, 1);
      }
    }
    return candidate;
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

bool _isSameLocalDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _addLocalDays(DateTime value, int days) => DateTime(
  value.year,
  value.month,
  value.day + days,
  value.hour,
  value.minute,
  value.second,
  value.millisecond,
  value.microsecond,
);
