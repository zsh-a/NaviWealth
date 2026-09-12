import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/assets/ui/asset_detail_page.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_view_state.dart';
import 'package:naviwealth/features/finance/investment/notifications/watchlist_alerts.dart';
import 'package:naviwealth/features/finance/investment/ui/watchlist_page.dart';
import 'package:naviwealth/features/finance/investment/ui/watchlist_rows.dart';
import 'package:naviwealth/features/finance/investment/ui/watchlist_sections.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _item = WatchlistItem(
  id: 'us_stock:AAPL',
  symbol: 'AAPL',
  market: AssetMarket.usStock,
  addedAt: DateTime.utc(2026, 7, 19),
  alertRules: const PriceAlertRules(),
  sync: SyncMeta(
    ownerUserId: 'u',
    updatedAt: DateTime.utc(2026, 7, 19),
    updatedByDevice: 'test',
    hlc: Hlc.zero('test'),
  ),
);

final _otherItem = WatchlistItem(
  id: 'us_stock:MSFT',
  symbol: 'MSFT',
  market: AssetMarket.usStock,
  addedAt: DateTime.utc(2026, 7, 20),
  alertRules: const PriceAlertRules(),
  sync: _item.sync,
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

final _collection = WatchlistCollection(
  id: 'collection-growth',
  name: 'Growth',
  createdAt: DateTime.utc(2026, 7, 19),
  sync: _item.sync,
);

final _otherCollection = WatchlistCollection(
  id: 'collection-income',
  name: 'Income',
  createdAt: DateTime.utc(2026, 7, 20),
  sync: _item.sync,
);

final _membership = WatchlistCollectionMember(
  id: 'membership-aapl-growth',
  collectionId: _collection.id,
  watchlistItemId: _item.id,
  addedAt: DateTime.utc(2026, 7, 19),
  sync: _item.sync,
);

final _otherMembership = WatchlistCollectionMember(
  id: 'membership-msft-growth',
  collectionId: _collection.id,
  watchlistItemId: _otherItem.id,
  addedAt: DateTime.utc(2026, 7, 20),
  sync: _item.sync,
  sortRank: 1024,
);

final _advancingSnapshot = WatchlistQuoteSnapshot(
  item: _item,
  response: MarketResponse(
    data: Quote(
      symbol: _item.symbol,
      currency: 'USD',
      price: Decimal.parse('201.25'),
      previousClose: Decimal.parse('200'),
      asOf: DateTime.utc(2026, 7, 19, 2),
    ),
    freshness: DataFreshness.cachedFresh,
    source: 'test-cache',
    fetchedAt: DateTime.utc(2026, 7, 19, 2),
  ),
);

final _decliningSnapshot = WatchlistQuoteSnapshot(
  item: _otherItem,
  response: MarketResponse(
    data: Quote(
      symbol: _otherItem.symbol,
      currency: 'USD',
      price: Decimal.parse('190'),
      previousClose: Decimal.parse('200'),
      asOf: DateTime.utc(2026, 7, 20, 2),
    ),
    freshness: DataFreshness.cachedFresh,
    source: 'test-cache',
    fetchedAt: DateTime.utc(2026, 7, 20, 2),
  ),
);

late SharedPreferences _preferences;

/// Builds the scoped harness. `Override` is not part of Riverpod's public
/// surface, so the overrides are applied here instead of being handed around.
Widget _scope(
  Widget child, {
  Future<List<HistoricalBar>>? history,
  List<WatchlistItem>? items,
  List<WatchlistQuoteSnapshot> snapshots = const [],
  List<WatchlistQuoteSnapshot>? scopedSnapshots,
  List<WatchlistCollection> collections = const [],
  List<WatchlistCollectionMember> members = const [],
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_preferences),
      manualAssetRepositoryProvider.overrideWith((_) async => _EmptyAssets()),
      watchlistHistoryProvider.overrideWith(
        (_, key) async => history != null
            ? await history
            : [
                for (var i = 0; i < 4; i++)
                  HistoricalBar(
                    symbol: key.symbol,
                    asOf: DateTime.utc(2026, 7, 16 + i),
                    open: Decimal.fromInt(198 + i),
                    high: Decimal.fromInt(198 + i),
                    low: Decimal.fromInt(198 + i),
                    close: Decimal.fromInt(198 + i),
                  ),
              ],
      ),
      watchlistSystemRemindersProvider.overrideWith((_) async => false),
      watchlistSymbolQuoteProvider.overrideWith(
        (_, key) async =>
            snapshots
                .where((entry) => entry.item.displaySymbol == key.symbol)
                .firstOrNull
                ?.response ??
            _advancingSnapshot.response!,
      ),
      watchlistQuoteUpdatesProvider.overrideWith(
        (_, scope) => Stream.value(
          scope.isAll ? snapshots : scopedSnapshots ?? snapshots,
        ),
      ),
      watchlistItemsProvider.overrideWith(
        (_) => Stream.value(items ?? [_item]),
      ),
      watchlistCollectionsProvider.overrideWith(
        (_) => Stream.value(collections),
      ),
      watchlistCollectionMembersProvider.overrideWith(
        (_) => Stream.value(members),
      ),
      watchlistSimulationsProvider.overrideWith((_) => Stream.value(const [])),
      watchlistQuoteSnapshotsProvider.overrideWith((_) async => snapshots),
      watchlistQuoteSnapshotsForScopeProvider.overrideWith(
        (_, _) async => scopedSnapshots ?? snapshots,
      ),
    ],
    child: child,
  );
}

/// Router-less host. Tapping a row must not need a router to have somewhere
/// to go, which is exactly the mobile dead end this page used to have.
Widget _wrap(
  TargetPlatform platform, {
  Future<List<HistoricalBar>>? history,
  List<WatchlistItem>? items,
  List<WatchlistQuoteSnapshot> snapshots = const [],
  List<WatchlistCollection> collections = const [],
  List<WatchlistCollectionMember> members = const [],
}) {
  final touch = platform == TargetPlatform.android;
  return _scope(
    MaterialApp(
      theme: AppTheme.light().copyWith(platform: platform),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: FTheme(
        data: buildAppForuiTheme(brightness: Brightness.light, touch: touch),
        child: const WatchlistPage(),
      ),
    ),
    history: history,
    items: items,
    snapshots: snapshots,
    collections: collections,
    members: members,
  );
}

Widget _routerWrap({
  required GoRouter router,
  List<WatchlistItem>? items,
  List<WatchlistQuoteSnapshot> snapshots = const [],
  List<WatchlistQuoteSnapshot>? scopedSnapshots,
  List<WatchlistCollection> collections = const [],
  List<WatchlistCollectionMember> members = const [],
}) {
  return _scope(
    MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
    ),
    items: items,
    snapshots: snapshots,
    scopedSnapshots: scopedSnapshots,
    collections: collections,
    members: members,
  );
}

GoRouter _watchlistRouter({String? initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation ?? FinanceRoutes.wealthWatchlist,
    routes: [
      GoRoute(
        path: '/wealth/assets/:assetId',
        builder: (_, state) => FTheme(
          data: buildAppForuiTheme(brightness: Brightness.light, touch: true),
          child: AssetDetailPage(assetId: state.pathParameters['assetId']!),
        ),
      ),
      GoRoute(
        path: FinanceRoutes.wealthWatchlist,
        builder: (_, _) => FTheme(
          data: buildAppForuiTheme(brightness: Brightness.light, touch: true),
          child: const WatchlistPage(),
        ),
      ),
    ],
  );
}

/// Opens the toolbar overflow menu, which is where every secondary action
/// lives now that the scope chips no longer share a scroller with them.
Future<void> _openToolbarMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(WatchlistToolbar.menuTriggerKey));
  await tester.pumpAndSettle();
}

/// Settles a sheet that contains a focused text field.
///
/// `pumpAndSettle` never returns while a caret is blinking, so the add sheet
/// is stepped instead.
Future<void> _pumpSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _preferences = await SharedPreferences.getInstance();
  });

  testWidgets(
    'does not duplicate an ungrouped list and disables incomplete submission',
    (tester) async {
      await tester.pumpWidget(_wrap(TargetPlatform.android));
      await tester.pumpAndSettle();
      expect(find.text('All (1)'), findsOneWidget);
      expect(find.text('Ungrouped (1)'), findsNothing);
      await tester.tap(find.byIcon(FLucideIcons.plus));
      await _pumpSheet(tester);
      expect(find.textContaining('Add to collections'), findsNothing);
      final sheet = tester.widget<AppSheet>(find.byType(AppSheet));
      expect((sheet.footer! as AppSheetFooter).enabled, isFalse);
      await tester.tap(find.text('Price reminder (optional)'));
      await _pumpSheet(tester);
      expect(find.textContaining('No background checks.'), findsOneWidget);
      expect(
        find.textContaining('Delivery: on the Watchlist page'),
        findsOneWidget,
      );
    },
  );

  testWidgets('builds long lists lazily and keeps the toolbar reachable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final items = [
      for (var i = 0; i < 120; i++)
        WatchlistItem(
          id: 'us_stock:S$i',
          symbol: 'S$i',
          market: AssetMarket.usStock,
          addedAt: _item.addedAt,
          alertRules: const PriceAlertRules(),
          sync: _item.sync,
        ),
    ];
    await tester.pumpWidget(_wrap(TargetPlatform.android, items: items));
    await tester.pumpAndSettle();
    expect(find.byType(WatchlistRow).evaluate().length, lessThan(30));
    final toolbarY = tester.getTopLeft(find.byType(WatchlistToolbar)).dy;
    await tester.drag(
      find.byKey(const ValueKey('watchlist-scroll')),
      const Offset(0, -1500),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(WatchlistToolbar)).dy, toolbarY);
    expect(find.byType(WatchlistRow).evaluate().length, lessThan(30));
    await _openToolbarMenu(tester);
    expect(find.text('Sort symbols'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps quote rows readable on a small phone with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      _wrap(
        TargetPlatform.android,
        items: [_namedItem],
        snapshots: [_advancingSnapshot],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('AAPL'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('watchlist-row-change-us_stock:AAPL')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selects multiple collections while adding a symbol', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(TargetPlatform.android, collections: [_collection]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.plus));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Add to watchlist'), findsOneWidget);
    expect(find.textContaining('Add to collections'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('watchlist-add-collection-collection-growth')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('watchlist-collections-expand')),
    );
    await _pumpSheet(tester);
    final collectionRow = find.byKey(
      const ValueKey<String>('watchlist-add-collection-collection-growth'),
    );
    expect(collectionRow, findsOneWidget);
    expect(
      tester
          .widget<FCheckbox>(
            find.descendant(
              of: collectionRow,
              matching: find.byType(FCheckbox),
            ),
          )
          .value,
      isFalse,
    );

    await tester.tap(collectionRow);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester
          .widget<FCheckbox>(
            find.descendant(
              of: collectionRow,
              matching: find.byType(FCheckbox),
            ),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('keeps optional alert rules out of the way when adding', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(TargetPlatform.android));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.plus));
    await _pumpSheet(tester);

    // The bound inputs used to sit in the open, which made an optional
    // follow-up look like a required step.
    expect(
      find.byKey(const ValueKey<String>('watchlist-alert-above')),
      findsNothing,
    );
    await tester.tap(find.text('Price reminder (optional)'));
    await _pumpSheet(tester);
    expect(
      find.byKey(const ValueKey<String>('watchlist-alert-above')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('watchlist-alert-below')),
      findsOneWidget,
    );
  });

  testWidgets('shows the localized stock name with its symbol', (tester) async {
    await tester.pumpWidget(_wrap(TargetPlatform.android, items: [_namedItem]));
    await tester.pumpAndSettle();

    expect(find.text('Apple Inc.'), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
  });

  testWidgets(
    'history arriving does not shift identity, price or change columns',
    (tester) async {
      final history = Completer<List<HistoricalBar>>();
      await tester.pumpWidget(
        _wrap(
          TargetPlatform.android,
          history: history.future,
          items: [_namedItem],
          snapshots: [_advancingSnapshot],
        ),
      );
      await tester.pumpAndSettle();
      final symbol = find.byKey(
        const ValueKey('watchlist-symbol-us_stock:AAPL'),
      );
      final trend = find.byKey(const ValueKey('watchlist-trend-us_stock:AAPL'));
      final change = find.byKey(
        const ValueKey('watchlist-row-change-us_stock:AAPL'),
      );
      final before = [
        tester.getRect(symbol),
        tester.getRect(trend),
        tester.getRect(change),
        tester.getRect(find.byType(MoneyText)),
      ];
      expect(find.byType(NwSparkline), findsNothing);
      history.complete([
        for (var i = 0; i < 3; i++)
          HistoricalBar(
            symbol: 'AAPL',
            asOf: DateTime.utc(2026, 7, 17 + i),
            open: Decimal.fromInt(200),
            high: Decimal.fromInt(202),
            low: Decimal.fromInt(199),
            close: Decimal.fromInt(200 + i),
          ),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(NwSparkline), findsOneWidget);
      expect([
        tester.getRect(symbol),
        tester.getRect(trend),
        tester.getRect(change),
        tester.getRect(find.byType(MoneyText)),
      ], before);
    },
  );

  testWidgets('opens bulk add and collection target selection', (tester) async {
    await tester.pumpWidget(
      _wrap(TargetPlatform.android, collections: [_collection]),
    );
    await tester.pumpAndSettle();

    await _openToolbarMenu(tester);
    await tester.tap(find.text('Organize symbols'));
    await tester.pumpAndSettle();

    expect(find.text('Organize symbols'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('watchlist-bulk-item-us_stock:AAPL')),
    );
    await tester.pump();
    await tester.tap(find.text('Add to collection'));
    await tester.pumpAndSettle();

    expect(find.text('Choose collection'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('watchlist-bulk-target-collection-growth'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('summarizes the collection in a single overview card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(TargetPlatform.android, snapshots: [_advancingSnapshot]),
    );
    await tester.pumpAndSettle();

    final overview = find.byKey(WatchlistOverviewCard.cardKey);
    expect(overview, findsOneWidget);
    expect(find.text('Today · 1 up · 0 down · 0 flat'), findsOneWidget);
    expect(find.byType(AppMetricCluster), findsNothing);
    expect(find.textContaining('Median'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('watchlist-overview-expand')));
    await tester.pumpAndSettle();
    expect(find.text('Median · +0.63%'), findsOneWidget);
    final rowChange = tester.widget<DeltaText>(
      find.byKey(const ValueKey<String>('watchlist-row-change-us_stock:AAPL')),
    );
    expect(rowChange.format, DeltaFormat.percent);
    expect(rowChange.value, closeTo(0.625, 0.000001));

    // One market needs no per-market breakdown — Up / down already says it.
    expect(find.textContaining('Up ·'), findsNothing);
  });

  testWidgets('keeps healthy quote telemetry out of the summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        TargetPlatform.android,
        items: [_item, _otherItem],
        snapshots: [_advancingSnapshot, _decliningSnapshot],
      ),
    );
    await tester.pumpAndSettle();

    final overview = find.byKey(WatchlistOverviewCard.cardKey);
    expect(
      find.descendant(of: overview, matching: find.text('2 cached')),
      findsNothing,
    );
    expect(
      find.descendant(of: overview, matching: find.byType(AppBadge)),
      findsNothing,
    );
    // The raw pipeline counters are gone.
    expect(find.textContaining('No price 0'), findsNothing);
    expect(find.textContaining('Live 0'), findsNothing);
  });

  testWidgets('draws a trend line per row without a per-row freshness chip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(TargetPlatform.android, snapshots: [_advancingSnapshot]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NwSparkline), findsOneWidget);
    // "Cached" belongs to the overview card, not to every single row.
    expect(find.text('Cached'), findsNothing);
  });

  testWidgets('keeps the overview compact and market breakdown collapsed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final hk = WatchlistItem(
      id: 'hk_stock:0700.HK',
      symbol: '0700.HK',
      market: AssetMarket.hkStock,
      addedAt: _item.addedAt,
      alertRules: const PriceAlertRules(),
      sync: _item.sync,
    );
    await tester.pumpWidget(
      _wrap(
        TargetPlatform.android,
        items: [_item, hk],
        snapshots: [_advancingSnapshot],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('By market'), findsNothing);
    expect(find.textContaining('Hong Kong ·'), findsNothing);
    expect(
      tester.getSize(find.byKey(WatchlistOverviewCard.cardKey)).height,
      lessThanOrEqualTo(844 * .25),
    );
    await tester.tap(find.byKey(const ValueKey('watchlist-overview-expand')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hong Kong ·'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('watchlist-overview-expand')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hong Kong ·'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('warns on the row only when its quote is actually stale', (
    tester,
  ) async {
    final stale = WatchlistQuoteSnapshot(
      item: _item,
      response: MarketResponse(
        data: _advancingSnapshot.quote!,
        freshness: DataFreshness.stale,
        source: 'test-cache',
        fetchedAt: _advancingSnapshot.response!.fetchedAt,
      ),
    );
    await tester.pumpWidget(_wrap(TargetPlatform.android, snapshots: [stale]));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey<String>('watchlist-row-stale-${_item.id}')),
      findsOneWidget,
    );
  });

  testWidgets('uses a bottom action sheet for row actions on Android', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(TargetPlatform.android));
    await tester.pumpAndSettle();

    expect(find.text('Price reminder'), findsNothing);
    expect(find.text('Remove'), findsNothing);
    expect(find.semantics.byLabel('Actions for AAPL'), findsOneWidget);
    final action = find.widgetWithIcon(
      AppIconButton,
      FLucideIcons.ellipsisVertical,
    );
    expect(tester.getSize(action), const Size.square(48));

    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.byType(AppSheet), findsOneWidget);
    expect(find.byType(AppActionSheetList), findsOneWidget);
    expect(find.text('Price reminder'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Price reminder'));
    await tester.pumpAndSettle();
    expect(find.text('Reminders for AAPL'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('uses an anchored row action menu on pointer platforms', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(TargetPlatform.macOS));
    await tester.pumpAndSettle();

    expect(find.semantics.byLabel('Actions for AAPL'), findsOneWidget);
    final action = find.widgetWithIcon(
      AppIconButton,
      FLucideIcons.ellipsisVertical,
    );
    expect(tester.getSize(action), const Size.square(44));
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-adaptive-action-menu.popover')),
      findsOneWidget,
    );
    expect(find.byType(AppSheet), findsNothing);
    expect(find.text('Price reminder'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('opens unowned symbol details through the existing asset route', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = _watchlistRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _routerWrap(router: router, snapshots: [_advancingSnapshot]),
    );
    await tester.pumpAndSettle();

    // Below the master/detail breakpoint the row used to be inert: the tap
    // target was the symbol text and had nowhere to go.
    await tester.tap(find.text('AAPL'));
    await tester.pumpAndSettle();

    expect(find.byType(AppSheet), findsNothing);
    expect(
      find.byKey(
        const ValueKey<String>('watchlist-detail-change-us_stock:AAPL'),
      ),
      findsOneWidget,
    );
    expect(find.text('No price reminder'), findsOneWidget);
    expect(
      tester.widget<AssetDetailPage>(find.byType(AssetDetailPage)).assetId,
      _item.assetId,
    );
    expect(router.canPop(), isTrue);
    router.pop();
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      FinanceRoutes.wealthWatchlist,
    );
  });

  testWidgets('uses a persistent quote detail pane on desktop', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = _watchlistRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _routerWrap(router: router, snapshots: [_advancingSnapshot]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MasterDetailLayout), findsOneWidget);
    expect(find.textContaining('Select a symbol'), findsOneWidget);

    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    expect(find.text('AAPL'), findsNWidgets(2));
    expect(find.text('Price reminder'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('watchlist-detail-change-us_stock:AAPL'),
      ),
      findsOneWidget,
    );
    expect(router.routeInformationProvider.value.uri.queryParameters, {
      'selected': 'us_stock:AAPL',
    });
    expect(
      tester.widget<WatchlistRow>(find.byType(WatchlistRow)).selected,
      isTrue,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('watchlist-detail-chart')))
          .width,
      greaterThan(200),
    );
    expect(find.textContaining('2026'), findsWidgets);
  });

  testWidgets('sorts through the view state without rewriting the URL', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _preferences.setString(kWatchlistSortPreferenceKey, 'decliners');
    final router = _watchlistRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _routerWrap(
        router: router,
        items: [_item, _otherItem],
        snapshots: [_advancingSnapshot, _decliningSnapshot],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('MSFT')).dy,
      lessThan(tester.getTopLeft(find.text('AAPL')).dy),
    );

    await _openToolbarMenu(tester);
    // The menu carries the current order as the action's subtitle.
    expect(find.text('Decliners first'), findsNWidgets(2));
    await tester.tap(find.text('Sort symbols'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gainers first'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('AAPL')).dy,
      lessThan(tester.getTopLeft(find.text('MSFT')).dy),
    );
    expect(_preferences.getString(kWatchlistSortPreferenceKey), 'gainers');
    // Sort order is presentation state, not a location.
    expect(router.routeInformationProvider.value.uri.queryParameters, isEmpty);
  });

  testWidgets('switches collection scope from the toolbar chips', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = _watchlistRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _routerWrap(
        router: router,
        items: [_item, _otherItem],
        collections: [_collection],
        members: [_membership],
        snapshots: const [],
      ),
    );
    await tester.pumpAndSettle();

    // Starts unscoped: every symbol shows, and picking a chip narrows.
    expect(find.text('All (2)'), findsOneWidget);
    expect(find.text('Growth (1)'), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsOneWidget);

    // The chip row scrolls horizontally; later chips need scrolling in.
    final growthChip = find.text('Growth (1)');
    await tester.ensureVisible(growthChip);
    await tester.pumpAndSettle();
    await tester.tap(growthChip);
    await tester.pumpAndSettle();

    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsNothing);
    expect(
      _preferences.getString(kWatchlistCollectionPreferenceKey),
      'collection:${_collection.id}',
    );

    final ungroupedChip = find.text('Ungrouped (1)');
    await tester.ensureVisible(ungroupedChip);
    await tester.pumpAndSettle();
    await tester.tap(ungroupedChip);
    await tester.pumpAndSettle();

    expect(find.text('MSFT'), findsOneWidget);
    expect(find.text('AAPL'), findsNothing);
    expect(
      _preferences.getString(kWatchlistCollectionPreferenceKey),
      'ungrouped',
    );
    expect(router.routeInformationProvider.value.uri.queryParameters, isEmpty);
  });

  testWidgets('restores the last valid collection without any URL state', (
    tester,
  ) async {
    await _preferences.setString(
      kWatchlistCollectionPreferenceKey,
      'collection:${_collection.id}',
    );
    final router = _watchlistRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _routerWrap(
        router: router,
        items: [_item, _otherItem],
        collections: [_collection],
        members: [_membership],
        snapshots: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Growth (1)'), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsNothing);
    expect(router.routeInformationProvider.value.uri.queryParameters, isEmpty);
  });

  testWidgets('falls back to all symbols when the scoped collection is gone', (
    tester,
  ) async {
    // A collection deleted on another device leaves a scope pointing at
    // nothing. Rendering an unreachable filter would show an empty list.
    await _preferences.setString(
      kWatchlistCollectionPreferenceKey,
      'collection:collection-deleted-elsewhere',
    );
    final router = _watchlistRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _routerWrap(
        router: router,
        items: [_item, _otherItem],
        collections: [_collection],
        members: [_membership],
        snapshots: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsOneWidget);
    expect(_preferences.getString(kWatchlistCollectionPreferenceKey), 'all');
  });

  testWidgets('applies and clears quote freshness filters from the menu', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = _watchlistRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _routerWrap(
        router: router,
        items: [_item, _otherItem],
        snapshots: [_advancingSnapshot],
      ),
    );
    await tester.pumpAndSettle();

    await _openToolbarMenu(tester);
    await tester.tap(find.text('Filter symbols'));
    await tester.pumpAndSettle();
    var sheet = find.byType(AppSheet);
    final noPrice = find.descendant(of: sheet, matching: find.text('No price'));
    var applyFilters = find.descendant(
      of: sheet,
      matching: find.text('Apply filters'),
    );
    await tester.ensureVisible(noPrice);
    await tester.tap(noPrice);
    await tester.ensureVisible(applyFilters);
    await tester.tap(applyFilters);
    await tester.pumpAndSettle();

    expect(find.text('MSFT'), findsOneWidget);
    expect(find.text('AAPL'), findsNothing);
    // A narrowing is visible in the toolbar without opening the menu.
    final activeChip = find.descendant(
      of: find.byKey(const ValueKey('watchlist-view-state')),
      matching: find.text('No price'),
    );
    expect(activeChip, findsOneWidget);
    expect(router.routeInformationProvider.value.uri.queryParameters, isEmpty);

    // Clear is reachable directly, without another sheet or horizontal scroll.
    await tester.tap(find.byKey(const ValueKey('watchlist-clear-filter')));
    await tester.pumpAndSettle();

    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('watchlist-view-state')),
      findsNothing,
    );
  });

  testWidgets('opens collection ordering from the toolbar menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        TargetPlatform.android,
        collections: [_collection, _otherCollection],
      ),
    );
    await tester.pumpAndSettle();

    await _openToolbarMenu(tester);
    await tester.tap(find.text('Reorder collections'));
    await tester.pumpAndSettle();

    expect(find.text('Reorder collections'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.text('Growth'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
  });

  testWidgets('opens symbol ordering for a selected collection', (
    tester,
  ) async {
    await _preferences.setString(
      kWatchlistCollectionPreferenceKey,
      'collection:${_collection.id}',
    );
    final router = _watchlistRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _routerWrap(
        router: router,
        items: [_item, _otherItem],
        collections: [_collection],
        members: [_membership, _otherMembership],
        snapshots: const [],
      ),
    );
    await tester.pumpAndSettle();

    await _openToolbarMenu(tester);
    await tester.tap(find.text('Reorder symbols'));
    await tester.pumpAndSettle();

    expect(find.text('Reorder symbols'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsOneWidget);
    final sheet = find.byType(AppSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('AAPL')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('MSFT')),
      findsOneWidget,
    );
  });

  testWidgets('guides an empty watchlist towards adding a symbol', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(TargetPlatform.android, items: const []));
    await tester.pumpAndSettle();

    expect(find.text('No watchlist symbols'), findsOneWidget);
    await tester.tap(find.widgetWithText(FButton, 'Add symbol'));
    await _pumpSheet(tester);
    expect(find.text('Add to watchlist'), findsOneWidget);
  });

  testWidgets('offers a way out when a filter matches nothing', (tester) async {
    await _preferences.setString(
      kWatchlistFreshnessFilterPreferenceKey,
      'live',
    );
    final router = _watchlistRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _routerWrap(
        router: router,
        items: [_item, _otherItem],
        snapshots: [_advancingSnapshot],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No matching symbols'), findsOneWidget);
    await tester.tap(find.widgetWithText(FButton, 'Clear filters'));
    await tester.pumpAndSettle();

    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsOneWidget);
  });

  testWidgets('query changes preserve the route pushed below watchlist', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: FinanceRoutes.wealth,
      routes: [
        GoRoute(
          path: FinanceRoutes.wealth,
          builder: (_, _) => const Scaffold(body: _WatchlistPushHost()),
        ),
        GoRoute(
          path: FinanceRoutes.wealthWatchlist,
          builder: (_, _) => FTheme(
            data: buildAppForuiTheme(brightness: Brightness.light, touch: true),
            child: const WatchlistPage(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _routerWrap(
        router: router,
        items: [_item, _otherItem],
        collections: [_collection],
        members: [_membership],
        snapshots: [_advancingSnapshot, _decliningSnapshot],
        scopedSnapshots: [_advancingSnapshot],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open watchlist'));
    await tester.pumpAndSettle();
    expect(find.byType(WatchlistPage), findsOneWidget);

    final collectionChip = find.text('Growth (1)');
    await tester.ensureVisible(collectionChip);
    await tester.pumpAndSettle();
    await tester.tap(collectionChip);
    await tester.pumpAndSettle();

    expect(router.canPop(), isTrue);
    expect(find.byType(WatchlistPage), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Portfolio hub'), findsOneWidget);
  });
}

/// Opening an unowned symbol must not create an asset as a navigation side effect.
class _EmptyAssets implements ManualAssetRepository {
  @override
  Future<Asset?> findById(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WatchlistPushHost extends StatelessWidget {
  const _WatchlistPushHost();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Portfolio hub'),
        TextButton(
          onPressed: () => context.push(FinanceRoutes.wealthWatchlist),
          child: const Text('Open watchlist'),
        ),
      ],
    );
  }
}
