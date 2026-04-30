import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/domain/amortization_entry.dart';
import '../../../data/domain/asset.dart';
import '../../../data/domain/liability.dart';
import '../../../data/repositories/providers.dart';
import '../../../domain/services/currency_converter.dart';
import '../../assets/physical/data/physical_asset.dart';
import '../../assets/physical/data/providers.dart';
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
final dashboardCurrencyConverterProvider =
    Provider<CurrencyConverter>((ref) {
  final rates = ref.watch(fxRatesStreamProvider).value ?? const [];
  return FxRateCurrencyConverter(InMemoryFxRateLookup(rates));
});

/// Currently selected time range for the trend chart. Defaults to 1 year —
/// long enough to surface savings momentum, short enough to keep daily
/// granularity readable without downsampling.
final dashboardSelectedRangeProvider =
    StateProvider<DashboardRangePreset>((ref) => DashboardRangePreset.y1);

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
/// category. Re-computes whenever any upstream stream emits.
final dashboardSnapshotProvider =
    Provider<AsyncValue<DashboardSnapshot>>((ref) {
  final manual = ref.watch(manualAssetsStreamProvider);
  final physical = ref.watch(physicalAssetsListProvider);
  final liab = ref.watch(liabilitiesStreamProvider);
  final converter = ref.watch(dashboardCurrencyConverterProvider);
  final base = ref.watch(dashboardBaseCurrencyProvider);

  if (manual.isLoading || physical.isLoading || liab.isLoading) {
    return const AsyncValue.loading();
  }
  final err = manual.error ?? physical.error ?? liab.error;
  if (err != null) {
    return AsyncValue.error(
      err,
      manual.stackTrace ?? physical.stackTrace ?? liab.stackTrace ?? StackTrace.current,
    );
  }
  final manualList = manual.value ?? const <Asset>[];
  final physicalList = physical.value ?? const <PhysicalAsset>[];
  final liabList = liab.value ?? const <Liability>[];

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
  );
  return AsyncValue.data(snapshot);
});

/// Schedule rows for every liability, keyed by liability id. The trend
/// builder needs the schedule so it can walk outstanding balance back
/// through time. We watch each schedule provider individually so a paid
/// installment in one loan reactively re-fires the whole map.
final dashboardLiabilitySchedulesProvider =
    Provider<Map<String, List<AmortizationEntry>>>((ref) {
  final liab = ref.watch(liabilitiesStreamProvider).value ?? const <Liability>[];
  final out = <String, List<AmortizationEntry>>{};
  for (final liability in liab) {
    final schedule = ref
            .watch(amortizationScheduleStreamProvider(liability.id))
            .value ??
        const <AmortizationEntry>[];
    out[liability.id] = schedule;
  }
  return out;
});

/// Net-worth trend timeseries for the dashboard line chart, scoped to the
/// selected [DashboardTimeRange]. Re-evaluates when the range changes or
/// any upstream stream emits.
final dashboardTrendProvider = Provider<AsyncValue<DashboardTrend>>((ref) {
  final manual = ref.watch(manualAssetsStreamProvider);
  final physical = ref.watch(physicalAssetsListProvider);
  final liab = ref.watch(liabilitiesStreamProvider);
  final converter = ref.watch(dashboardCurrencyConverterProvider);
  final base = ref.watch(dashboardBaseCurrencyProvider);
  final range = ref.watch(dashboardTimeRangeProvider);
  final schedules = ref.watch(dashboardLiabilitySchedulesProvider);

  if (manual.isLoading || physical.isLoading || liab.isLoading) {
    return const AsyncValue.loading();
  }
  final err = manual.error ?? physical.error ?? liab.error;
  if (err != null) {
    return AsyncValue.error(
      err,
      manual.stackTrace ?? physical.stackTrace ?? liab.stackTrace ?? StackTrace.current,
    );
  }
  final builder = DashboardTrendBuilder(
    converter: converter,
    baseCurrency: base,
  );
  final trend = builder.build(
    range: range,
    manualAssets: manual.value ?? const <Asset>[],
    physicalAssets: physical.value ?? const <PhysicalAsset>[],
    liabilities: liab.value ?? const <Liability>[],
    liabilitySchedules: schedules,
  );
  return AsyncValue.data(trend);
});
