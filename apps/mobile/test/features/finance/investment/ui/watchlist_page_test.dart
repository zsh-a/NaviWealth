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
import 'package:naviwealth/features/finance/investment/ui/watchlist_page.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
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

final _collection = WatchlistCollection(
  id: 'collection-growth',
  name: 'Growth',
  createdAt: DateTime.utc(2026, 7, 19),
  sync: _item.sync,
);

final _membership = WatchlistCollectionMember(
  id: 'membership-aapl-growth',
  collectionId: _collection.id,
  watchlistItemId: _item.id,
  addedAt: DateTime.utc(2026, 7, 19),
  sync: _item.sync,
);

Widget _wrap(TargetPlatform platform) {
  final touch = platform == TargetPlatform.android;
  return ProviderScope(
    overrides: [
      watchlistItemsProvider.overrideWith((_) => Stream.value([_item])),
      watchlistCollectionsProvider.overrideWith((_) => Stream.value(const [])),
      watchlistCollectionMembersProvider.overrideWith(
        (_) => Stream.value(const []),
      ),
      watchlistQuoteSnapshotsProvider.overrideWith((_) async => const []),
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
          watchlistQuoteSnapshotsProvider.overrideWith((_) async => const []),
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
          watchlistItemsProvider.overrideWith(
            (_) => Stream.value([_item, _otherItem]),
          ),
          watchlistCollectionsProvider.overrideWith(
            (_) => Stream.value([_collection]),
          ),
          watchlistCollectionMembersProvider.overrideWith(
            (_) => Stream.value([_membership]),
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

    expect(find.text('Growth'), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MSFT'), findsNothing);

    await tester.tap(find.text('Ungrouped'));
    await tester.pumpAndSettle();

    expect(find.text('MSFT'), findsOneWidget);
    expect(find.text('AAPL'), findsNothing);
    expect(router.routeInformationProvider.value.uri.queryParameters, {
      'collection': 'ungrouped',
    });
  });
}
