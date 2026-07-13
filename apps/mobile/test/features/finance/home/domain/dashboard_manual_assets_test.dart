import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/manual_asset_metadata.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_aggregator.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_granularity.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_trend_builder.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/market/domain/price_confidence.dart';

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

  test('manual lifecycle distinguishes unheld from active missing value', () {
    final deposit = ManualAssetValuation(
      asset: _asset(
        id: 'deposit-1',
        type: AssetType.bankDepositTerm,
        currency: 'CNY',
        metadataJson: DepositMetadata(
          accountId: 'bank-1',
          principal: Decimal.parse('1000'),
          interestRate: Decimal.parse('0.02'),
          startDate: DateTime.utc(2026, 1, 2),
        ).encode(),
      ),
      observations: [
        ManualAssetValuePoint(
          observedOn: DateTime.utc(2026, 1, 3),
          value: Decimal.parse('1000'),
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
            to: DateTime.utc(2026, 1, 4),
            granularity: NetWorthGranularity.day,
          ),
          manualAssets: [deposit],
          physicalAssets: const [],
          liabilities: const [],
          liabilitySchedules: const {},
        );

    expect(
      trend.points[0].componentQualities['manual:deposit-1'],
      TrendComponentQuality.unheld,
    );
    expect(trend.points[1].quality, TrendPointQuality.incomplete);
    expect(
      trend.points[1].componentQualities['manual:deposit-1'],
      TrendComponentQuality.missing,
    );
    expect(trend.latestCompleteSegment.map((point) => point.asOf), [
      DateTime.utc(2026, 1, 3),
      DateTime.utc(2026, 1, 4),
    ]);
  });

  test('latest complete segment does not bridge an estimated gap', () {
    final template = HoldingSnapshot(
      assetId: 'AAPL',
      quantity: Decimal.one,
      costBasisInAssetCurrency: Decimal.parse('100'),
      marketValueInAssetCurrency: Decimal.parse('100'),
      assetCurrency: 'USD',
      costBasisInBase: Decimal.parse('100'),
      marketValueInBase: Decimal.parse('100'),
      unrealizedPnlInBase: Decimal.zero,
      weight: Decimal.one,
      baseCurrency: 'USD',
      asOf: DateTime.utc(2026, 1, 1),
    );
    final trend =
        DashboardTrendBuilder(
          converter: const _MapConverter({}),
          baseCurrency: 'USD',
        ).build(
          range: DashboardTimeRange(
            preset: DashboardRangePreset.custom,
            from: DateTime.utc(2026, 1, 1),
            to: DateTime.utc(2026, 1, 3),
            granularity: NetWorthGranularity.day,
          ),
          manualAssets: const [],
          physicalAssets: const [],
          liabilities: const [],
          liabilitySchedules: const {},
          securitySamples: [
            _securitySample(template, DateTime.utc(2026, 1, 1), '100'),
            _securitySample(
              template,
              DateTime.utc(2026, 1, 2),
              '100',
              estimated: true,
            ),
            _securitySample(template, DateTime.utc(2026, 1, 3), '110'),
          ],
        );

    expect(trend.latestCompleteSegment, hasLength(1));
    expect(trend.latestCompleteSegment.single.asOf, DateTime.utc(2026, 1, 3));

    final endingInEstimate = DashboardTrend(
      range: trend.range,
      baseCurrency: trend.baseCurrency,
      points: trend.points.take(2).toList(growable: false),
    );
    expect(endingInEstimate.latestEstimatedSegment, hasLength(1));
    expect(
      endingInEstimate.latestEstimatedSegment.single.asOf,
      DateTime.utc(2026, 1, 2),
    );
  });

  test('manual asset without lifecycle evidence is incomplete, not unheld', () {
    final wealth = ManualAssetValuation(
      asset: _asset(
        id: 'wealth-unknown',
        type: AssetType.wealthProduct,
        currency: 'CNY',
      ),
      observations: const [],
    );
    final trend =
        DashboardTrendBuilder(
          converter: const _MapConverter({}),
          baseCurrency: 'CNY',
        ).build(
          range: DashboardTimeRange(
            preset: DashboardRangePreset.custom,
            from: DateTime.utc(2026, 1, 1),
            to: DateTime.utc(2026, 1, 1),
            granularity: NetWorthGranularity.day,
          ),
          manualAssets: [wealth],
          physicalAssets: const [],
          liabilities: const [],
          liabilitySchedules: const {},
        );

    expect(trend.points.single.quality, TrendPointQuality.incomplete);
    expect(
      trend.points.single.componentQualities['manual:wealth-unknown'],
      TrendComponentQuality.missing,
    );
  });

  test('missing FX marks the trend point incomplete', () {
    final usdCash = _manualValuation(
      _asset(id: 'cash-usd', type: AssetType.cash, currency: 'USD'),
      value: '100',
      observedOn: DateTime.utc(2026, 1, 1),
    );
    final trend =
        DashboardTrendBuilder(
          converter: const _MapConverter({}),
          baseCurrency: 'CNY',
        ).build(
          range: DashboardTimeRange(
            preset: DashboardRangePreset.custom,
            from: DateTime.utc(2026, 1, 1),
            to: DateTime.utc(2026, 1, 1),
            granularity: NetWorthGranularity.day,
          ),
          manualAssets: [usdCash],
          physicalAssets: const [],
          liabilities: const [],
          liabilitySchedules: const {},
        );

    expect(trend.points.single.quality, TrendPointQuality.incomplete);
    expect(trend.points.single.assets.amount, Decimal.zero);
    expect(trend.currencyMismatches.single.currency, 'USD');
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

  test('securities use historical prices for trend when available', () {
    final snapshot = HoldingSnapshot(
      assetId: 'AAPL',
      quantity: Decimal.fromInt(10),
      costBasisInAssetCurrency: Decimal.parse('1000'),
      marketValueInAssetCurrency: Decimal.parse('2000'),
      assetCurrency: 'USD',
      costBasisInBase: Decimal.parse('1000'),
      marketValueInBase: Decimal.parse('2000'),
      unrealizedPnlInBase: Decimal.parse('1000'),
      weight: Decimal.one,
      baseCurrency: 'USD',
      asOf: DateTime.utc(2026, 5, 1),
    );

    final trend =
        DashboardTrendBuilder(
          converter: const _MapConverter({}),
          baseCurrency: 'USD',
        ).build(
          range: DashboardTimeRange(
            preset: DashboardRangePreset.custom,
            from: DateTime.utc(2026, 1, 1),
            to: DateTime.utc(2026, 1, 5),
            granularity: NetWorthGranularity.day,
          ),
          manualAssets: const [],
          physicalAssets: const [],
          liabilities: const [],
          liabilitySchedules: const {},
          securitySamples: [
            _securitySample(snapshot, DateTime.utc(2026, 1, 1), '1000'),
            _securitySample(snapshot, DateTime.utc(2026, 1, 2), '1000'),
            _securitySample(snapshot, DateTime.utc(2026, 1, 3), '1500'),
            _securitySample(snapshot, DateTime.utc(2026, 1, 4), '1500'),
            _securitySample(snapshot, DateTime.utc(2026, 1, 5), '2000'),
          ],
        );

    // Jan 1: $100×10=$1000, Jan 2: $100×10=$1000, Jan 3: $150×10=$1500,
    // Jan 4: $150×10=$1500, Jan 5: $200×10=$2000
    expect(trend.points.map((p) => p.assets.amount), [
      Decimal.parse('1000'),
      Decimal.parse('1000'),
      Decimal.parse('1500'),
      Decimal.parse('1500'),
      Decimal.parse('2000'),
    ]);
  });

  test('securities use estimated cost basis without historical prices', () {
    final snapshot = HoldingSnapshot(
      assetId: 'TSLA',
      quantity: Decimal.fromInt(5),
      costBasisInAssetCurrency: Decimal.parse('500'),
      marketValueInAssetCurrency: Decimal.parse('1000'),
      assetCurrency: 'USD',
      costBasisInBase: Decimal.parse('500'),
      marketValueInBase: Decimal.parse('1000'),
      unrealizedPnlInBase: Decimal.parse('500'),
      weight: Decimal.one,
      baseCurrency: 'USD',
      asOf: DateTime.utc(2026, 5, 1),
    );

    final trend =
        DashboardTrendBuilder(
          converter: const _MapConverter({}),
          baseCurrency: 'USD',
        ).build(
          range: DashboardTimeRange(
            preset: DashboardRangePreset.custom,
            from: DateTime.utc(2026, 1, 1),
            to: DateTime.utc(2026, 1, 3),
            granularity: NetWorthGranularity.day,
          ),
          manualAssets: const [],
          physicalAssets: const [],
          liabilities: const [],
          liabilitySchedules: const {},
          securitySamples: [
            for (var day = 1; day <= 3; day++)
              _securitySample(
                snapshot,
                DateTime.utc(2026, 1, day),
                '500',
                estimated: true,
              ),
          ],
        );

    // No quote: the historical position is valued at cost and tagged estimate.
    expect(trend.points.map((p) => p.assets.amount), [
      Decimal.parse('500'),
      Decimal.parse('500'),
      Decimal.parse('500'),
    ]);
    expect(
      trend.points.map((p) => p.quality),
      everyElement(TrendPointQuality.estimated),
    );
  });

  test('securities isolate cost estimates before first market price', () {
    final snapshot = HoldingSnapshot(
      assetId: 'NVDA',
      quantity: Decimal.fromInt(10),
      costBasisInAssetCurrency: Decimal.parse('1000'),
      marketValueInAssetCurrency: Decimal.parse('5000'),
      assetCurrency: 'USD',
      costBasisInBase: Decimal.parse('1000'),
      marketValueInBase: Decimal.parse('5000'),
      unrealizedPnlInBase: Decimal.parse('4000'),
      weight: Decimal.one,
      baseCurrency: 'USD',
      asOf: DateTime.utc(2026, 5, 1),
    );

    final trend =
        DashboardTrendBuilder(
          converter: const _MapConverter({}),
          baseCurrency: 'USD',
        ).build(
          range: DashboardTimeRange(
            preset: DashboardRangePreset.custom,
            from: DateTime.utc(2026, 1, 1),
            to: DateTime.utc(2026, 1, 5),
            granularity: NetWorthGranularity.day,
          ),
          manualAssets: const [],
          physicalAssets: const [],
          liabilities: const [],
          liabilitySchedules: const {},
          securitySamples: [
            _securitySample(
              snapshot,
              DateTime.utc(2026, 1, 1),
              '1000',
              estimated: true,
            ),
            _securitySample(
              snapshot,
              DateTime.utc(2026, 1, 2),
              '1000',
              estimated: true,
            ),
            _securitySample(snapshot, DateTime.utc(2026, 1, 3), '2000'),
            _securitySample(snapshot, DateTime.utc(2026, 1, 4), '2000'),
            _securitySample(snapshot, DateTime.utc(2026, 1, 5), '3000'),
          ],
        );

    // Jan 1-2 use cost basis rather than zero. The cost→quote transition is
    // excluded from the reliable segment because the quality boundary is
    // explicit.
    expect(trend.points.map((p) => p.assets.amount), [
      Decimal.parse('1000'),
      Decimal.parse('1000'),
      Decimal.parse('2000'),
      Decimal.parse('2000'),
      Decimal.parse('3000'),
    ]);
    expect(trend.latestCompleteSegment.map((p) => p.asOf), [
      DateTime.utc(2026, 1, 3),
      DateTime.utc(2026, 1, 4),
      DateTime.utc(2026, 1, 5),
    ]);
  });
}

HoldingSample _securitySample(
  HoldingSnapshot template,
  DateTime asOf,
  String marketValue, {
  bool estimated = false,
}) {
  final value = Decimal.parse(marketValue);
  final snapshot = HoldingSnapshot(
    assetId: template.assetId,
    quantity: template.quantity,
    costBasisInAssetCurrency: template.costBasisInAssetCurrency,
    marketValueInAssetCurrency: value,
    assetCurrency: template.assetCurrency,
    costBasisInBase: template.costBasisInBase,
    marketValueInBase: value,
    unrealizedPnlInBase: value - template.costBasisInBase,
    weight: Decimal.one,
    baseCurrency: template.baseCurrency,
    asOf: asOf,
    priceConfidence: estimated
        ? PriceConfidence.estimated
        : PriceConfidence.dailyClose,
    priceSource: estimated ? 'cost_basis' : 'test_quote',
    priceAsOf: asOf,
  );
  return HoldingSample(
    asOf: asOf,
    snapshots: {template.assetId: snapshot},
    issues: estimated
        ? [
            HoldingValuationIssue(
              assetId: template.assetId,
              currency: template.assetCurrency,
              cause: HoldingValuationIssueCause.missingPrice,
            ),
          ]
        : const [],
  );
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
  String? metadataJson,
}) {
  return Asset(
    id: id,
    type: type,
    symbol: currency,
    currency: currency,
    name: id,
    metadataJson: metadataJson,
    sync: SyncMeta(
      ownerUserId: 'u-test',
      updatedAt: DateTime.utc(2026),
      updatedByDevice: 'dev-test',
      hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
    ),
  );
}
