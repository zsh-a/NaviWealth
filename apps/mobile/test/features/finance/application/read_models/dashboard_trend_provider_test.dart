import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/finance/assets/physical/data/providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_granularity.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_trend_builder.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';

void main() {
  test('trend provider excludes non-security holding samples', () async {
    final manual = _asset('manual', AssetType.wealthProduct);
    final stock = _asset('stock', AssetType.stock);
    final service = _SampledService(
      {
        manual.id: _snapshot(manual.id, 100),
        stock.id: _snapshot(stock.id, 900),
      },
      [
        HoldingValuationIssue(
          assetId: manual.id,
          currency: 'USD',
          cause: HoldingValuationIssueCause.missingFx,
        ),
        HoldingValuationIssue(
          assetId: stock.id,
          currency: 'CNY',
          cause: HoldingValuationIssueCause.missingPrice,
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        dashboardBaseCurrencyProvider.overrideWith((_) => 'CNY'),
        dashboardManualAssetValuationsProvider.overrideWith(
          (_) => const AsyncValue.data(<ManualAssetValuation>[]),
        ),
        physicalAssetsListProvider.overrideWith(
          (_) => Stream.value(const <PhysicalAsset>[]),
        ),
        liabilitiesStreamProvider.overrideWith((_) => Stream.value(const [])),
        fxRatesStreamProvider.overrideWith(
          (_) => Stream<List<FxRate>>.value(const []),
        ),
        allAssetsStreamProvider.overrideWith(
          (_) => Stream.value([manual, stock]),
        ),
        holdingsSnapshotProvider.overrideWith((_) async => const {}),
        holdingServiceProvider.overrideWith((_) async => service),
      ],
    );
    addTearDown(container.dispose);
    final date = DateTime.utc(2026, 1, 1);
    final range = DashboardTimeRange(
      preset: DashboardRangePreset.custom,
      from: date,
      to: date,
      granularity: NetWorthGranularity.day,
    );
    final trendProvider = dashboardTrendProvider(range);
    final subscription = container.listen(trendProvider, (_, _) {});
    addTearDown(subscription.close);

    final trend = await container.read(trendProvider.future);

    expect(trend.points.single.assets.amount, Decimal.fromInt(900));
    expect(
      trend.points.single.componentQualities.keys,
      contains('security:stock'),
    );
    expect(
      trend.points.single.componentQualities.keys,
      isNot(contains('security:manual')),
    );
    expect(trend.points.single.quality, TrendPointQuality.estimated);
    expect(trend.currencyMismatches, isEmpty);
  });
}

class _SampledService implements SampledHoldingService {
  const _SampledService(this.snapshots, this.issues);

  final Map<String, HoldingSnapshot> snapshots;
  final List<HoldingValuationIssue> issues;

  @override
  Future<List<HoldingSample>> computeAtSamples(Iterable<DateTime> dates) async {
    return [
      for (final date in dates)
        HoldingSample(asOf: date.toUtc(), snapshots: snapshots, issues: issues),
    ];
  }

  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async =>
      snapshots;

  @override
  Future<void> invalidateFrom(DateTime from) async {}

  @override
  Future<List<Lot>> lotsAt(DateTime asOf) async => const [];

  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) async =>
      LotInventorySnapshot(ownerUserId: 'u-test', day: day, lots: const []);
}

Asset _asset(String id, AssetType type) => Asset(
  id: id,
  type: type,
  symbol: id,
  currency: 'CNY',
  name: id,
  sync: SyncMeta(
    ownerUserId: 'u-test',
    updatedAt: DateTime.utc(2026),
    updatedByDevice: 'dev-test',
    hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
  ),
);

HoldingSnapshot _snapshot(String id, int value) => HoldingSnapshot(
  assetId: id,
  quantity: Decimal.one,
  costBasisInAssetCurrency: Decimal.fromInt(value),
  marketValueInAssetCurrency: Decimal.fromInt(value),
  assetCurrency: 'CNY',
  costBasisInBase: Decimal.fromInt(value),
  marketValueInBase: Decimal.fromInt(value),
  unrealizedPnlInBase: Decimal.zero,
  weight: Decimal.one,
  baseCurrency: 'CNY',
  asOf: DateTime.utc(2026, 1, 1),
);
