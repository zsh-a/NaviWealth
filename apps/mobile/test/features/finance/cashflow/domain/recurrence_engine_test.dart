import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/cashflow/domain/recurrence_engine.dart';

void main() {
  const engine = RecurrenceEngine();

  test('expands daily rules with interval and until', () {
    final dates = engine.expand(
      'FREQ=DAILY;INTERVAL=2;UNTIL=20260107',
      DateTime.utc(2026, 1, 1),
      DateTime.utc(2026, 1, 10),
    );

    expect(dates, [
      DateTime.utc(2026, 1, 1),
      DateTime.utc(2026, 1, 3),
      DateTime.utc(2026, 1, 5),
      DateTime.utc(2026, 1, 7),
    ]);
  });

  test('expands weekly rules on the same weekday', () {
    final dates = engine.expand(
      'FREQ=WEEKLY;INTERVAL=1',
      DateTime.utc(2026, 5, 4),
      DateTime.utc(2026, 5, 20),
    );

    expect(dates, [
      DateTime.utc(2026, 5, 4),
      DateTime.utc(2026, 5, 11),
      DateTime.utc(2026, 5, 18),
    ]);
  });

  test('monthly BYMONTHDAY skips invalid month-end dates', () {
    final dates = engine.expand(
      'FREQ=MONTHLY;BYMONTHDAY=31',
      DateTime.utc(2026, 1, 31),
      DateTime.utc(2026, 5, 31),
    );

    expect(dates, [
      DateTime.utc(2026, 1, 31),
      DateTime.utc(2026, 3, 31),
      DateTime.utc(2026, 5, 31),
    ]);
  });

  test('yearly leap-day rules skip non-leap years', () {
    final dates = engine.expand(
      'FREQ=YEARLY',
      DateTime.utc(2024, 2, 29),
      DateTime.utc(2030, 12, 31),
    );

    expect(dates, [DateTime.utc(2024, 2, 29), DateTime.utc(2028, 2, 29)]);
  });

  test('rejects unsupported frequency', () {
    expect(
      () => engine.expand(
        'FREQ=HOURLY',
        DateTime.utc(2026),
        DateTime.utc(2026, 1, 2),
      ),
      throwsA(isA<RecurrenceParseException>()),
    );
  });
}
