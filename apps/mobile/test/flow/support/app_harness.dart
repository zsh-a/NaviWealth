// Flow-test harness (Task-oriented testing — see docs/development/testing-strategy.md §4).
//
// Flow tests exercise a *user task* across multiple screens, asserted
// through Page Objects (support/page_objects.dart) rather than raw
// `find.text(...)` calls. The point is durability: when the responsive
// layout is refactored, only the Page Objects change — the Task logic
// in the `*_flow_test.dart` files stays put.
//
// This harness boots the real `NaviWealthApp` (real router, real shell,
// real widgets) with the data layer overridden to deterministic streams,
// reusing the proven override set from test/widget_test.dart. It runs
// under `flutter test` (no device/emulator). The on-device
// `integration_test/` layer that exercises SQLCipher + a real Drift
// connection is the documented next step (docs/development/testing-strategy.md §6).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/app/domain_composition.dart';
import 'package:naviwealth/app/routing/router.dart';
import 'package:naviwealth/app/share_intents/share_intent_service.dart';
import 'package:naviwealth/core/ai/contracts/privacy_mode_provider.dart';
import 'package:naviwealth/core/ai/write/providers.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/analytics/data/benchmark/benchmark_history_source.dart';
import 'package:naviwealth/features/finance/analytics/data/benchmark/benchmark_providers.dart';
import 'package:naviwealth/features/finance/analytics/data/providers.dart'
    as analytics_data;
import 'package:naviwealth/features/finance/analytics/domain/benchmark/benchmark_comparison.dart';
import 'package:naviwealth/features/finance/analytics/domain/benchmark/benchmark_index.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/assets/physical/data/providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/cash_flow_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/recurring_transaction_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/liability.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/test_database.dart';
import '../../features/finance/data/repositories/_stub_stamper.dart';

class _OfflineBenchmarkSource implements BenchmarkHistorySource {
  @override
  Future<List<TimeSeriesPoint>> seriesFor({
    required BenchmarkIndex index,
    required DateTime from,
    required DateTime to,
  }) async => const [];
}

/// Deterministic seed data for a flow. Defaults to an empty portfolio
/// (the "first run" state); pass non-empty lists to drive Tasks that
/// assert on rendered balances.
class FlowSeed {
  const FlowSeed({
    this.accounts = const [],
    this.manualAssets = const [],
    this.liabilities = const [],
  });

  final List<Account> accounts;
  final List<Asset> manualAssets;
  final List<Liability> liabilities;
}

/// Real in-memory data layer for flow Tasks that must prove a write path
/// through repositories, not only navigation through stubbed streams.
class FlowDataHarness {
  FlowDataHarness({
    required this.db,
    required this.outbox,
    required this.stamper,
  });

  final AppDatabase db;
  final InMemoryOutboxStore outbox;
  final MutationStamper stamper;

  static Future<FlowDataHarness> create() async {
    return FlowDataHarness(
      db: makeTestDatabase(),
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(userId: kLocalOnlyUserId),
    );
  }

  Future<void> dispose() => db.close();

  Future<void> enableDomains(Iterable<DomainScope> scopes) {
    return DomainOptInStore(db).write(DomainOptIns(scopes.toSet()));
  }
}

/// Boots `NaviWealthApp` on a phone-sized surface and pumps it to a
/// settled frame. Returns once the home shell is interactive.
///
/// [extraOverrides] are appended after the base overrides, so a flow can
/// replace any provider it needs without rewriting the boot sequence.
Future<void> bootApp(
  WidgetTester tester, {
  FlowSeed seed = const FlowSeed(),
  FlowDataHarness? liveData,
  String initialLocation = '/',
  Map<String, Object> initialPrefs = const {},
  List<Override> extraOverrides = const [],
}) async {
  // Phone surface so the shell renders the bottom navigation bar; the
  // responsive rail/sidebar switch is covered in app/router_test.dart.
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'naviwealth.locale': 'en',
    'app.mode.v1': 'local_only',
    ...initialPrefs,
  });
  final prefs = await SharedPreferences.getInstance();
  await markAiPrivacyOnboardingSeen(prefs);
  final testDb = liveData == null ? makeTestDatabase() : null;
  if (testDb != null) {
    addTearDown(testDb.close);
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        activeUserIdProvider.overrideWithValue(kLocalOnlyUserId),
        currentUserIdProvider.overrideWithValue(() async => kLocalOnlyUserId),
        shareIntentPlatformAvailableProvider.overrideWithValue(false),
        appDatabaseProvider.overrideWith((_) async => liveData?.db ?? testDb!),
        if (liveData != null) ...[
          outboxStoreProvider.overrideWith((_) async => liveData.outbox),
          mutationStamperProvider.overrideWith((_) async => liveData.stamper),
        ] else
          mutationStamperProvider.overrideWith(
            (_) async => makeStubStamper(userId: kLocalOnlyUserId),
          ),
        // Match production bootstrap so the DomainPack inventory, shell
        // routes, active-domain aggregators, and domain-owned provider
        // seams stay in sync.
        ...lifeOsDomainCompositionOverrides(),
        // Most legacy task flows start on Finance Today. Cross-domain tasks
        // pass `/life` or a domain route explicitly.
        appRouterProvider.overrideWith(
          (ref) => buildAppRouter(ref, initialLocation: initialLocation),
        ),
        // Data layer → deterministic streams. Seeded from [FlowSeed] so a
        // Task can assert on rendered balances without touching Drift.
        manualAssetsStreamProvider.overrideWith(
          (ref) => Stream<List<Asset>>.value(seed.manualAssets),
        ),
        allAssetsStreamProvider.overrideWith(
          (ref) => Stream<List<Asset>>.value(seed.manualAssets),
        ),
        physicalAssetsListProvider.overrideWith(
          (ref) => Stream.value(const []),
        ),
        liabilitiesStreamProvider.overrideWith(
          (ref) => Stream<List<Liability>>.value(seed.liabilities),
        ),
        analytics_data.equityAssetsStreamProvider.overrideWith(
          (ref) => Stream<List<Asset>>.value(const []),
        ),
        benchmarkHistorySourceProvider.overrideWith(
          (_) async => _OfflineBenchmarkSource(),
        ),
        if (liveData == null)
          accountsStreamProvider.overrideWith(
            (ref) => Stream<List<Account>>.value(seed.accounts),
          ),
        fxRatesStreamProvider.overrideWith(
          (ref) => Stream<List<FxRate>>.value(const []),
        ),
        holdingsSnapshotProvider.overrideWith(
          (ref) async => const <String, HoldingSnapshot>{},
        ),
        dashboardManualAssetValuationsProvider.overrideWith(
          (ref) => const AsyncValue.data(<ManualAssetValuation>[]),
        ),
        dashboardSnapshotProvider.overrideWith(
          (ref) async => DashboardSnapshot.empty(
            asOf: DateTime.utc(2026, 1, 1),
            baseCurrency: 'CNY',
          ),
        ),
        dashboardPriceRowsProvider.overrideWith(
          (ref) => Stream.value(const []),
        ),
        cashFlowSummaryProvider.overrideWith(
          (ref, request) async => CashFlowSummary(
            period: request.period,
            baseCurrency: 'CNY',
            buckets: const [],
            totalInBase: Money.zero('CNY'),
          ),
        ),
        recurringMaterialiseDueProvider.overrideWith((ref, now) async => 0),
        undoEntriesStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ...extraOverrides,
      ],
      child: const NaviWealthApp(),
    ),
  );
  await settle(tester);
  addTearDown(() async {
    await closeApp(tester);
  });
}

/// Unmounts the app before a flow test body returns so Drift/Riverpod
/// dispose timers are flushed before flutter_test verifies invariants.
Future<void> closeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 600));
}

/// Pumps a bounded number of frames. Flow surfaces subscribe to streams
/// and timers, so `pumpAndSettle` can hang — pump a fixed budget instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
}

/// Pumps until [finder] resolves or a bounded time budget is exhausted.
///
/// Use this for work intentionally dispatched to an isolate/background queue;
/// a fixed frame count becomes flaky when the full suite is CPU-concurrent.
Future<void> settleUntil(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 100,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  await tester.pump();
}
