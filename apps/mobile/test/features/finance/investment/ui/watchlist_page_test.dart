import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/ui/watchlist_page.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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

Widget _wrap(TargetPlatform platform) {
  final touch = platform == TargetPlatform.android;
  return ProviderScope(
    overrides: [
      watchlistItemsProvider.overrideWith((_) => Stream.value([_item])),
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
    final action = find.byType(AppIconButton);
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
    final action = find.byType(AppIconButton);
    expect(tester.getSize(action), const Size.square(40));
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
}
