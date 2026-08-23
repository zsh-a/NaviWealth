import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:naviwealth/core/async/isolate_runner.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/features/finance/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/finance/assets/physical/data/providers.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/amortization_entry.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/liability.dart';
import 'package:naviwealth/features/finance/domain/models/manual_asset_metadata.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_aggregator.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_granularity.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_time_range.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_trend_builder.dart';
import 'package:naviwealth/features/finance/investment/data/historical_holding_price_source.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';
import 'package:naviwealth/features/finance/liabilities/domain/liability_summary.dart';

part 'dashboard_header_metrics.dart';
part 'dashboard_manual_valuations.dart';

/// Base currency the dashboard renders totals in. Reads from the persisted
/// user preference so changing the setting reactively recomputes
/// every downstream allocation / trend point.
final dashboardBaseCurrencyProvider = Provider<String>((ref) {
  return ref.watch(baseCurrencyProvider);
});

/// Holdings excluded from the dashboard totals because no FX rate could
/// convert them to [dashboardBaseCurrencyProvider]. Aggregated across both
/// the snapshot (current allocation) and the trend (historical samples) so
/// the dashboard renders a single warning banner instead of forcing the
/// user to spot the discrepancy by eyeballing two charts.
final dashboardCurrencyMismatchesProvider = Provider<List<CurrencyMismatch>>((
  ref,
) {
  final snapshot = ref.watch(dashboardSnapshotProvider).value;
  final range = ref.watch(dashboardTimeRangeProvider);
  final trend = ref.watch(dashboardTrendProvider(range)).value;
  final seen = <String>{};
  final out = <CurrencyMismatch>[];
  for (final m in [
    ...?snapshot?.currencyMismatches,
    ...?trend?.currencyMismatches,
  ]) {
    if (seen.add(m.id)) out.add(m);
  }
  return List.unmodifiable(out);
});

/// Currency converter used for cross-currency conversion in the dashboard.
/// Dashboard aggregation expects an [FxRateLookup]-backed converter. It reads
/// every recorded rate from the local `fx_rates` table so manually entered
/// rates flow into the snapshot, the allocation pie, and the trend chart
/// without a refresh.
///
/// Same-currency conversions short-circuit, and callers (the aggregator +
/// trend builder) drop rows whose FX rate is missing while reporting them
/// via [DashboardSnapshot.currencyMismatches] / [DashboardTrend.currencyMismatches]
/// — so the dashboard renders correctly for single-currency portfolios and
/// degrades visibly (banner, not silent) when a foreign-currency holding
/// is missing its rate.
final dashboardCurrencyConverterProvider = Provider<CurrencyConverter>((ref) {
  final rates = ref.watch(fxRatesStreamProvider).value ?? const [];
  return FxRateCurrencyConverter(InMemoryFxRateLookup(rates));
});

/// Currently selected time range for the trend chart. Defaults to 1 year —
/// long enough to surface savings momentum, short enough to keep daily
/// granularity readable without downsampling.
final dashboardSelectedRangeProvider = StateProvider<DashboardRangePreset>(
  (ref) => DashboardRangePreset.y1,
);

/// Currently selected custom range — only applies when
/// [dashboardSelectedRangeProvider] is [DashboardRangePreset.custom].
final dashboardCustomRangeProvider =
    StateProvider<({DateTime from, DateTime to})?>((ref) => null);

/// Resolved [DashboardTimeRange] for the trend chart. Recomputes whenever
/// the selected preset (or the custom range) changes.
final dashboardTimeRangeProvider = Provider<DashboardTimeRange>((ref) {
  final preset = ref.watch(dashboardSelectedRangeProvider);
  final custom = ref.watch(dashboardCustomRangeProvider);
  return DashboardTimeRange.resolve(
    preset: preset,
    now: DateTime.now(),
    customFrom: custom?.from,
    customTo: custom?.to,
  );
});

/// Live snapshot of asset / liability allocations grouped by big-bucket
/// category. Re-computes whenever any upstream stream emits — including
/// the postings-derived [holdingsSnapshotProvider], so a newly recorded
/// trade flows straight into the totals without manual invalidation.
final dashboardSnapshotProvider = FutureProvider<DashboardSnapshot>((
  ref,
) async {
  final manualList = await _manualAssetValuationsForHeader(ref);
  final physical = ref.watch(physicalAssetsListProvider);
  final liab = ref.watch(liabilitiesStreamProvider);
  final assets = ref.watch(allAssetsStreamProvider);
  final holdings = ref.watch(holdingsSnapshotProvider);
  final rates = ref.watch(fxRatesStreamProvider);
  final base = ref.watch(dashboardBaseCurrencyProvider);

  final physicalList =
      physical.value ??
      await ref.watch(physicalAssetsListProvider.future) ??
      const <PhysicalAsset>[];
  final liabList =
      liab.value ??
      await ref.watch(liabilitiesStreamProvider.future) ??
      const <Liability>[];
  final assetList =
      assets.value ??
      await ref.watch(allAssetsStreamProvider.future) ??
      const <Asset>[];
  final holdingsByAsset =
      holdings.value ??
      await ref.watch(holdingsSnapshotProvider.future) ??
      const <String, HoldingSnapshot>{};
  final fxRows =
      rates.value ?? await ref.watch(fxRatesStreamProvider.future) ?? const [];
  final summaryMap = liabList.isEmpty
      ? const <String, LiabilitySummary>{}
      : await ref.watch(allLiabilitySummariesProvider.future);
  final securities = _buildSecurityHoldings(
    holdingsByAsset: holdingsByAsset,
    assets: assetList,
  );

  return runInIsolate(
    () => aggregateDashboard(
      baseCurrency: base,
      asOf: DateTime.now(),
      fxRates: fxRows,
      manualAssets: manualList,
      physicalAssets: dashboardPhysicalAssetsFrom(physicalList),
      liabilities: liabList,
      liabilitySummaries: summaryMap.values,
      securitiesHoldings: securities,
    ),
  );
});

/// Pair each priced holding with its asset row, dropping anything that
/// isn't a security (manual cash / deposits are already counted via
/// [manualAssetsStreamProvider] — folding them in twice would double the
/// total).
List<SecurityHolding> _buildSecurityHoldings({
  required Map<String, HoldingSnapshot> holdingsByAsset,
  required List<Asset> assets,
}) {
  if (holdingsByAsset.isEmpty) return const [];
  final byId = {for (final a in assets) a.id: a};
  final out = <SecurityHolding>[];
  for (final entry in holdingsByAsset.entries) {
    final asset = byId[entry.key];
    if (asset == null) continue;
    if (!kSecuritiesAssetTypes.contains(asset.type)) continue;
    out.add((asset: asset, snapshot: entry.value));
  }
  return out;
}

List<DashboardPhysicalAsset> dashboardPhysicalAssetsFrom(
  Iterable<PhysicalAsset> assets,
) {
  return [
    for (final asset in assets)
      DashboardPhysicalAsset(
        id: asset.id,
        name: asset.name,
        currency: asset.currency,
        type: asset.type,
        currentValuation: asset.currentValuation,
        purchaseDate: asset.purchaseDate,
        purchasePrice: asset.purchasePrice,
        lastValuationAt: asset.lastValuationAt,
        address: asset.address,
        autoDepreciation: asset.autoDepreciation,
        annualResidualRate: asset.annualResidualRate,
      ),
  ];
}

/// Schedule rows for every liability, keyed by liability id. The trend
/// builder needs the schedule so it can walk outstanding balance back
/// through time. We watch each schedule provider individually so a paid
/// installment in one loan reactively re-fires the whole map.
final dashboardLiabilitySchedulesProvider =
    Provider<Map<String, List<AmortizationEntry>>>((ref) {
      final liab =
          ref.watch(liabilitiesStreamProvider).value ?? const <Liability>[];
      final out = <String, List<AmortizationEntry>>{};
      for (final liability in liab) {
        final schedule =
            ref.watch(amortizationScheduleStreamProvider(liability.id)).value ??
            const <AmortizationEntry>[];
        out[liability.id] = schedule;
      }
      return out;
    });

Future<Map<String, List<AmortizationEntry>>> _liabilitySchedulesForTrend(
  Ref ref,
  List<Liability> liabilities,
) async {
  final out = <String, List<AmortizationEntry>>{};
  for (final liability in liabilities) {
    final schedule = ref.watch(
      amortizationScheduleStreamProvider(liability.id),
    );
    out[liability.id] =
        schedule.value ??
        await ref.watch(
          amortizationScheduleStreamProvider(liability.id).future,
        );
  }
  return out;
}

/// Net-worth trend timeseries for the dashboard line chart, scoped to the
/// selected [DashboardTimeRange]. Re-evaluates when the range changes or
/// any upstream stream emits.
final dashboardTrendProvider = FutureProvider.autoDispose
    .family<DashboardTrend, DashboardTimeRange>((ref, range) async {
      final manualList = await _manualAssetValuationsForHeader(ref);
      final physical = ref.watch(physicalAssetsListProvider);
      final liab = ref.watch(liabilitiesStreamProvider);
      final assets = ref.watch(allAssetsStreamProvider);
      final rates = ref.watch(fxRatesStreamProvider);
      final base = ref.watch(dashboardBaseCurrencyProvider);
      // Establish the postings invalidation edge while historical samples are
      // computed in one replay by HoldingService.
      ref.watch(holdingsSnapshotProvider);

      final physicalList =
          physical.value ??
          await ref.watch(physicalAssetsListProvider.future) ??
          const <PhysicalAsset>[];
      final liabList =
          liab.value ??
          await ref.watch(liabilitiesStreamProvider.future) ??
          const <Liability>[];
      final assetList =
          assets.value ??
          await ref.watch(allAssetsStreamProvider.future) ??
          const <Asset>[];
      final securityAssetIds = {
        for (final asset in assetList)
          if (kSecuritiesAssetTypes.contains(asset.type)) asset.id,
      };
      final schedules = await _liabilitySchedulesForTrend(ref, liabList);
      final fxRows =
          rates.value ??
          await ref.watch(fxRatesStreamProvider.future) ??
          const [];
      final service = await ref.watch(holdingServiceProvider.future);
      final sampleDates = dashboardTrendSampleDates(range);
      final sampleInstants = [
        for (final date in sampleDates) _endOfUtcDay(date),
      ];
      final rawSamples = service is RepriceableSampledHoldingService
          ? await service.computeAtSamplesWithPriceSource(
              sampleInstants,
              priceSource: await buildHistoricalHoldingPriceSource(
                market: await ref.watch(marketDataServiceProvider.future),
                current: await ref.watch(holdingPriceSourceProvider.future),
                assets: [
                  for (final asset in assetList)
                    if (securityAssetIds.contains(asset.id)) asset,
                ],
                from: range.from,
                to: _endOfUtcDay(range.to),
              ),
            )
          : await service.computeAtSamples(sampleInstants);
      final rawByInstant = {
        for (final sample in rawSamples) sample.asOf: sample,
      };
      final securitySamples = [
        for (var i = 0; i < sampleDates.length; i++)
          HoldingSample(
            asOf: sampleDates[i],
            snapshots: {
              for (final entry
                  in (rawByInstant[sampleInstants[i]]?.snapshots ??
                          const <String, HoldingSnapshot>{})
                      .entries)
                if (securityAssetIds.contains(entry.key))
                  entry.key: entry.value,
            },
            issues: [
              for (final issue
                  in rawByInstant[sampleInstants[i]]?.issues ??
                      const <HoldingValuationIssue>[])
                if (securityAssetIds.contains(issue.assetId)) issue,
            ],
          ),
      ];

      return runInIsolate(
        () => buildDashboardTrend(
          range: range,
          baseCurrency: base,
          fxRates: fxRows,
          manualAssets: manualList,
          physicalAssets: dashboardPhysicalAssetsFrom(physicalList),
          liabilities: liabList,
          liabilitySchedules: schedules,
          securitySamples: securitySamples,
        ),
      );
    });

DateTime _endOfUtcDay(DateTime date) {
  final utc = date.toUtc();
  return DateTime.utc(
    utc.year,
    utc.month,
    utc.day + 1,
  ).subtract(const Duration(microseconds: 1));
}
