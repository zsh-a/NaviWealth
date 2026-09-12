import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/composition/finance_command_palette.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final entries = financeCommandPaletteEntries(l10n);

  test('registers every destination under a unique id', () {
    final ids = entries.map((entry) => entry.id).toList();

    expect(ids.toSet(), hasLength(ids.length));
  });

  test('exposes the watchlist as a first-class destination', () {
    final watchlist = entries.where((entry) => entry.id == 'nav.watchlist');

    expect(watchlist, hasLength(1));
    expect(watchlist.single.label, 'Watchlist');
    expect(watchlist.single.subtitle, isNotEmpty);
  });

  test('the watchlist is reachable from English and Chinese queries', () {
    final watchlist = entries.firstWhere((entry) => entry.id == 'nav.watchlist');

    for (final query in <String>[
      'watchlist',
      'watch',
      'track symbol',
      'price alert',
      '自选',
      '关注',
      '价格提醒',
    ]) {
      expect(watchlist.matches(query), isTrue, reason: 'query: $query');
    }
  });

  testWidgets('the watchlist command goes to the watchlist route', (
    tester,
  ) async {
    final watchlist = entries.firstWhere((entry) => entry.id == 'nav.watchlist');
    late BuildContext paletteContext;
    final router = GoRouter(
      initialLocation: FinanceRoutes.wealth,
      routes: [
        GoRoute(
          path: FinanceRoutes.wealth,
          builder: (context, _) {
            paletteContext = context;
            return const Scaffold(body: Text('Wealth hub'));
          },
        ),
        GoRoute(
          path: FinanceRoutes.wealthWatchlist,
          builder: (_, _) => const Scaffold(body: Text('Watchlist page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Wealth hub'), findsOneWidget);

    watchlist.run(paletteContext);
    await tester.pumpAndSettle();

    expect(find.text('Watchlist page'), findsOneWidget);
  });
}
