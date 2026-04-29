import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/features/analytics/analytics_page.dart';
import 'package:naviwealth/features/analytics/data/providers.dart';
import 'package:naviwealth/features/investment/domain/holding_service.dart';
import 'package:naviwealth/features/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

class _StubHoldingService implements HoldingService {
  _StubHoldingService(this._snapshots);
  final Map<String, HoldingSnapshot> _snapshots;
  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async =>
      _snapshots;
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

ProviderContainer _container({
  required Map<String, HoldingSnapshot> snapshots,
  required List<Asset> assets,
  String baseCurrency = _baseCurrency,
}) {
  return ProviderContainer(
    overrides: [
      equityAssetsStreamProvider.overrideWith(
        (_) => Stream.value(assets),
      ),
      holdingServiceProvider.overrideWithValue(
        _StubHoldingService(snapshots),
      ),
      analyticsBaseCurrencyProvider.overrideWithValue(baseCurrency),
    ],
  );
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
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
  await tester.pumpAndSettle();
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
    final container = _container(snapshots: const {}, assets: const []);
    addTearDown(container.dispose);
    await _pump(tester, container);

    final l10n = AppLocalizations.of(tester.element(find.byType(AnalyticsPage)));
    expect(find.text(l10n.analyticsEmptyTitle), findsOneWidget);
  });

  testWidgets(
    'renders sector buckets and reflects switching to the region dimension',
    (tester) async {
      final assets = [
        _equity(id: 'a', symbol: 'AAPL', industry: 'Technology', market: 'us'),
        _equity(id: 'b', symbol: 'MSFT', industry: 'Technology', market: 'us'),
        _equity(id: 'c', symbol: '600519', industry: 'Beverages', market: 'sse'),
      ];
      final snapshots = {
        'a': _snap('a', '500'),
        'b': _snap('b', '300'),
        'c': _snap('c', '200'),
      };
      final container = _container(snapshots: snapshots, assets: assets);
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
      await tester.pumpAndSettle();

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
      final snapshots = {
        'a': _snap('a', '900'),
        'b': _snap('b', '100'),
      };
      final container = _container(snapshots: snapshots, assets: assets);
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
