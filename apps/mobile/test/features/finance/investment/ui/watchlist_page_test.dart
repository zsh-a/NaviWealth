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
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_simulation_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_view_preferences.dart';
import 'package:naviwealth/features/finance/investment/ui/watchlist_page.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
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

Widget _wrap(
  TargetPlatform platform, {
  List<WatchlistItem>? items,
  List<WatchlistQuoteSnapshot> snapshots = const [],
  List<WatchlistCollection> collections = const [],
  List<WatchlistCollectionMember> members = const [],
}) {
  final touch = platform == TargetPlatform.android;
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_preferences),
      watchlistItemsProvider.overrideWith(
        (_) => Stream.value(items ?? [_item]),
      ),
      watchlistCollectionsProvider.overrideWith(
        (_) => Stream.value(collections),
      ),
      watchlistCollectionMembersProvider.overrideWith(
        (_) => Stream.value(members),
      ),
      watchlistQuoteSnapshotsProvider.overrideWith((_) async => snapshots),
    ],
    child: MaterialApp(
      theme: AppTheme.light().copyWith(platform: platform),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: FTheme(
        data: buildAppForuiTheme(brightness: Brightness.light, touch: touch),
        child: const WatchlistPage(),
      ),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _preferences = await SharedPreferences.getInstance();
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
    expect(find.text('Add to collections'), findsOneWidget);
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

  testWidgets('shows the localized stock name with its symbol', (tester) async {
    await tester.pumpWidget(_wrap(TargetPlatform.android, items: [_namedItem]));
    await tester.pumpAndSettle();

    expect(find.text('Apple Inc.'), findsOneWidget);
    expect(find.textContaining('AAPL ·'), findsOneWidget);
  });

  testWidgets('opens bulk add and collection target selection', (tester) async {
    await tester.pumpWidget(
      _wrap(TargetPlatform.android, collections: [_collection]),
    );
    await tester.pumpAndSettle();

    final trigger = find.byKey(
      const ValueKey<String>('watchlist-bulk-manage-trigger'),
    );
    await tester.ensureVisible(trigger);
    await tester.pumpAndSettle();
    await tester.tap(trigger);
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

  testWidgets('shows a summary of the loaded quote snapshots', (tester) async {
    await tester.pumpWidget(
      _wrap(TargetPlatform.android, snapshots: [_advancingSnapshot]),
    );
    await tester.pumpAndSettle();

    final summary = find.byKey(
      const ValueKey<String>('watchlist-quote-summary'),
    );
    expect(summary, findsOneWidget);
    final metrics = tester.widget<AppMetricCluster>(
      find.descendant(of: summary, matching: find.byType(AppMetricCluster)),
    );
    expect(metrics.items.map((item) => '${item.label}:${item.value}'), [
      'Symbols:1',
      'Quotes:1 / 1',
      'Advancing:1',
      'Declining:0',
    ]);
    final rowChange = tester.widget<DeltaText>(
      find.byKey(const ValueKey<String>('watchlist-row-change-us_stock:AAPL')),
    );
    expect(rowChange.format, DeltaFormat.percent);
    expect(rowChange.value, closeTo(0.625, 0.000001));

    final analysis = find.byKey(
      const ValueKey<String>('watchlist-collection-analysis'),
    );
    expect(analysis, findsOneWidget);
    final analysisMetrics = tester.widgetList<AppMetricCluster>(
      find.descendant(of: analysis, matching: find.byType(AppMetricCluster)),
    );
    expect(
      analysisMetrics
          .expand((cluster) => cluster.items)
          .map((item) => '${item.label}:${item.value}'),
      [
        'Quote coverage:100%',
        'Median move:+0.63%',
        'Alert coverage:0 / 1',
        'Triggered:0',
      ],
    );
    expect(
      find.descendant(
        of: analysis,
        matching: find.text('Live 0 · Cached 1 · Stale 0 · No price 0'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: analysis,
        matching: find.text('Largest gain: AAPL +0.63%'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('uses a bottom action sheet for row actions on Android', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(TargetPlatform.android));
    await tester.pumpAndSettle();

    expect(find.text('Alerts'), findsNothing);
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
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    expect(find.text('Alerts for AAPL'), findsOneWidget);
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
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('uses a persistent quote detail pane on desktop', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: FinanceRoutes.wealthWatchlist,
      routes: [
        GoRoute(
          path: FinanceRoutes.wealthWatchlist,
          builder: (_, _) => FTheme(
            data: buildAppForuiTheme(
              brightness: Brightness.light,
              touch: false,
            ),
            child: const WatchlistPage(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          watchlistItemsProvider.overrideWith((_) => Stream.value([_item])),
          watchlistCollectionsProvider.overrideWith(
            (_) => Stream.value(const []),
          ),
          watchlistCollectionMembersProvider.overrideWith(
            (_) => Stream.value(const []),
          ),
          watchlistQuoteSnapshotsProvider.overrideWith(
            (_) async => [_advancingSnapshot],
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light().copyWith(platform: TargetPlatform.macOS),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en', 'US'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MasterDetailLayout), findsOneWidget);
    expect(find.textContaining('Select a symbol'), findsOneWidget);
    await tester.tap(find.text('AAPL').first);
    await tester.pumpAndSettle();

    expect(find.text('AAPL'), findsNWidgets(2));
    expect(find.text('Alerts'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>('watchlist-detail-change-us_stock:AAPL'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('sorts the current scope through the URL', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _preferences.setString(kWatchlistSortPreferenceKey, 'gainers');
    final router = GoRouter(
      initialLocation: '${FinanceRoutes.wealthWatchlist}?sort=change-asc',
      routes: [
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
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_preferences),
          watchlistItemsProvider.overrideWith(
            (_) => Stream.value([_item, _otherItem]),
          ),
          watchlistCollectionsProvider.overrideWith(
            (_) => Stream.value(const []),
          ),
          watchlistCollectionMembersProvider.overrideWith(
            (_) => Stream.value(const []),
          ),
          watchlistQuoteSnapshotsProvider.overrideWith(
            (_) async => [_advancingSnapshot, _decliningSnapshot],
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en', 'US'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('MSFT')).dy,
      lessThan(tester.getTopLeft(find.text('AAPL')).dy),
    );

    final sortTrigger = find.byKey(
      const ValueKey<String>('watchlist-sort-trigger'),
    );
    await tester.ensureVisible(sortTrigger);
    await tester.pumpAndSettle();
    await tester.tap(sortTrigger);
    await tester.pumpAndSettle();
    expect(find.byType(AppSheet), findsOneWidget);
    await tester.tap(find.text('Gainers first'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('AAPL')).dy,
      lessThan(tester.getTopLeft(find.text('MSFT')).dy),
    );
    expect(router.routeInformationProvider.value.uri.queryParameters, {
      'sort': 'change-desc',
    });
    expect(_preferences.getString(kWatchlistSortPreferenceKey), 'gainers');
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
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_preferences),
          watchlistItemsProvider.overrideWith(
            (_) => Stream.value([_item, _otherItem]),
          ),
          watchlistCollectionsProvider.overrideWith(
            (_) => Stream.value([_collection]),
          ),
          watchlistCollectionMembersProvider.overrideWith(
            (_) => Stream.value([_membership]),
          ),
          watchlistSimulationsProvider.overrideWith(
            (_) => Stream.value(const []),
          ),
          watchlistQuoteSnapshotsProvider.overrideWith(
            (_) async => [_advancingSnapshot, _decliningSnapshot],
          ),
          watchlistQuoteSnapshotsForScopeProvider.overrideWith(
            (_, _) async => [_advancingSnapshot],
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en', 'US'),
        ),
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

  testWidgets('filters collection and ungrouped scopes through the URL', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation:
          '${FinanceRoutes.wealthWatchlist}?collection=${_collection.id}',
      routes: [
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
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_preferences),
          watchlistItemsProvider.overrideWith(
            (_) => Stream.value([_item, _otherItem]),
          ),
          watchlistCollectionsProvider.overrideWith(
            (_) => Stream.value([_collection]),
          ),
          watchlistCollectionMembersProvider.overrideWith(
            (_) => Stream.value([_membership]),
          ),
          watchlistSimulationsProvider.overrideWith(
            (_) => Stream.value(const []),
          ),
          watchlistQuoteSnapshotsProvider.overrideWith((_) async => const []),
          watchlistQuoteSnapshotsForScopeProvider.overrideWith(
            (_, _) async => const [],
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en', 'US'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Growth (1)'), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsNothing);

    await tester.tap(find.text('Ungrouped (1)'));
    await tester.pumpAndSettle();

    expect(find.text('MSFT'), findsOneWidget);
    expect(find.text('AAPL'), findsNothing);
    expect(router.routeInformationProvider.value.uri.queryParameters, {
      'collection': 'ungrouped',
    });
    expect(
      _preferences.getString(kWatchlistCollectionPreferenceKey),
      'ungrouped',
    );
  });

  testWidgets('restores the last valid collection without URL state', (
    tester,
  ) async {
    await _preferences.setString(
      kWatchlistCollectionPreferenceKey,
      'collection:${_collection.id}',
    );
    final router = GoRouter(
      initialLocation: FinanceRoutes.wealthWatchlist,
      routes: [
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
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_preferences),
          watchlistItemsProvider.overrideWith(
            (_) => Stream.value([_item, _otherItem]),
          ),
          watchlistCollectionsProvider.overrideWith(
            (_) => Stream.value([_collection]),
          ),
          watchlistCollectionMembersProvider.overrideWith(
            (_) => Stream.value([_membership]),
          ),
          watchlistSimulationsProvider.overrideWith(
            (_) => Stream.value(const []),
          ),
          watchlistQuoteSnapshotsForScopeProvider.overrideWith(
            (_, _) async => const [],
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en', 'US'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Growth (1)'), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsNothing);
    expect(router.routeInformationProvider.value.uri.queryParameters, isEmpty);
  });

  testWidgets('applies and clears quote freshness filters through the URL', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: FinanceRoutes.wealthWatchlist,
      routes: [
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
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_preferences),
          watchlistItemsProvider.overrideWith(
            (_) => Stream.value([_item, _otherItem]),
          ),
          watchlistCollectionsProvider.overrideWith(
            (_) => Stream.value(const []),
          ),
          watchlistCollectionMembersProvider.overrideWith(
            (_) => Stream.value(const []),
          ),
          watchlistQuoteSnapshotsProvider.overrideWith(
            (_) async => [_advancingSnapshot],
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en', 'US'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final filterTrigger = find.byKey(
      const ValueKey<String>('watchlist-filter-trigger'),
    );
    await tester.ensureVisible(filterTrigger);
    await tester.tap(filterTrigger);
    await tester.pumpAndSettle();
    var sheet = find.byType(AppSheet);
    var noPrice = find.descendant(of: sheet, matching: find.text('No price'));
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
    expect(router.routeInformationProvider.value.uri.queryParameters, {
      'freshness': 'unavailable',
    });

    await tester.ensureVisible(filterTrigger);
    await tester.tap(filterTrigger);
    await tester.pumpAndSettle();
    sheet = find.byType(AppSheet);
    final clearFilters = find.descendant(
      of: sheet,
      matching: find.text('Clear filters'),
    );
    applyFilters = find.descendant(
      of: sheet,
      matching: find.text('Apply filters'),
    );
    await tester.ensureVisible(clearFilters);
    await tester.tap(clearFilters);
    await tester.ensureVisible(applyFilters);
    await tester.tap(applyFilters);
    await tester.pumpAndSettle();

    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.queryParameters, isEmpty);
  });

  testWidgets('opens collection ordering from the watchlist toolbar', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        TargetPlatform.android,
        collections: [_collection, _otherCollection],
      ),
    );
    await tester.pumpAndSettle();

    final trigger = find.byKey(
      const ValueKey<String>('watchlist-reorder-collections'),
    );
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
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
    final router = GoRouter(
      initialLocation: FinanceRoutes.wealthWatchlist,
      routes: [
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
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_preferences),
          watchlistItemsProvider.overrideWith(
            (_) => Stream.value([_item, _otherItem]),
          ),
          watchlistCollectionsProvider.overrideWith(
            (_) => Stream.value([_collection]),
          ),
          watchlistCollectionMembersProvider.overrideWith(
            (_) => Stream.value([_membership, _otherMembership]),
          ),
          watchlistSimulationsProvider.overrideWith(
            (_) => Stream.value(const []),
          ),
          watchlistQuoteSnapshotsForScopeProvider.overrideWith(
            (_, _) async => const [],
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light().copyWith(platform: TargetPlatform.android),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en', 'US'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final trigger = find.byKey(
      const ValueKey<String>('watchlist-reorder-symbols'),
    );
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
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
