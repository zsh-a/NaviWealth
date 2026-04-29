import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/amortization_entry.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/liability.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/domain/services/net_worth_service.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset_meta.dart';
import 'package:naviwealth/features/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/features/home/domain/dashboard_trend_builder.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int y, int m, int dd) => DateTime.utc(y, m, dd);

SyncMeta _meta() => SyncMeta(
      ownerUserId: 'u',
      updatedAt: day(2026, 4, 1),
      updatedByDevice: 'test',
      hlc: Hlc.zero('test'),
    );

Asset _cash({String id = 'c', required String price}) {
  return Asset(
    id: id,
    type: AssetType.cash,
    symbol: id,
    currency: 'CNY',
    lastPrice: d(price),
    sync: _meta(),
  );
}

PhysicalAsset _physical({
  required String id,
  required DateTime purchaseDate,
  required String purchase,
  required String current,
  DateTime? lastValuationAt,
}) {
  final meta = PhysicalAssetMeta(
    purchaseDate: purchaseDate,
    purchasePrice: d(purchase),
  );
  return PhysicalAsset(
    row: AssetRow(
      id: id,
      ownerUserId: 'u',
      updatedAt: day(2026, 4, 1),
      updatedByDevice: 'test',
      hlc: Hlc.zero('test'),
      type: AssetType.realEstate,
      symbol: id,
      currency: 'CNY',
      lastPrice: d(current),
      lastPriceAt: lastValuationAt,
      metadataJson: meta.encode(),
    ),
    meta: meta,
  );
}

Liability _liability({
  required String id,
  required String principal,
  DateTime? startDate,
}) {
  return Liability(
    id: id,
    type: LiabilityType.mortgage,
    name: 'L',
    principal: d(principal),
    interestRate: d('0.045'),
    currency: 'CNY',
    startDate: startDate,
    sync: _meta(),
  );
}

AmortizationEntry _row({
  required String liabilityId,
  required int period,
  required DateTime due,
  required String remaining,
}) {
  return AmortizationEntry(
    id: '$liabilityId-$period',
    liabilityId: liabilityId,
    periodIndex: period,
    dueDate: due,
    principalPayment: Decimal.zero,
    interestPayment: Decimal.zero,
    remainingBalance: d(remaining),
    sync: _meta(),
  );
}

DashboardTrendBuilder _builder() => DashboardTrendBuilder(
      converter: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
      baseCurrency: 'CNY',
    );

void main() {
  group('DashboardTrendBuilder', () {
    test('cash held flat across the window', () {
      final range = DashboardTimeRange.resolve(
        preset: DashboardRangePreset.m1,
        now: day(2026, 4, 30),
      );
      final trend = _builder().build(
        range: range,
        manualAssets: [_cash(id: 'c', price: '10000')],
        physicalAssets: const [],
        liabilities: const [],
        liabilitySchedules: const {},
      );
      expect(trend.points, isNotEmpty);
      // Every point should report the same net worth.
      final first = trend.points.first.netWorth.amount;
      expect(first, d('10000'));
      expect(trend.points.every((p) => p.netWorth.amount == first), isTrue);
    });

    test('liability schedule drives outstanding balance over time', () {
      final liability = _liability(
        id: 'L',
        principal: '120000',
        startDate: day(2025, 1, 1),
      );
      final schedule = [
        _row(
          liabilityId: 'L',
          period: 1,
          due: day(2025, 6, 1),
          remaining: '110000',
        ),
        _row(
          liabilityId: 'L',
          period: 2,
          due: day(2025, 12, 1),
          remaining: '100000',
        ),
        _row(
          liabilityId: 'L',
          period: 3,
          due: day(2026, 6, 1),
          remaining: '90000',
        ),
      ];
      final range = DashboardTimeRange.resolve(
        preset: DashboardRangePreset.y1,
        now: day(2026, 6, 30),
      );
      final trend = _builder().build(
        range: range,
        manualAssets: const [],
        physicalAssets: const [],
        liabilities: [liability],
        liabilitySchedules: {'L': schedule},
      );
      // Outstanding falls from 110000 → 100000 → 90000 across the window.
      final firstLiab = trend.points.first.liabilities.amount;
      final lastLiab = trend.points.last.liabilities.amount;
      expect(firstLiab >= lastLiab, isTrue);
      expect(lastLiab, d('90000'));
      // Net worth = -liabilities (no assets in this scenario).
      expect(trend.points.last.netWorth.amount, d('-90000'));
    });

    test('physical asset interpolates between purchase and current valuation',
        () {
      final pa = _physical(
        id: 'house',
        purchaseDate: day(2025, 1, 1),
        purchase: '1000000',
        current: '1500000',
        lastValuationAt: day(2026, 1, 1),
      );
      final range = DashboardTimeRange.resolve(
        preset: DashboardRangePreset.y1,
        now: day(2026, 1, 1),
        earliestDataDate: day(2025, 1, 1),
      );
      final trend = _builder().build(
        range: range,
        manualAssets: const [],
        physicalAssets: [pa],
        liabilities: const [],
        liabilitySchedules: const {},
      );
      // First point at-or-after purchase should equal purchasePrice.
      expect(
        trend.points.first.assets.amount,
        d('1000000'),
      );
      // Last point matches the current valuation.
      expect(trend.points.last.assets.amount, d('1500000'));
      // Some interior point sits between the two anchors (interpolation).
      final mid = trend.points[trend.points.length ~/ 2];
      expect(mid.assets.amount > d('1000000'), isTrue);
      expect(mid.assets.amount < d('1500000'), isTrue);
    });

    test('granularity adapts to window length', () {
      final mtr = DashboardTimeRange.resolve(
        preset: DashboardRangePreset.m1,
        now: day(2026, 4, 30),
      );
      expect(mtr.granularity, NetWorthGranularity.day);
      final yr = DashboardTimeRange.resolve(
        preset: DashboardRangePreset.y1,
        now: day(2026, 4, 30),
      );
      expect(yr.granularity, NetWorthGranularity.week);
      final all = DashboardTimeRange.resolve(
        preset: DashboardRangePreset.all,
        now: day(2026, 4, 30),
        earliestDataDate: day(2020, 1, 1),
      );
      expect(all.granularity, NetWorthGranularity.month);
    });

    test('custom range honours user-picked endpoints', () {
      final range = DashboardTimeRange.resolve(
        preset: DashboardRangePreset.custom,
        now: day(2026, 4, 30),
        customFrom: day(2026, 1, 1),
        customTo: day(2026, 3, 31),
      );
      expect(range.from, day(2026, 1, 1));
      expect(range.to, day(2026, 3, 31));
    });
  });
}
