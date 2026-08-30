import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/assets/data/asset_detail_providers.dart';
import 'package:naviwealth/features/finance/assets/ui/asset_holding_card.dart';
import 'package:naviwealth/features/finance/assets/ui/asset_pnl_card.dart';
import 'package:naviwealth/features/finance/assets/ui/asset_summary_card.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets(
    'asset summary presents compact quote identity without overflow',
    (tester) async {
      await _pumpCard(
        tester,
        Asset(
          id: 'custom:AAPL',
          type: AssetType.stock,
          symbol: 'AAPL',
          currency: 'USD',
          name: 'Apple Inc.',
          sync: _meta(),
        ),
      );

      expect(find.text('AAPL'), findsOneWidget);
      expect(find.text('Apple Inc.'), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);
      expect(find.text('Latest close'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long security identity stays bounded at larger text scale', (
    tester,
  ) async {
    const symbol = 'VERY-LONG-SECURITY-SYMBOL';
    const name =
        'A deliberately long localized security name that must remain bounded';
    await _pumpCard(
      tester,
      Asset(
        id: 'custom:long',
        type: AssetType.etf,
        symbol: symbol,
        currency: 'USD',
        name: name,
        sync: _meta(),
      ),
      textScale: 1.5,
    );

    expect(find.text(symbol), findsOneWidget);
    expect(find.text(name), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('price and market value share the holding valuation input', (
    tester,
  ) async {
    final asset = Asset(
      id: 'custom:AAPL',
      type: AssetType.stock,
      symbol: 'AAPL',
      currency: 'USD',
      market: 'us_stock',
      sync: _meta(),
    );
    final snapshot = HoldingSnapshot(
      assetId: asset.id,
      quantity: Decimal.parse('2'),
      costBasisInAssetCurrency: Decimal.parse('180'),
      // Deliberately inconsistent legacy aggregate: the UI must use the
      // canonical quantity × unit-price calculation instead.
      marketValueInAssetCurrency: Decimal.parse('999'),
      assetCurrency: 'USD',
      costBasisInBase: Decimal.parse('180'),
      marketValueInBase: Decimal.parse('999'),
      unrealizedPnlInBase: Decimal.parse('819'),
      weight: Decimal.one,
      baseCurrency: 'USD',
      asOf: DateTime.utc(2026, 1, 3),
      unitPriceInAssetCurrency: Decimal.parse('120'),
      priceAsOf: DateTime.utc(2026, 1, 3, 12),
    );

    await _pumpCard(
      tester,
      asset,
      child: SingleChildScrollView(
        child: Column(
          children: [
            AssetSummaryCard(asset: asset),
            AssetHoldingCard(asset: asset),
            AssetPnLCard(asset: asset),
          ],
        ),
      ),
      overrides: [
        assetHoldingSnapshotProvider.overrideWith(
          (ref, assetId) async => snapshot,
        ),
        assetPriceHistoryProvider.overrideWith(
          (ref, key) async => MarketResponse(
            data: [
              HistoricalBar(
                symbol: key.symbol,
                asOf: DateTime.utc(2026, 1, 1),
                open: Decimal.parse('99'),
                high: Decimal.parse('101'),
                low: Decimal.parse('98'),
                close: Decimal.parse('100'),
              ),
              HistoricalBar(
                symbol: key.symbol,
                asOf: DateTime.utc(2026, 1, 2),
                open: Decimal.parse('100'),
                high: Decimal.parse('102'),
                low: Decimal.parse('99'),
                close: Decimal.parse('101'),
              ),
            ],
            freshness: DataFreshness.live,
            source: 'test',
            fetchedAt: DateTime.utc(2026, 1, 3),
          ),
        ),
      ],
    );

    expect(find.text('Valuation price'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AnimatedMoneyText && widget.amount == 120,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AnimatedMoneyText && widget.amount == 240,
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<DeltaText>(find.byType(DeltaText, skipOffstage: false))
          .map((w) => w.value),
      contains(38),
    );
  });
}

Future<void> _pumpCard(
  WidgetTester tester,
  Asset asset, {
  double textScale = 1,
  Widget? child,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: FTheme(
        data: FTheme.neutral.light.desktop,
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(body: child ?? AssetSummaryCard(asset: asset)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u-test',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'dev-test',
  hlc: Hlc.zero('dev-test'),
);
