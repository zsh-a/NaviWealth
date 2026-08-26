import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_granularity.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_trend_builder.dart';

DashboardTimeRange _range(DateTime from, DateTime to) =>
    DashboardTimeRange.resolve(
      preset: DashboardRangePreset.custom,
      now: to,
      customFrom: from,
      customTo: to,
    );

DashboardPhysicalAsset _physical({
  required String id,
  required AssetType type,
  required DateTime purchaseDate,
  required String purchasePrice,
  required String currentValuation,
  bool autoDepreciation = false,
  String? annualResidualRate,
  List<DashboardPhysicalValuation> valuationHistory = const [],
}) => DashboardPhysicalAsset(
  id: id,
  name: id,
  currency: 'USD',
  type: type,
  currentValuation: Decimal.parse(currentValuation),
  purchaseDate: purchaseDate,
  purchasePrice: Decimal.parse(purchasePrice),
  autoDepreciation: autoDepreciation,
  annualResidualRate: annualResidualRate == null
      ? null
      : Decimal.parse(annualResidualRate),
  valuationHistory: valuationHistory,
);

void main() {
  test('all range starts at the earliest known data date', () {
    final range = DashboardTimeRange.resolve(
      preset: DashboardRangePreset.all,
      now: DateTime.utc(2026, 1, 3, 18),
      earliestDataDate: DateTime.utc(2024, 6, 15, 12),
    );

    expect(range.from, DateTime.utc(2024, 6, 15));
    expect(range.to, DateTime.utc(2026, 1, 3));
    expect(range.granularity, NetWorthGranularity.week);
  });

  test(
    'replays every physical valuation instead of interpolating endpoints',
    () {
      final purchase = DateTime.utc(2026, 1, 1, 12);
      final trend = buildDashboardTrend(
        range: _range(purchase, DateTime.utc(2026, 1, 3)),
        baseCurrency: 'USD',
        fxRates: const [],
        manualAssets: const [],
        physicalAssets: [
          _physical(
            id: 'home',
            type: AssetType.realEstate,
            purchaseDate: purchase,
            purchasePrice: '1000',
            currentValuation: '1200',
            valuationHistory: [
              DashboardPhysicalValuation(
                asOf: purchase,
                value: Decimal.fromInt(1000),
              ),
              DashboardPhysicalValuation(
                asOf: purchase,
                value: Decimal.fromInt(1100),
              ),
              DashboardPhysicalValuation(
                asOf: DateTime.utc(2026, 1, 2),
                value: Decimal.fromInt(1500),
              ),
              DashboardPhysicalValuation(
                asOf: DateTime.utc(2026, 1, 3),
                value: Decimal.fromInt(1200),
              ),
            ],
          ),
        ],
        liabilities: const [],
        liabilitySchedules: const {},
      );

      expect(trend.points.map((point) => point.assets.amount), [
        Decimal.fromInt(1100),
        Decimal.fromInt(1500),
        Decimal.fromInt(1200),
      ]);
      expect(
        trend.points.every(
          (point) => point.quality == TrendPointQuality.complete,
        ),
        isTrue,
      );
    },
  );

  test(
    'marks vehicle depreciation after the last manual valuation as estimated',
    () {
      final purchase = DateTime.utc(2026, 1, 1);
      final trend = buildDashboardTrend(
        range: _range(purchase, DateTime.utc(2026, 1, 2)),
        baseCurrency: 'USD',
        fxRates: const [],
        manualAssets: const [],
        physicalAssets: [
          _physical(
            id: 'car',
            type: AssetType.vehicle,
            purchaseDate: purchase,
            purchasePrice: '100000',
            currentValuation: '100000',
            autoDepreciation: true,
            annualResidualRate: '0.8',
            valuationHistory: [
              DashboardPhysicalValuation(
                asOf: purchase,
                value: Decimal.fromInt(100000),
              ),
            ],
          ),
        ],
        liabilities: const [],
        liabilitySchedules: const {},
      );

      expect(trend.points[1].assets.amount, lessThan(Decimal.fromInt(100000)));
      expect(trend.points[1].quality, TrendPointQuality.estimated);
    },
  );
}
