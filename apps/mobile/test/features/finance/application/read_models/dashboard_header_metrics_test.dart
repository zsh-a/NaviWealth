import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_trend_builder.dart';

void main() {
  test('header deltas are unavailable when a baseline is incomplete', () async {
    final now = DateTime.utc(2026, 8, 15, 12);
    final today = DateTime.utc(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final monthStart = DateTime.utc(today.year, today.month, 1);
    final yearStart = DateTime.utc(today.year, 1, 1);
    final container = ProviderContainer(
      overrides: [
        dashboardHeaderClockProvider.overrideWithValue(() => now),
        dashboardBaseCurrencyProvider.overrideWith((_) => 'USD'),
        dashboardTrendProvider.overrideWith(
          (_, range) async => DashboardTrend(
            range: range,
            baseCurrency: 'USD',
            points: [
              _point(yearStart, 800, TrendPointQuality.incomplete),
              _point(monthStart, 900, TrendPointQuality.incomplete),
              _point(yesterday, 980, TrendPointQuality.incomplete),
              _point(today, 1000, TrendPointQuality.complete),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final metrics = await container.read(dashboardHeaderMetricsProvider.future);

    expect(metrics.dailyChange, isNull);
    expect(metrics.monthlyChange, isNull);
    expect(metrics.monthlyChangePct, isNull);
    expect(metrics.ytdChange, isNull);
    expect(metrics.ytdChangePct, isNull);
  });

  test(
    'daily delta remains available when both daily points are complete',
    () async {
      final now = DateTime.utc(2026, 8, 15, 12);
      final today = DateTime.utc(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final yearStart = DateTime.utc(today.year, 1, 1);
      final container = ProviderContainer(
        overrides: [
          dashboardHeaderClockProvider.overrideWithValue(() => now),
          dashboardBaseCurrencyProvider.overrideWith((_) => 'USD'),
          dashboardTrendProvider.overrideWith(
            (_, range) async => DashboardTrend(
              range: range,
              baseCurrency: 'USD',
              points: [
                _point(yearStart, 800, TrendPointQuality.incomplete),
                _point(yesterday, 980, TrendPointQuality.complete),
                _point(today, 1000, TrendPointQuality.complete),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final metrics = await container.read(
        dashboardHeaderMetricsProvider.future,
      );

      expect(metrics.dailyChange?.amount, Decimal.fromInt(20));
      expect(metrics.ytdChange, isNull);
      expect(metrics.ytdChangePct, isNull);
    },
  );
}

TrendPoint _point(DateTime asOf, int value, TrendPointQuality quality) {
  final netWorth = Money(Decimal.fromInt(value), 'USD');
  return TrendPoint(
    asOf: asOf,
    assets: netWorth,
    liabilities: Money.zero('USD'),
    netWorth: netWorth,
    quality: quality,
  );
}
