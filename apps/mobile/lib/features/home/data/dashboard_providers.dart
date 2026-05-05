import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../data/db/app_database.dart';
import '../../../data/db/providers.dart';
import '../../../data/domain/amortization_entry.dart';
import '../../../data/domain/asset.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/liability.dart';
import '../../../data/domain/manual_asset_metadata.dart';
import '../../../data/repositories/providers.dart';
import '../../../domain/services/currency_converter.dart';
import '../../../domain/services/net_worth_service.dart';
import '../../../domain/values/money.dart';
import '../../assets/physical/data/physical_asset.dart';
import '../../assets/physical/data/providers.dart';
import '../../investment/data/providers.dart';
import '../../investment/domain/models/holding_snapshot.dart';
import '../../liabilities/data/providers.dart';
import '../../liabilities/domain/liability_summary.dart';
import '../../settings/data/base_currency_preference.dart';
import '../domain/dashboard_aggregator.dart';
import '../domain/dashboard_models.dart';
import '../domain/dashboard_time_range.dart';
import '../domain/dashboard_trend_builder.dart';

/// Base currency the dashboard renders totals in. Reads from the persisted
/// user preference (FIR-73) so changing the setting reactively recomputes
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
  final trend = ref.watch(dashboardTrendProvider).value;
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
/// FIR-51's [NetWorthService] expects an [FxRateLookup]-backed converter;
/// the dashboard reads every recorded rate from the local `fx_rates` table
/// (FIR-73) so manually entered rates flow into the snapshot, the
/// allocation pie, and the trend chart without a refresh.
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

final _dashboardPriceRowsProvider = StreamProvider.autoDispose<List<PriceRow>>((
  ref,
) async* {
  final db = await ref.watch(appDatabaseProvider.future);
  final query = db.select(db.prices)..where((t) => t.deletedAt.isNull());
  yield* query.watch();
});

/// Historical cash-account balances derived from the postings ledger.
///
/// Keyed by `accountId`, each value is a chronologically ordered list of
/// [ManualAssetValuePoint]s representing the running balance after every
/// posting date.  The dashboard snapshot uses the last point per account;
/// the trend builder walks the full series via [ManualAssetValuation.valueAt].
final _cashPostingHistoryProvider =
    StreamProvider.autoDispose<Map<String, List<ManualAssetValuePoint>>>((
      ref,
    ) async* {
      // Collect account IDs from cash assets' metadata. The link between a
      // cash asset and its postings is through CashMetadata.accountId stored
      // in assets.metadata_json — not through assets.id.
      final cashAccountIds = <String>{};
      final assets = await ref.watch(manualAssetsStreamProvider.future);
      for (final a in assets) {
        if (a.type == AssetType.cash) {
          final meta = ManualAssetMetadata.decode(a.metadataJson);
          if (meta?.accountId case final id?) cashAccountIds.add(id);
        }
      }
      if (cashAccountIds.isEmpty) {
        yield const {};
        return;
      }

      final db = await ref.watch(appDatabaseProvider.future);
      final je = db.journalEntries;
      final p = db.postings;
      final query = db.select(p).join([
        innerJoin(je, je.id.equalsExp(p.journalEntryId)),
      ])
        ..where(p.deletedAt.isNull())
        ..where(je.deletedAt.isNull())
        ..where(p.accountId.isIn(cashAccountIds))
        ..addColumns([je.date])
        ..orderBy([
          OrderingTerm.asc(p.accountId),
          OrderingTerm.asc(je.date),
        ]);
      yield* query.watch().map((rows) {
        final raw = <String, List<(DateTime, Decimal)>>{};
        for (final row in rows) {
          final posting = row.readTable(p);
          final date = row.read(je.date)!;
          raw
              .putIfAbsent(posting.accountId, () => [])
              .add((date, posting.units));
        }
        return {
          for (final entry in raw.entries)
            entry.key: _runningBalance(entry.value),
        };
      });
    });

List<ManualAssetValuePoint> _runningBalance(
  List<(DateTime date, Decimal delta)> rows,
) {
  final out = <ManualAssetValuePoint>[];
  var cumulative = Decimal.zero;
  for (final (date, delta) in rows) {
    cumulative += delta;
    out.add(ManualAssetValuePoint(observedOn: _floorToDay(date), value: cumulative));
  }
  return out;
}

final dashboardManualAssetValuationsProvider =
    Provider<AsyncValue<List<ManualAssetValuation>>>((ref) {
      final manual = ref.watch(manualAssetsStreamProvider);
      if (manual.isLoading) return const AsyncValue.loading();
      if (manual.hasError) {
        return AsyncValue.error(
          manual.error!,
          manual.stackTrace ?? StackTrace.current,
        );
      }
      final manualList = manual.value ?? const <Asset>[];
      if (manualList.isEmpty) {
        return const AsyncValue.data(<ManualAssetValuation>[]);
      }

      final cashHistory = ref.watch(_cashPostingHistoryProvider);
      final prices = ref.watch(_dashboardPriceRowsProvider);
      if (cashHistory.isLoading || prices.isLoading) {
        return const AsyncValue.loading();
      }
      if (cashHistory.hasError) {
        return AsyncValue.error(
          cashHistory.error!,
          cashHistory.stackTrace ?? StackTrace.current,
        );
      }
      if (prices.hasError) {
        return AsyncValue.error(
          prices.error!,
          prices.stackTrace ?? StackTrace.current,
        );
      }
      return AsyncValue.data(
        _buildManualAssetValuations(
          manualAssets: manualList,
          priceRows: prices.value ?? const <PriceRow>[],
          cashHistory: cashHistory.value ?? const {},
        ),
      );
    });

/// Live snapshot of asset / liability allocations grouped by big-bucket
/// category. Re-computes whenever any upstream stream emits — including
/// the postings-derived [holdingsSnapshotProvider], so a newly recorded
/// trade flows straight into the totals without manual invalidation.
final dashboardSnapshotProvider = Provider<AsyncValue<DashboardSnapshot>>((
  ref,
) {
  final manualValuations = ref.watch(dashboardManualAssetValuationsProvider);
  final physical = ref.watch(physicalAssetsListProvider);
  final liab = ref.watch(liabilitiesStreamProvider);
  final assets = ref.watch(allAssetsStreamProvider);
  final holdings = ref.watch(holdingsSnapshotProvider);
  final converter = ref.watch(dashboardCurrencyConverterProvider);
  final base = ref.watch(dashboardBaseCurrencyProvider);

  if (manualValuations.isLoading || physical.isLoading || liab.isLoading) {
    return const AsyncValue.loading();
  }
  final err = manualValuations.error ?? physical.error ?? liab.error;
  if (err != null) {
    return AsyncValue.error(
      err,
      manualValuations.stackTrace ??
          physical.stackTrace ??
          liab.stackTrace ??
          StackTrace.current,
    );
  }
  final manualList = manualValuations.value ?? const <ManualAssetValuation>[];
  final physicalList = physical.value ?? const <PhysicalAsset>[];
  final liabList = liab.value ?? const <Liability>[];
  final securities = _buildSecurityHoldings(
    holdingsByAsset: holdings.value ?? const {},
    assets: assets.value ?? const [],
  );

  final summaries = <LiabilitySummary>[];
  for (final liability in liabList) {
    final summary = ref.watch(liabilitySummaryProvider(liability.id)).value;
    if (summary != null) summaries.add(summary);
  }

  final aggregator = DashboardAggregator(
    converter: converter,
    baseCurrency: base,
    asOf: DateTime.now(),
  );
  final snapshot = aggregator.aggregate(
    manualAssets: manualList,
    physicalAssets: physicalList,
    liabilities: liabList,
    liabilitySummaries: summaries,
    securitiesHoldings: securities,
  );
  return AsyncValue.data(snapshot);
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

/// Build historical price series for securities so the trend builder can
/// look up per-date prices instead of using the current snapshot value.
Map<String, List<ManualAssetValuePoint>> _buildSecurityPriceHistory({
  required List<Asset> assets,
  required List<PriceRow> priceRows,
}) {
  if (priceRows.isEmpty || assets.isEmpty) return const {};
  final pricesByUnit = <String, List<PriceRow>>{};
  for (final row in priceRows) {
    pricesByUnit.putIfAbsent(row.unit, () => <PriceRow>[]).add(row);
  }
  final out = <String, List<ManualAssetValuePoint>>{};
  for (final asset in assets) {
    if (!kSecuritiesAssetTypes.contains(asset.type)) continue;
    final rows =
        (pricesByUnit[asset.id] ?? const <PriceRow>[])
            .where((row) => row.quoteCurrency == asset.currency)
            .toList(growable: false)
          ..sort((a, b) => a.observedOn.compareTo(b.observedOn));
    if (rows.isEmpty) continue;
    out[asset.id] = [
      for (final row in rows)
        ManualAssetValuePoint(observedOn: _floorToDay(row.observedOn), value: row.perUnit),
    ];
  }
  return out;
}

/// Floor a timestamp to the start of its UTC day. Trend sample dates are
/// all at midnight UTC; observations with an intra-day time component
/// (e.g. `12:25:33`) would fall *after* the sample date and be invisible
/// to [ManualAssetValuation.valueAt].
DateTime _floorToDay(DateTime d) {
  final u = d.toUtc();
  return DateTime.utc(u.year, u.month, u.day);
}

List<ManualAssetValuation> _buildManualAssetValuations({
  required List<Asset> manualAssets,
  required List<PriceRow> priceRows,
  required Map<String, List<ManualAssetValuePoint>> cashHistory,
}) {
  if (manualAssets.isEmpty) return const [];
  final pricesByUnit = <String, List<PriceRow>>{};
  for (final row in priceRows) {
    pricesByUnit.putIfAbsent(row.unit, () => <PriceRow>[]).add(row);
  }

  final out = <ManualAssetValuation>[];
  final seenCashAccounts = <String>{};
  for (final asset in manualAssets) {
    if (asset.type == AssetType.cash) {
      final meta = ManualAssetMetadata.decode(asset.metadataJson);
      final accountId = meta?.accountId;
      // Each ledger account has at most one cash asset (double-entry
      // invariant enforced by the create flow). Skip duplicates keyed by
      // accountId to avoid double-counting. When accountId is null the
      // metadata is missing — fall through to the price-row lookup.
      if (accountId != null && !seenCashAccounts.add(accountId)) continue;

      // 1. Prefer posting-derived running balance (most accurate).
      if (accountId != null) {
        final historyObs = cashHistory[accountId];
        if (historyObs != null && historyObs.isNotEmpty) {
          out.add(
            ManualAssetValuation(asset: asset, observations: historyObs),
          );
          continue;
        }
      }

      // 2. Fall back to price-row observations (created by
      //    _recordValuation when the cash asset was first set up).
      final assetPriceRows =
          (pricesByUnit[asset.id] ?? const <PriceRow>[])
              .where((row) => row.quoteCurrency == asset.currency)
              .toList(growable: false)
            ..sort((a, b) => a.observedOn.compareTo(b.observedOn));
      if (assetPriceRows.isNotEmpty) {
        out.add(
          ManualAssetValuation(
            asset: asset,
            observations: [
              for (final row in assetPriceRows)
                ManualAssetValuePoint(
                  observedOn: _floorToDay(row.observedOn),
                  value: row.perUnit,
                ),
            ],
          ),
        );
        continue;
      }

      // 3. Last resort: zero-value stub so the row appears in the
      //    snapshot even before any balance has been recorded.
      out.add(
        ManualAssetValuation(
          asset: asset,
          observations: [
            ManualAssetValuePoint(
              observedOn: _floorToDay(asset.sync.updatedAt),
              value: Decimal.zero,
            ),
          ],
        ),
      );
      continue;
    }
    // Non-cash manual assets: use price-row observations.
    final rows =
        (pricesByUnit[asset.id] ?? const <PriceRow>[])
            .where((row) => row.quoteCurrency == asset.currency)
            .toList(growable: false)
          ..sort((a, b) => a.observedOn.compareTo(b.observedOn));
    if (rows.isNotEmpty) {
      out.add(
        ManualAssetValuation(
          asset: asset,
          observations: [
            for (final row in rows)
              ManualAssetValuePoint(
                observedOn: _floorToDay(row.observedOn),
                value: row.perUnit,
              ),
          ],
        ),
      );
    }
  }
  return List.unmodifiable(out);
}

Future<List<ManualAssetValuation>> _manualAssetValuationsForHeader(
  Ref ref,
) async {
  final async = ref.watch(dashboardManualAssetValuationsProvider);
  if (async.hasValue) {
    return async.value ?? const <ManualAssetValuation>[];
  }
  if (async.hasError) {
    Error.throwWithStackTrace(
      async.error!,
      async.stackTrace ?? StackTrace.current,
    );
  }

  final manualAssets = await ref.watch(manualAssetsStreamProvider.future);
  if (manualAssets.isEmpty) return const <ManualAssetValuation>[];
  final cashHistory =
      await ref.watch(_cashPostingHistoryProvider.future);
  final priceRows = await ref.watch(_dashboardPriceRowsProvider.future);
  return _buildManualAssetValuations(
    manualAssets: manualAssets,
    priceRows: priceRows,
    cashHistory: cashHistory,
  );
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

/// Net-worth trend timeseries for the dashboard line chart, scoped to the
/// selected [DashboardTimeRange]. Re-evaluates when the range changes or
/// any upstream stream emits.
final dashboardTrendProvider = Provider<AsyncValue<DashboardTrend>>((ref) {
  final manualValuations = ref.watch(dashboardManualAssetValuationsProvider);
  final physical = ref.watch(physicalAssetsListProvider);
  final liab = ref.watch(liabilitiesStreamProvider);
  final converter = ref.watch(dashboardCurrencyConverterProvider);
  final base = ref.watch(dashboardBaseCurrencyProvider);
  final range = ref.watch(dashboardTimeRangeProvider);
  final schedules = ref.watch(dashboardLiabilitySchedulesProvider);
  final holdings = ref.watch(holdingsSnapshotProvider);
  final assets = ref.watch(allAssetsStreamProvider);
  final prices = ref.watch(_dashboardPriceRowsProvider);

  if (manualValuations.isLoading || physical.isLoading || liab.isLoading) {
    return const AsyncValue.loading();
  }
  final err = manualValuations.error ?? physical.error ?? liab.error;
  if (err != null) {
    return AsyncValue.error(
      err,
      manualValuations.stackTrace ??
          physical.stackTrace ??
          liab.stackTrace ??
          StackTrace.current,
    );
  }
  final securities = _buildSecurityHoldings(
    holdingsByAsset: holdings.value ?? const {},
    assets: assets.value ?? const [],
  );
  final securityPrices = _buildSecurityPriceHistory(
    assets: assets.value ?? const [],
    priceRows: prices.value ?? const [],
  );
  final builder = DashboardTrendBuilder(
    converter: converter,
    baseCurrency: base,
  );
  final trend = builder.build(
    range: range,
    manualAssets: manualValuations.value ?? const <ManualAssetValuation>[],
    physicalAssets: physical.value ?? const <PhysicalAsset>[],
    liabilities: liab.value ?? const <Liability>[],
    liabilitySchedules: schedules,
    securitiesHoldings: securities,
    securityPrices: securityPrices,
  );
  return AsyncValue.data(trend);
});

/// Header-strip metrics that complement the hero net-worth number with
/// signed deltas: today's change in base currency, MTD change as a ratio,
/// and YTD return as an annualized rate.
///
/// `dailyChange` is `nw(today) − nw(yesterday)` in base currency.
///
/// `monthlyChangePct` is `(nw(today) − nw(monthStart)) / nw(monthStart)`
/// — a simple percent change suitable for short windows where path-
/// dependent flows are noise. `null` when `nw(monthStart)` is zero.
///
/// `ytdChangePct` is the postings-derived money-weighted return. It uses
/// XIRR when the ledger has a solvable set of cash flows, and falls back to
/// cumulative absolute return for degenerate windows.
@immutable
class DashboardHeaderMetrics {
  const DashboardHeaderMetrics({
    required this.baseCurrency,
    required this.dailyChange,
    required this.monthlyChange,
    required this.monthlyChangePct,
    required this.ytdChange,
    required this.ytdChangePct,
  });

  final String baseCurrency;
  final Money dailyChange;
  final Money monthlyChange;
  final double? monthlyChangePct;
  final Money ytdChange;
  final double? ytdChangePct;
}

final dashboardHeaderMetricsProvider = FutureProvider<DashboardHeaderMetrics>((
  ref,
) async {
  // Establish the same postings-derived invalidation edge as the dashboard
  // snapshot. The return service does the historical XIRR query below.
  ref.watch(holdingsSnapshotProvider);
  final manualList = await _manualAssetValuationsForHeader(ref);
  final physicalList = await ref.watch(physicalAssetsListProvider.future);
  final liabList = await ref.watch(liabilitiesStreamProvider.future);
  final converter = ref.watch(dashboardCurrencyConverterProvider);
  final base = ref.watch(dashboardBaseCurrencyProvider);
  final schedules = ref.watch(dashboardLiabilitySchedulesProvider);

  final builder = DashboardTrendBuilder(
    converter: converter,
    baseCurrency: base,
  );

  Money nwAt(DateTime date) {
    final range = DashboardTimeRange(
      preset: DashboardRangePreset.custom,
      from: date,
      to: date,
      granularity: NetWorthGranularity.day,
    );
    final trend = builder.build(
      range: range,
      manualAssets: manualList,
      physicalAssets: physicalList,
      liabilities: liabList,
      liabilitySchedules: schedules,
    );
    return trend.points.isEmpty
        ? Money.zero(base)
        : trend.points.first.netWorth;
  }

  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final monthStart = DateTime.utc(today.year, today.month, 1);
  final yearStart = DateTime.utc(today.year, 1, 1);

  final nwToday = nwAt(today);
  final nwYesterday = nwAt(yesterday);
  final nwMonthStart = nwAt(monthStart);
  final nwYearStart = nwAt(yearStart);

  double? pctChange(Money current, Money baseline) {
    if (baseline.amount.sign == 0) {
      return current.amount.sign == 0 ? null : double.infinity;
    }
    final ratio = (current.amount - baseline.amount) / baseline.amount;
    return ratio.toDecimal(scaleOnInfinitePrecision: 8).toDouble();
  }

  final ytdRatio = await _ytdRatio(ref, from: yearStart, to: today);

  return DashboardHeaderMetrics(
    baseCurrency: base,
    dailyChange: nwToday - nwYesterday,
    monthlyChange: nwToday - nwMonthStart,
    monthlyChangePct: pctChange(nwToday, nwMonthStart),
    ytdChange: nwToday - nwYearStart,
    ytdChangePct: ytdRatio,
  );
});

Future<double?> _ytdRatio(
  Ref ref, {
  required DateTime from,
  required DateTime to,
}) async {
  final service = await ref.watch(portfolioReturnServiceProvider.future);
  final result = await service.compute(from: from, to: to);
  return result.displayReturn;
}
