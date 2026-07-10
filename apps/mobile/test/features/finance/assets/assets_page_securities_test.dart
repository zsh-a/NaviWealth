import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/shell/selection_query.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/finance/assets/physical/data/providers.dart';
import 'package:naviwealth/features/finance/assets/ui/asset_detail_page.dart';
import 'package:naviwealth/features/finance/assets/ui/assets_page.dart';
import 'package:naviwealth/features/finance/assets/ui/security_asset_tile.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 5, 1),
  updatedByDevice: 'dev',
  hlc: Hlc.zero('dev'),
);

Asset _security({
  required String symbol,
  AssetType type = AssetType.stock,
  String currency = 'USD',
  String market = 'us_stock',
  String name = '',
}) {
  return Asset(
    id: '$market:$symbol',
    type: type,
    symbol: symbol,
    currency: currency,
    name: name.isEmpty ? null : name,
    market: market,
    sync: _meta(),
  );
}

HoldingSnapshot _snapshot({
  required String assetId,
  required String quantity,
  required String marketValue,
  String currency = 'USD',
}) {
  return HoldingSnapshot(
    assetId: assetId,
    quantity: Decimal.parse(quantity),
    costBasisInAssetCurrency: Decimal.zero,
    marketValueInAssetCurrency: Decimal.parse(marketValue),
    assetCurrency: currency,
    costBasisInBase: Decimal.zero,
    marketValueInBase: Decimal.parse(marketValue),
    unrealizedPnlInBase: Decimal.zero,
    weight: Decimal.zero,
    baseCurrency: currency,
    asOf: DateTime.utc(2026, 5, 1),
  );
}

Widget _wrap({
  required SharedPreferences prefs,
  List<Asset> manualAssets = const [],
  List<Asset> securities = const [],
  Map<String, HoldingSnapshot> holdings = const {},
  List<PhysicalAsset> physicalAssets = const [],
  bool holdingsNeverCompletes = false,
  double? contentWidth,
}) {
  // The page reaches for `GoRouter.of(context)` to resolve the
  // `?selected=` query — wrap with a router that serves the page at `/wealth`
  // and absorbs any push targets the test never actually exercises.
  final router = GoRouter(
    initialLocation: '/wealth',
    routes: [
      GoRoute(
        path: '/wealth',
        builder: (_, _) => Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: contentWidth, child: const AssetsPage()),
        ),
      ),
      GoRoute(
        path: '/wealth/assets/:id',
        builder: (_, _) => const Text('single-asset-detail'),
      ),
    ],
    errorBuilder: (_, _) => const SizedBox.shrink(),
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      manualAssetsStreamProvider.overrideWith(
        (_) => Stream.value(manualAssets),
      ),
      securitiesAssetsStreamProvider.overrideWith(
        (_) => Stream.value(securities),
      ),
      physicalAssetsListProvider.overrideWith(
        (_) => Stream.value(physicalAssets),
      ),
      holdingsSnapshotProvider.overrideWith((_) {
        if (holdingsNeverCompletes) {
          return Completer<Map<String, HoldingSnapshot>>().future;
        }
        return Future.value(holdings);
      }),
      dashboardManualAssetValuationsProvider.overrideWith(
        (_) => const AsyncValue.data(<ManualAssetValuation>[]),
      ),
      accountsStreamProvider.overrideWith((_) => Stream.value(const [])),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> setSurface(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('renders securities section with name + market value when '
      'a holding snapshot is available', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final aapl = _security(symbol: 'AAPL', name: 'Apple Inc.');
    await tester.pumpWidget(
      _wrap(
        prefs: prefs,
        securities: [aapl],
        holdings: {
          aapl.id: _snapshot(
            assetId: aapl.id,
            quantity: '10',
            marketValue: '1800',
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AssetsPage), findsOneWidget);
    expect(find.textContaining('AAPL'), findsWidgets);
    expect(find.textContaining('Apple Inc.'), findsWidgets);
  });

  testWidgets('renders a security row without a holding snapshot', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final aapl = _security(symbol: 'AAPL', name: 'Apple Inc.');
    await tester.pumpWidget(
      _wrap(
        prefs: prefs,
        securities: [aapl],
        // No holdings — the section should still render the asset row.
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('AAPL'), findsWidgets);
  });

  testWidgets('renders asset rows while holding snapshot is still loading', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final aapl = _security(symbol: 'AAPL', name: 'Apple Inc.');
    await tester.pumpWidget(
      _wrap(prefs: prefs, securities: [aapl], holdingsNeverCompletes: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('AAPL'), findsWidgets);
  });

  testWidgets('uses viewport width for inline selection at 1280', (
    tester,
  ) async {
    await setSurface(tester, 1280);
    final prefs = await SharedPreferences.getInstance();
    final aapl = _security(symbol: 'AAPL', name: 'Apple Inc.');
    await tester.pumpWidget(
      _wrap(prefs: prefs, securities: [aapl], contentWidth: 900),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MasterDetailLayout), findsOneWidget);
    final tile = find.byType(SecurityAssetTile);
    expect(tile, findsOneWidget);
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(selectedQueryOf(tester.element(find.byType(AssetsPage))), aapl.id);
    expect(find.byType(AssetDetailPage), findsOneWidget);
    expect(find.text('single-asset-detail'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('pushes a detail route below 1280', (tester) async {
    await setSurface(tester, 1279);
    final prefs = await SharedPreferences.getInstance();
    final aapl = _security(symbol: 'AAPL', name: 'Apple Inc.');
    await tester.pumpWidget(
      _wrap(prefs: prefs, securities: [aapl], contentWidth: 900),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MasterDetailLayout), findsNothing);
    final tile = find.byType(SecurityAssetTile);
    expect(tile, findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.text('single-asset-detail'), findsOneWidget);
  });
}
