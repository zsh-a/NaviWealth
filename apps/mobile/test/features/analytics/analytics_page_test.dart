import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart' as dom;
import 'package:naviwealth/features/analytics/analytics_page.dart';
import 'package:naviwealth/features/analytics/data/benchmark/benchmark_history_source.dart';
import 'package:naviwealth/features/analytics/data/benchmark/benchmark_providers.dart';
import 'package:naviwealth/features/analytics/data/providers.dart';
import 'package:naviwealth/features/analytics/domain/benchmark/benchmark_comparison.dart';
import 'package:naviwealth/features/analytics/domain/benchmark/benchmark_index.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/assets/physical/data/providers.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/liability.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart'
    as repo_providers;
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/domain/holding_service.dart';
import 'package:naviwealth/features/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/investment/domain/models/lot.dart';
import 'package:naviwealth/features/liabilities/data/providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/test_database.dart';

class _EmptyBenchmarkSource implements BenchmarkHistorySource {
  @override
  Future<List<TimeSeriesPoint>> seriesFor({
    required BenchmarkIndex index,
    required DateTime from,
    required DateTime to,
  }) async => const [];
}

class _StubHoldingService implements HoldingService {
  _StubHoldingService(this._snapshots);
  final Map<String, HoldingSnapshot> _snapshots;
  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async =>
      _snapshots;
  @override
  Future<List<Lot>> lotsAt(DateTime asOf) async => const [];
  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) =>
      throw UnimplementedError();
  @override
  Future<void> invalidateFrom(DateTime from) async {}
}

const _user = 'user-1';
const _baseCurrency = 'USD';

Asset _equity({
  required String id,
  required String symbol,
  String? industry,
  String? region,
  String? market,
  String? name,
  AssetType type = AssetType.stock,
}) {
  return Asset(
    id: id,
    type: type,
    symbol: symbol,
    currency: 'USD',
    name: name ?? symbol,
    market: market,
    industry: industry,
    region: region,
    sync: SyncMeta(
      ownerUserId: _user,
      updatedAt: DateTime.utc(2026, 1, 1),
      updatedByDevice: 'dev',
      hlc: Hlc.zero('node'),
    ),
  );
}

HoldingSnapshot _snap(String assetId, String mvBase) {
  final value = Decimal.parse(mvBase);
  return HoldingSnapshot(
    assetId: assetId,
    quantity: Decimal.one,
    costBasisInAssetCurrency: Decimal.zero,
    marketValueInAssetCurrency: value,
    assetCurrency: 'USD',
    costBasisInBase: Decimal.zero,
    marketValueInBase: value,
    unrealizedPnlInBase: Decimal.zero,
    weight: Decimal.zero,
    baseCurrency: _baseCurrency,
    asOf: DateTime.utc(2026, 4, 28),
  );
}

Future<ProviderContainer> _container({
  required Map<String, HoldingSnapshot> snapshots,
  required List<Asset> assets,
  String baseCurrency = _baseCurrency,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = makeTestDatabase();
  addTearDown(db.close);
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWith((_) async => db),
      equityAssetsStreamProvider.overrideWith((_) => Stream.value(assets)),
      holdingsSnapshotProvider.overrideWith((_) async => snapshots),
      holdingServiceProvider.overrideWith(
        (ref) async => _StubHoldingService(snapshots),
      ),
      analyticsBaseCurrencyProvider.overrideWithValue(baseCurrency),
      // Benchmark card depends on the dashboard's net-worth pipeline. Stub
      // the upstream streams so the card renders the empty state without
      // touching the database / market-data service.
      repo_providers.manualAssetsStreamProvider.overrideWith(
        (_) => Stream.value(const <Asset>[]),
      ),
      repo_providers.fxRatesStreamProvider.overrideWith(
        (_) => Stream.value(const <dom.FxRate>[]),
      ),
      physicalAssetsListProvider.overrideWith(
        (_) => Stream.value(const <PhysicalAsset>[]),
      ),
      liabilitiesStreamProvider.overrideWith(
        (_) => Stream.value(const <Liability>[]),
      ),
      benchmarkHistorySourceProvider.overrideWith(
        (_) async => _EmptyBenchmarkSource(),
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: AnalyticsPage(),
      ),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump();
}

void main() {
  setUpAll(() {
    GlobalMaterialLocalizations.delegate;
    GlobalWidgetsLocalizations.delegate;
    GlobalCupertinoLocalizations.delegate;
  });

  testWidgets('renders empty state when no equity holdings exist', (
    tester,
  ) async {
    final container = await _container(snapshots: const {}, assets: const []);
    addTearDown(container.dispose);
    await _pump(tester, container);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AnalyticsPage)),
    );
    expect(find.text(l10n.analyticsCashFlowTrendTitle), findsOneWidget);
    expect(find.text(l10n.analyticsFireProgressTitle), findsOneWidget);
    expect(find.text(l10n.analyticsEmptyTitle), findsOneWidget);
  });

  testWidgets(
    'renders sector buckets and reflects switching to the region dimension',
    (tester) async {
      final assets = [
        _equity(id: 'a', symbol: 'AAPL', industry: 'Technology', market: 'us'),
        _equity(id: 'b', symbol: 'MSFT', industry: 'Technology', market: 'us'),
        _equity(
          id: 'c',
          symbol: '600519',
          industry: 'Beverages',
          market: 'sse',
        ),
      ];
      final snapshots = {
        'a': _snap('a', '500'),
        'b': _snap('b', '300'),
        'c': _snap('c', '200'),
      };
      final container = await _container(snapshots: snapshots, assets: assets);
      addTearDown(container.dispose);
      await _pump(tester, container);

      // Sector view: Technology bucket and Beverages bucket should both render.
      expect(find.text('Technology'), findsOneWidget);
      expect(find.text('Beverages'), findsOneWidget);

      // Switch to region dimension.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(AnalyticsPage)),
      );
      await tester.tap(find.text(l10n.analyticsDimensionRegion));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump();

      expect(find.text(l10n.analyticsBucketRegionUs), findsOneWidget);
      expect(find.text(l10n.analyticsBucketRegionCnA), findsOneWidget);
    },
  );

  testWidgets(
    'shows the unclassified banner and bucket when sector metadata missing',
    (tester) async {
      final assets = [
        _equity(id: 'a', symbol: 'AAPL', industry: 'Technology'),
        _equity(id: 'b', symbol: 'XYZ'),
      ];
      final snapshots = {'a': _snap('a', '900'), 'b': _snap('b', '100')};
      final container = await _container(snapshots: snapshots, assets: assets);
      addTearDown(container.dispose);
      await _pump(tester, container);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(AnalyticsPage)),
      );
      expect(find.text(l10n.analyticsBucketUnclassified), findsOneWidget);
      expect(find.text(l10n.analyticsUnclassifiedHint(1)), findsOneWidget);
    },
  );
}
