import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/analytics/analytics_page.dart';
import 'package:naviwealth/features/finance/analytics/data/benchmark/benchmark_history_source.dart';
import 'package:naviwealth/features/finance/analytics/data/benchmark/benchmark_providers.dart';
import 'package:naviwealth/features/finance/analytics/data/providers.dart';
import 'package:naviwealth/features/finance/analytics/domain/benchmark/benchmark_comparison.dart';
import 'package:naviwealth/features/finance/analytics/domain/benchmark/benchmark_index.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/assets/physical/data/providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '_golden_setup.dart';

class _EmptyBenchmarkSource implements BenchmarkHistorySource {
  @override
  Future<List<TimeSeriesPoint>> seriesFor({
    required BenchmarkIndex index,
    required DateTime from,
    required DateTime to,
  }) async => const [];
}

class _EmptyHoldingService implements HoldingService {
  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async => {};
  @override
  Future<List<Lot>> lotsAt(DateTime asOf) async => const [];
  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) =>
      throw UnimplementedError();
  @override
  Future<void> invalidateFrom(DateTime from) async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Empty-portfolio analytics page renders the "no equity holdings yet"
  // state plus the risk + benchmark cards in their idle layout. This is
  // both the most common state for new users and the cheapest to mock,
  // so it's the right surface for the visual baseline.
  runAllVariants('analytics_page_empty', (tester, variant) async {
    final prefs = await SharedPreferences.getInstance();
    await pumpAndSnapshotMobile(
      tester,
      name: 'analytics_page_empty',
      variant: variant,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        equityAssetsStreamProvider.overrideWith(
          (_) => Stream.value(const <Asset>[]),
        ),
        holdingServiceProvider.overrideWith(
          (_) async => _EmptyHoldingService(),
        ),
        holdingsSnapshotProvider.overrideWith((_) async => const {}),
        analyticsBaseCurrencyProvider.overrideWithValue('USD'),
        manualAssetsStreamProvider.overrideWith(
          (_) => Stream.value(const <Asset>[]),
        ),
        allAssetsStreamProvider.overrideWith(
          (_) => Stream.value(const <Asset>[]),
        ),
        physicalAssetsListProvider.overrideWith((_) => Stream.value(const [])),
        liabilitiesStreamProvider.overrideWith((_) => Stream.value(const [])),
        // BenchmarkComparisonCard pulls the dashboard currency converter,
        // which transitively watches `fxRatesStreamProvider`. Without an
        // override that one reaches the real Drift database and leaves a
        // stream-query timer dangling at scope dispose.
        fxRatesStreamProvider.overrideWith(
          (_) => Stream<List<FxRate>>.value(const []),
        ),
        dashboardPriceRowsProvider.overrideWith((_) => Stream.value(const [])),
        allAccountsStreamProvider.overrideWith((_) => Stream.value(const [])),
        journalEntriesWithPostingsStreamProvider.overrideWith(
          (_) => Stream.value(const []),
        ),
        benchmarkHistorySourceProvider.overrideWith(
          (_) async => _EmptyBenchmarkSource(),
        ),
      ],
      child: const AnalyticsPage(),
    );
  });
}
