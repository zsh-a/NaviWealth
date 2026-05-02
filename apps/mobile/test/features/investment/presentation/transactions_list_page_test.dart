import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/domain/transaction.dart';
import 'package:naviwealth/features/investment/data/providers.dart';
import 'package:naviwealth/features/investment/presentation/transactions_list_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

SyncMeta _meta() => SyncMeta(
      ownerUserId: 'u',
      updatedAt: DateTime.utc(2026, 5, 1),
      updatedByDevice: 'dev',
      hlc: Hlc.zero('dev'),
    );

Transaction _tx({
  required String id,
  String assetId = 'us_stock:AAPL',
  TransactionType type = TransactionType.buy,
  String quantity = '10',
  String price = '180',
  required DateTime tradeDate,
}) {
  return Transaction(
    id: id,
    accountId: 'acct-1',
    assetId: assetId,
    type: type,
    quantity: Decimal.parse(quantity),
    price: Decimal.parse(price),
    currency: 'USD',
    tradeDate: tradeDate,
    sync: _meta(),
  );
}

Asset _asset({String id = 'us_stock:AAPL', String symbol = 'AAPL'}) {
  return Asset(
    id: id,
    type: AssetType.stock,
    symbol: symbol,
    currency: 'USD',
    name: 'Apple Inc.',
    market: 'us_stock',
    sync: _meta(),
  );
}

Widget _harness({
  required List<Transaction> transactions,
  List<Asset> assets = const [],
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const TransactionsListPage()),
    ],
    errorBuilder: (_, _) => const SizedBox.shrink(),
  );
  return ProviderScope(
    overrides: [
      transactionsStreamProvider
          .overrideWith((ref) => Stream.value(transactions)),
      allAssetsStreamProvider.overrideWith((ref) => Stream.value(assets)),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('renders empty hint when no transactions exist', (tester) async {
    await tester.pumpWidget(_harness(transactions: const []));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionsListPage), findsOneWidget);
    expect(find.byKey(const Key('transactions-add-fab')), findsOneWidget);
    // Empty hint is rendered (any of the localized variants).
    expect(find.byIcon(Icons.swap_horiz_outlined), findsOneWidget);
  });

  testWidgets('groups transactions by month and shows asset symbol + chip',
      (tester) async {
    await tester.pumpWidget(_harness(
      transactions: [
        _tx(id: 't-1', tradeDate: DateTime.utc(2026, 5, 10)),
        _tx(
          id: 't-2',
          type: TransactionType.sell,
          tradeDate: DateTime.utc(2026, 5, 1),
        ),
        _tx(
          id: 't-3',
          tradeDate: DateTime.utc(2026, 4, 20),
        ),
      ],
      assets: [_asset()],
    ));
    await tester.pumpAndSettle();

    // Both rows appear, plus their separator headers.
    expect(find.byKey(const Key('transactions-row-t-1')), findsOneWidget);
    expect(find.byKey(const Key('transactions-row-t-2')), findsOneWidget);
    expect(find.byKey(const Key('transactions-row-t-3')), findsOneWidget);
    // Two month groups.
    expect(find.byKey(const Key('transactions-header-2026-05')), findsOneWidget);
    expect(find.byKey(const Key('transactions-header-2026-04')), findsOneWidget);
    // Asset symbol surfaces in the row title.
    expect(find.text('AAPL'), findsWidgets);
  });

  testWidgets('FAB key is wired so the trade form is reachable', (tester) async {
    await tester.pumpWidget(_harness(transactions: const []));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transactions-add-fab')), findsOneWidget);
  });
}
