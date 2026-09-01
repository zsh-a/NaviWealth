import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_repository.dart';
import 'package:naviwealth/features/finance/investment/ui/watchlist_simulation_section.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _sync = SyncMeta(
  ownerUserId: 'u-test',
  updatedAt: DateTime.utc(2026, 8, 31),
  updatedByDevice: 'dev-test',
  hlc: Hlc.zero('dev-test'),
);

final _collection = WatchlistCollection(
  id: 'collection-growth',
  name: 'Growth',
  createdAt: DateTime.utc(2026, 8, 31),
  sync: _sync,
);

final _item = WatchlistItem(
  id: 'us_stock:AAPL',
  symbol: 'AAPL',
  market: AssetMarket.usStock,
  addedAt: DateTime.utc(2026, 8, 31),
  alertRules: const PriceAlertRules(),
  sync: _sync,
);

final _namedItem = WatchlistItem(
  id: _item.id,
  symbol: _item.symbol,
  market: _item.market,
  addedAt: _item.addedAt,
  alertRules: _item.alertRules,
  sync: _item.sync,
  nameEn: 'Apple Inc.',
  nameCn: '苹果公司',
);

final _simulation = WatchlistSimulation(
  id: 'simulation-growth',
  collectionId: _collection.id,
  name: 'Growth paper mix',
  baseCurrency: 'USD',
  startingCapital: Decimal.parse('100000'),
  cashWeight: Decimal.parse('0.1'),
  baselineAt: DateTime.utc(2026, 8, 31),
  createdAt: DateTime.utc(2026, 8, 31),
  sync: _sync,
);

final _position = WatchlistSimulationPosition(
  id: 'position-aapl',
  simulationId: _simulation.id,
  watchlistItemId: _item.id,
  targetWeight: Decimal.parse('0.9'),
  createdAt: DateTime.utc(2026, 8, 31),
  sync: _sync,
);

final _snapshot = WatchlistQuoteSnapshot(
  item: _item,
  response: MarketResponse(
    data: Quote(
      symbol: 'AAPL',
      currency: 'USD',
      price: Decimal.parse('101'),
      previousClose: Decimal.parse('100'),
      asOf: DateTime.utc(2026, 8, 31, 2),
    ),
    freshness: DataFreshness.cachedFresh,
    source: 'test',
    fetchedAt: DateTime.utc(2026, 8, 31, 2),
  ),
);

final _dividendReference = WatchlistSimulationActionEntry(
  id: 'action-dividend',
  simulationId: _simulation.id,
  watchlistItemId: _item.id,
  symbol: 'AAPL',
  market: AssetMarket.usStock.wire,
  source: 'test',
  dataset: 'fixture',
  sourceKey: 'AAPL:dividend:1',
  revisionHash: 'revision-1',
  kind: MarketCorporateActionKind.distribution,
  status: MarketCorporateActionStatus.implemented,
  paperState: WatchlistSimulationPaperActionState.referenceOnly,
  recordDate: DateTime.utc(2026, 9, 10),
  exDate: DateTime.utc(2026, 9, 11),
  payDate: DateTime.utc(2026, 9, 12),
  currency: 'USD',
  cashPerShare: Decimal.parse('0.25'),
  eligibleQuantity: null,
  grossAmount: null,
  withholdingTaxAmount: null,
  netAmount: null,
  baseCurrencyAmount: null,
  createdAt: DateTime.utc(2026, 9, 1),
  sync: _sync,
);

final _dividendEntitlement = WatchlistSimulationActionEntry(
  id: 'action-entitlement',
  simulationId: _simulation.id,
  watchlistItemId: _item.id,
  symbol: 'AAPL',
  market: AssetMarket.usStock.wire,
  source: 'test',
  dataset: 'fixture',
  sourceKey: 'AAPL:dividend:2',
  revisionHash: 'revision-2',
  kind: MarketCorporateActionKind.distribution,
  status: MarketCorporateActionStatus.implemented,
  paperState: WatchlistSimulationPaperActionState.grossCashPendingTax,
  recordDate: DateTime.utc(2026, 9, 10),
  exDate: DateTime.utc(2026, 9, 11),
  payDate: DateTime.utc(2026, 9, 12),
  currency: 'USD',
  cashPerShare: Decimal.parse('0.25'),
  eligibleQuantity: Decimal.parse('100'),
  grossAmount: Decimal.parse('25'),
  paperCashGrossAmount: Decimal.parse('25'),
  stateAt: DateTime.utc(2026, 9, 12),
  withholdingTaxAmount: null,
  netAmount: null,
  baseCurrencyAmount: null,
  createdAt: DateTime.utc(2026, 9, 1),
  sync: _sync,
);

final _observations = [
  WatchlistSimulationObservation(
    id: 'observation-baseline',
    simulationId: _simulation.id,
    observationDay: '2026-08-31',
    observedAt: DateTime.utc(2026, 8, 31),
    projectedValue: Decimal.parse('100000'),
    weightedDailyChange: Decimal.zero,
    pricedWeight: Decimal.zero,
    missingQuoteWeight: Decimal.parse('0.9'),
  ),
  WatchlistSimulationObservation(
    id: 'observation-next-day',
    simulationId: _simulation.id,
    observationDay: '2026-09-01',
    observedAt: DateTime.utc(2026, 9),
    projectedValue: Decimal.parse('100900'),
    weightedDailyChange: Decimal.parse('0.009'),
    pricedWeight: Decimal.parse('0.9'),
    missingQuoteWeight: Decimal.zero,
  ),
];

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
  });

  testWidgets('offers simulations only from a concrete collection', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        preferences: preferences,
        simulations: const [],
        positions: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Paper simulations'), findsOneWidget);
    expect(
      find.textContaining('never changes real portfolios'),
      findsOneWidget,
    );
    expect(find.text('New simulation'), findsOneWidget);
  });

  testWidgets('shows paper projection and allocation controls', (tester) async {
    await tester.pumpWidget(
      _wrap(
        preferences: preferences,
        simulations: [_simulation],
        positions: [_position],
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(
      const ValueKey<String>('watchlist-simulation-simulation-growth'),
    );
    expect(card, findsOneWidget);
    expect(
      find.descendant(
        of: card,
        matching: find.text('Paper allocation · not actual performance'),
      ),
      findsOneWidget,
    );
    final metrics = tester
        .widgetList<AppMetricCluster>(
          find.descendant(of: card, matching: find.byType(AppMetricCluster)),
        )
        .expand((cluster) => cluster.items)
        .map((item) => '${item.label}:${item.value}');
    expect(metrics, [
      'Virtual capital:\$100K',
      'Weighted daily move:+0.90%',
      'Priced allocation:90%',
      'Virtual cash:10%',
    ]);
    expect(
      find.descendant(of: card, matching: find.text('AAPL')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'watchlist-simulation-history-chart-simulation-growth',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Latest observed value'), findsOneWidget);
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('no historical NAV'),
      ),
      findsOneWidget,
    );

    expect(find.byIcon(FLucideIcons.slidersHorizontal), findsOneWidget);
    expect(find.byIcon(FLucideIcons.trash2), findsOneWidget);
  });

  testWidgets('shows automatically recorded dividend references', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        preferences: preferences,
        simulations: [_simulation],
        positions: [_position],
        actionEntries: [_dividendReference],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recorded dividends'), findsOneWidget);
    expect(find.text(r'$0.25 per share'), findsOneWidget);
    expect(
      find.textContaining('quantity, tax, cash and NAV are not inferred'),
      findsOneWidget,
    );
  });

  testWidgets('shows holdings-based gross dividend entitlement', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        preferences: preferences,
        simulations: [_simulation],
        positions: [_position],
        actionEntries: [_dividendEntitlement],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(r'$25.00 gross · 100 virtual shares'), findsOneWidget);
    expect(
      find.textContaining('Gross paper cash · tax pending'),
      findsOneWidget,
    );
    expect(
      find.textContaining('informational and excluded from NAV'),
      findsOneWidget,
    );
  });

  testWidgets('shows localized stock names beside simulation symbols', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        preferences: preferences,
        simulations: [_simulation],
        positions: [_position],
        item: _namedItem,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Apple Inc. (AAPL)'), findsOneWidget);
  });
}

Widget _wrap({
  required SharedPreferences preferences,
  required List<WatchlistSimulation> simulations,
  required List<WatchlistSimulationPosition> positions,
  WatchlistItem? item,
  List<WatchlistSimulationActionEntry> actionEntries = const [],
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      watchlistSimulationsProvider.overrideWith(
        (_) => Stream.value(simulations),
      ),
      watchlistSimulationPositionsProvider.overrideWith(
        (_, _) => Stream.value(positions),
      ),
      watchlistSimulationObservationsProvider.overrideWith(
        (_, _) => Stream.value(_observations),
      ),
      watchlistSimulationActionEntriesProvider.overrideWith(
        (_, _) => Stream.value(actionEntries),
      ),
      watchlistSimulationActionReconciliationProvider.overrideWith(
        (_, _) async => const WatchlistSimulationActionReconciliation(
          materializedCount: 0,
          failedSymbolCount: 0,
          unsupportedSymbolCount: 0,
        ),
      ),
      watchlistSimulationObservationRecorderProvider.overrideWithValue(
        (_) async {},
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: FTheme(
        data: buildAppForuiTheme(brightness: Brightness.light, touch: true),
        child: Scaffold(
          body: ListView(
            children: [
              WatchlistSimulationSection(
                collection: _collection,
                items: [item ?? _item],
                snapshots: [_snapshot],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
