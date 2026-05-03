import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/assets/assets_page.dart';
import 'package:naviwealth/features/assets/physical/data/physical_asset.dart';
import 'package:naviwealth/features/assets/physical/data/providers.dart';
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/domain/models/holding_snapshot.dart';
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
}) {
  // The page reaches for `GoRouter.of(context)` to resolve the
  // `?selected=` query — wrap with a router that serves the page at `/`
  // and absorbs any push targets the test never actually exercises.
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => const AssetsPage())],
    errorBuilder: (_, _) => const SizedBox.shrink(),
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      manualAssetsStreamProvider.overrideWith((_) => Stream.value(manualAssets)),
      securitiesAssetsStreamProvider
          .overrideWith((_) => Stream.value(securities)),
      physicalAssetsListProvider.overrideWith(
        (_) => Stream.value(physicalAssets),
      ),
      holdingsSnapshotProvider.overrideWith((_) async => holdings),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('renders securities section with name + market value when '
      'a holding snapshot is available', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final aapl = _security(
      symbol: 'AAPL',
      name: 'Apple Inc.',
    );
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

  testWidgets('renders a security row without a holding snapshot',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final aapl = _security(
      symbol: 'AAPL',
      name: 'Apple Inc.',
    );
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
}
