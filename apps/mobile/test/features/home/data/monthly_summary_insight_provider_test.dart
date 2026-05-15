import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/home/data/monthly_summary_insight_provider.dart';
import 'package:naviwealth/features/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/features/home/domain/dashboard_trend_builder.dart';

TrendPoint _p(DateTime asOf, double netWorth, {String currency = 'CNY'}) {
  return TrendPoint(
    asOf: asOf,
    assets: Money(Decimal.parse(netWorth.toString()), currency),
    liabilities: Money(Decimal.zero, currency),
    netWorth: Money(Decimal.parse(netWorth.toString()), currency),
  );
}

DashboardTrend _trend(List<TrendPoint> points, {String currency = 'CNY'}) {
  return DashboardTrend(
    range: DashboardTimeRange.resolve(
      preset: DashboardRangePreset.y1,
      now: DateTime.utc(2026, 5, 1),
    ),
    baseCurrency: currency,
    points: points,
  );
}

void main() {
  group('summarizeMonthlyDelta', () {
    test('returns null when trend is null', () {
      expect(
        summarizeMonthlyDelta(trend: null, now: DateTime.utc(2026, 5, 3)),
        isNull,
      );
    });

    test('returns null outside the 7-day window', () {
      final trend = _trend(<TrendPoint>[
        _p(DateTime.utc(2026, 3, 31), 100000),
        _p(DateTime.utc(2026, 4, 30), 121400),
      ]);
      // 9 days into May → window has closed.
      expect(
        summarizeMonthlyDelta(
          trend: trend,
          now: DateTime.utc(2026, 5, 9),
        ),
        isNull,
      );
    });

    test('reports an upward delta inside the window', () {
      final trend = _trend(<TrendPoint>[
        _p(DateTime.utc(2026, 3, 31), 100000),
        _p(DateTime.utc(2026, 4, 30), 121400),
      ]);
      final summary = summarizeMonthlyDelta(
        trend: trend,
        now: DateTime.utc(2026, 5, 3),
      );
      expect(summary, isNotNull);
      expect(summary!.year, 2026);
      expect(summary.month, 4);
      expect(summary.deltaMinor, 2140000); // 21,400.00 in cents
      expect(summary.currency, 'CNY');
      expect(summary.scopeHash, '2026-04');
    });

    test('reports a downward delta', () {
      final trend = _trend(<TrendPoint>[
        _p(DateTime.utc(2026, 3, 31), 100000),
        _p(DateTime.utc(2026, 4, 30), 95000),
      ]);
      final summary = summarizeMonthlyDelta(
        trend: trend,
        now: DateTime.utc(2026, 5, 1),
      )!;
      expect(summary.deltaMinor, -500000);
    });

    test('returns null when no anchor exists before the prior month', () {
      final trend = _trend(<TrendPoint>[
        // First point is inside the prior month — no earlier anchor.
        _p(DateTime.utc(2026, 4, 15), 50000),
        _p(DateTime.utc(2026, 4, 30), 60000),
      ]);
      expect(
        summarizeMonthlyDelta(
          trend: trend,
          now: DateTime.utc(2026, 5, 3),
        ),
        isNull,
      );
    });

    test('returns null when no point lands inside the prior month', () {
      final trend = _trend(<TrendPoint>[
        _p(DateTime.utc(2026, 3, 31), 100000),
        // Skipped April, so no end-point inside the prior month.
        _p(DateTime.utc(2026, 5, 1), 105000),
      ]);
      expect(
        summarizeMonthlyDelta(
          trend: trend,
          now: DateTime.utc(2026, 5, 3),
        ),
        isNull,
      );
    });
  });
}
