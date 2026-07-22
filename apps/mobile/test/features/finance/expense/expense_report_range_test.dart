import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_report_range.dart';

void main() {
  group('ExpenseReportRange', () {
    test('monthToDate spans the 1st of the current month → tomorrow UTC', () {
      final range = ExpenseReportRange.resolve(
        preset: ExpenseReportRangePreset.monthToDate,
        now: DateTime.utc(2026, 4, 17, 14, 30),
      );
      expect(range.from, DateTime.utc(2026, 4, 1));
      expect(range.to, DateTime.utc(2026, 4, 18));
      expect(range.monthSpan, 1);
      expect(range.daySpan, 17);
    });

    test('m3 starts at the 1st of two months back', () {
      final range = ExpenseReportRange.resolve(
        preset: ExpenseReportRangePreset.m3,
        now: DateTime.utc(2026, 4, 17),
      );
      expect(range.from, DateTime.utc(2026, 2, 1));
      expect(range.to, DateTime.utc(2026, 4, 18));
      expect(range.monthSpan, 3);
    });

    test('m6 wraps year boundary correctly', () {
      final range = ExpenseReportRange.resolve(
        preset: ExpenseReportRangePreset.m6,
        now: DateTime.utc(2026, 2, 10),
      );
      expect(range.from, DateTime.utc(2025, 9, 1));
      expect(range.to, DateTime.utc(2026, 2, 11));
      expect(range.monthSpan, 6);
    });

    test('m12 starts a year ago', () {
      final range = ExpenseReportRange.resolve(
        preset: ExpenseReportRangePreset.m12,
        now: DateTime.utc(2026, 4, 17),
      );
      expect(range.from, DateTime.utc(2025, 5, 1));
      expect(range.monthSpan, 12);
    });

    test('custom range floors to UTC day and uses exclusive end', () {
      final range = ExpenseReportRange.resolve(
        preset: ExpenseReportRangePreset.custom,
        customFrom: DateTime.utc(2026, 1, 15),
        customTo: DateTime.utc(2026, 3, 5),
      );
      expect(range.from, DateTime.utc(2026, 1, 15));
      expect(range.to, DateTime.utc(2026, 3, 6));
      expect(range.monthSpan, 3);
    });

    test('custom range rejects missing args', () {
      expect(
        () =>
            ExpenseReportRange.resolve(preset: ExpenseReportRangePreset.custom),
        throwsArgumentError,
      );
    });

    test('custom range rejects inverted bounds', () {
      expect(
        () => ExpenseReportRange.resolve(
          preset: ExpenseReportRangePreset.custom,
          customFrom: DateTime.utc(2026, 4, 1),
          customTo: DateTime.utc(2026, 3, 1),
        ),
        throwsArgumentError,
      );
    });
  });
}
