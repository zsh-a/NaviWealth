import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/domain/services/net_worth_service.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/home/domain/dashboard_aggregator.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/features/home/domain/dashboard_trend_builder.dart';

class _MapConverter implements CurrencyConverter {
  const _MapConverter(this.rates);

  final Map<String, Decimal> rates;

  @override
  Money convert(Money amount, String to, {DateTime? on}) {
    if (amount.currency == to) return amount;
    final rate = rates['${amount.currency}:$to'];
    if (rate == null) throw FxRateNotFoundError(amount.currency, to, on);
    return Money(amount.amount * rate, to);
  }
}

void main() {
  test('DashboardAggregator includes cash from manual valuation prices', () {
    final cash = _manualValuation(
      _asset(id: 'cash-1', type: AssetType.cash, currency: 'CNY'),
      value: '1234',
      observedOn: DateTime.utc(2026, 1, 1),
    );

    final snapshot =
        DashboardAggregator(
          converter: const _MapConverter({}),
          baseCurrency: 'CNY',
          asOf: DateTime.utc(2026, 5, 1),
        ).aggregate(
          manualAssets: [cash],
          physicalAssets: const [],
          liabilities: const [],
          liabilitySummaries: const [],
        );

    expect(snapshot.totalAssets.amount, Decimal.parse('1234'));
    expect(snapshot.netWorth.amount, Decimal.parse('1234'));
    expect(snapshot.allocations.single.category, AssetCategory.cash);
    expect(snapshot.allocations.single.items.single.nativeCurrency, 'CNY');
  });

  test('DashboardTrendBuilder carries manual asset values through samples', () {
    final cash = ManualAssetValuation(
      asset: _asset(id: 'cash-1', type: AssetType.cash, currency: 'CNY'),
      observations: [
        ManualAssetValuePoint(
          observedOn: DateTime.utc(2026, 1, 1),
          value: Decimal.parse('100'),
        ),
        ManualAssetValuePoint(
          observedOn: DateTime.utc(2026, 1, 3),
          value: Decimal.parse('250'),
        ),
      ],
    );

    final trend =
        DashboardTrendBuilder(
          converter: const _MapConverter({}),
          baseCurrency: 'CNY',
        ).build(
          range: DashboardTimeRange(
            preset: DashboardRangePreset.custom,
            from: DateTime.utc(2026, 1, 1),
            to: DateTime.utc(2026, 1, 3),
            granularity: NetWorthGranularity.day,
          ),
          manualAssets: [cash],
          physicalAssets: const [],
          liabilities: const [],
          liabilitySchedules: const {},
        );

    expect(trend.points.map((p) => p.assets.amount), [
      Decimal.parse('100'),
      Decimal.parse('100'),
      Decimal.parse('250'),
    ]);
  });

  test('manual assets missing FX are reported instead of silently counted', () {
    final usdCash = _manualValuation(
      _asset(id: 'cash-usd', type: AssetType.cash, currency: 'USD'),
      value: '100',
      observedOn: DateTime.utc(2026, 1, 1),
    );

    final snapshot =
        DashboardAggregator(
          converter: const _MapConverter({}),
          baseCurrency: 'CNY',
          asOf: DateTime.utc(2026, 5, 1),
        ).aggregate(
          manualAssets: [usdCash],
          physicalAssets: const [],
          liabilities: const [],
          liabilitySummaries: const [],
        );

    expect(snapshot.totalAssets.amount, Decimal.zero);
    expect(snapshot.currencyMismatches.single.id, 'cash-usd');
    expect(snapshot.currencyMismatches.single.currency, 'USD');
  });
}

ManualAssetValuation _manualValuation(
  Asset asset, {
  required String value,
  required DateTime observedOn,
}) {
  return ManualAssetValuation(
    asset: asset,
    observations: [
      ManualAssetValuePoint(
        observedOn: observedOn,
        value: Decimal.parse(value),
      ),
    ],
  );
}

Asset _asset({
  required String id,
  required AssetType type,
  required String currency,
}) {
  return Asset(
    id: id,
    type: type,
    symbol: currency,
    currency: currency,
    name: id,
    sync: SyncMeta(
      ownerUserId: 'u-test',
      updatedAt: DateTime.utc(2026),
      updatedByDevice: 'dev-test',
      hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
    ),
  );
}
