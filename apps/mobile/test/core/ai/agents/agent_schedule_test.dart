import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';

void main() {
  group('AgentSchedule.shouldFire — interval gate', () {
    test('first run (lastRunAt == null) fires when no hour anchor', () {
      const s = AgentSchedule(interval: Duration(hours: 1));
      expect(s.shouldFire(now: DateTime(2026, 5, 27, 14, 23)), isTrue);
    });

    test('blocks re-fire inside interval window', () {
      const s = AgentSchedule(interval: Duration(hours: 6));
      final last = DateTime(2026, 5, 27, 10);
      expect(
        s.shouldFire(
          now: DateTime(2026, 5, 27, 13), // 3h after, still gated
          lastRunAt: last,
        ),
        isFalse,
      );
    });

    test('fires once interval elapsed', () {
      const s = AgentSchedule(interval: Duration(hours: 6));
      final last = DateTime(2026, 5, 27, 10);
      expect(
        s.shouldFire(
          now: DateTime(2026, 5, 27, 16, 30), // 6.5h after
          lastRunAt: last,
        ),
        isTrue,
      );
    });
  });

  group('AgentSchedule.shouldFire — preferred hour anchor', () {
    test('fires in the preferred-hour window (±jitter)', () {
      final s = AgentSchedule.daily(hourLocal: 7);
      // Build a `now` whose local hour is 7; jitter is 5min so any
      // minute 00–04 is inside, plus the 5min lookahead 55–59 of hour 6.
      final inWindow = DateTime(2026, 5, 27, 7, 2);
      expect(s.shouldFire(now: inWindow), isTrue);
    });

    test('blocks outside the preferred-hour window', () {
      final s = AgentSchedule.daily(hourLocal: 7);
      final tooLate = DateTime(2026, 5, 27, 9, 0);
      expect(s.shouldFire(now: tooLate), isFalse);
    });

    test('still blocks when interval elapsed but hour wrong', () {
      final s = AgentSchedule.daily(hourLocal: 7);
      final last = DateTime(2026, 5, 26, 7, 1);
      final now = DateTime(2026, 5, 27, 20, 0); // 37h later, but hour 20
      expect(s.shouldFire(now: now, lastRunAt: last), isFalse);
    });

    test('honours custom jitter', () {
      const wideSchedule = AgentSchedule(
        interval: Duration(days: 1),
        preferredHourLocal: 7,
        jitter: Duration(minutes: 30),
      );
      final widerWindow = DateTime(2026, 5, 27, 7, 25);
      expect(wideSchedule.shouldFire(now: widerWindow), isTrue);
    });
  });

  test('equality + hash consider all fields', () {
    const a = AgentSchedule(
      interval: Duration(hours: 1),
      preferredHourLocal: 7,
      jitter: Duration(minutes: 5),
    );
    const b = AgentSchedule(
      interval: Duration(hours: 1),
      preferredHourLocal: 7,
      jitter: Duration(minutes: 5),
    );
    const c = AgentSchedule(interval: Duration(hours: 1));
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == c, isFalse);
  });
}
