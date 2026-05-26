import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/hlc.dart';
import 'package:naviwealth/features/finance/data/domain/posting.dart';
import 'package:naviwealth/features/finance/data/domain/sync_meta.dart';
import 'package:naviwealth/features/shared/postings_preview.dart';

const _hlc = Hlc(wallMillis: 1700000000000, counter: 0, nodeId: 'dev');
final _sync = SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'dev',
  hlc: _hlc,
);

Account _account({
  required String id,
  required String name,
  AccountSide category = AccountSide.asset,
  String? parentId,
}) => Account(
  id: id,
  type: AccountCategory.asset,
  name: name,
  currency: 'USD',
  category: category,
  parentId: parentId,
  sync: _sync,
);

Posting _p({
  required String accountId,
  required Decimal units,
  required String unit,
  Cost? cost,
  Price? price,
  int position = 0,
}) => Posting(
  id: 'p-$position',
  journalEntryId: 'je-test',
  position: position,
  accountId: accountId,
  units: units,
  unit: unit,
  cost: cost,
  price: price,
  sync: _sync,
);

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
  locale: const Locale('en', 'US'),
  home: Scaffold(
    body: SizedBox(
      width: 400,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

void main() {
  testWidgets('renders three legs of a buy with cost annotation', (
    tester,
  ) async {
    final accounts = <String, Account>{
      'a-bro': _account(id: 'a-bro', name: 'Brokerage'),
      'a-fee': _account(
        id: 'a-fee',
        name: 'Trading Fee',
        category: AccountSide.expense,
        parentId: 'a-trading',
      ),
      'a-trading': _account(
        id: 'a-trading',
        name: 'Trading',
        category: AccountSide.expense,
        parentId: 'a-expense-root',
      ),
      'a-expense-root': _account(
        id: 'a-expense-root',
        name: 'Expenses',
        category: AccountSide.expense,
      ),
    };
    final postings = [
      _p(
        accountId: 'a-bro',
        units: Decimal.parse('100'),
        unit: 'NASDAQ:AAPL',
        cost: Cost(perUnit: Decimal.parse('150'), currency: 'USD'),
      ),
      _p(
        accountId: 'a-fee',
        units: Decimal.parse('5'),
        unit: 'USD',
        position: 1,
      ),
      _p(
        accountId: 'a-bro',
        units: Decimal.parse('-15005'),
        unit: 'USD',
        position: 2,
      ),
    ];

    await tester.pumpWidget(
      _wrap(
        PostingsPreview(
          postings: postings,
          accounts: accounts,
          title: 'Buy 100 AAPL',
        ),
      ),
    );

    expect(find.text('Buy 100 AAPL'), findsOneWidget);
    // Brokerage row present + cost annotation (lotId omitted).
    expect(find.text('Brokerage'), findsAtLeastNWidgets(1));
    expect(find.text('+100 AAPL'), findsAtLeastNWidgets(1));
    expect(find.text('{150 USD}'), findsOneWidget);
    // Nested fee account shows the full breadcrumb path.
    expect(find.text('Expenses › Trading › Trading Fee'), findsOneWidget);
    expect(find.text('+\$5'), findsOneWidget);
    expect(find.text('-\$15,005'), findsOneWidget);
  });

  testWidgets('unit-balance footer renders a Σ row only for unbalanced units', (
    tester,
  ) async {
    final accounts = <String, Account>{
      'a-cash': _account(id: 'a-cash', name: 'Cash'),
      'a-bro': _account(id: 'a-bro', name: 'Brokerage'),
    };
    // Two cash legs sum to -1; the AAPL legs cancel out at zero.
    final postings = [
      _p(
        accountId: 'a-bro',
        units: Decimal.parse('100'),
        unit: 'NASDAQ:AAPL',
        cost: Cost(perUnit: Decimal.parse('150'), currency: 'USD'),
      ),
      _p(
        accountId: 'a-bro',
        units: Decimal.parse('-100'),
        unit: 'NASDAQ:AAPL',
        cost: Cost(perUnit: Decimal.parse('150'), currency: 'USD'),
        position: 1,
      ),
      _p(
        accountId: 'a-cash',
        units: Decimal.parse('100'),
        unit: 'USD',
        position: 2,
      ),
      _p(
        accountId: 'a-cash',
        units: Decimal.parse('-101'),
        unit: 'USD',
        position: 3,
      ),
    ];
    await tester.pumpWidget(
      _wrap(PostingsPreview(postings: postings, accounts: accounts)),
    );
    // AAPL is balanced (sum = 0) → no Σ row.
    expect(find.text('Σ NASDAQ:AAPL'), findsNothing);
    // USD is off by 1 → Σ row visible with the residual.
    expect(find.text('Σ USD'), findsOneWidget);
    expect(find.text('-\$1'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.circleAlert), findsOneWidget);
  });

  testWidgets('balanced posting set renders without a Σ footer', (
    tester,
  ) async {
    final accounts = <String, Account>{
      'a-from': _account(id: 'a-from', name: 'A'),
      'a-to': _account(id: 'a-to', name: 'B'),
    };
    final postings = [
      _p(accountId: 'a-from', units: Decimal.parse('-1000'), unit: 'CNY'),
      _p(
        accountId: 'a-to',
        units: Decimal.parse('1000'),
        unit: 'CNY',
        position: 1,
      ),
    ];
    await tester.pumpWidget(
      _wrap(PostingsPreview(postings: postings, accounts: accounts)),
    );
    expect(find.byIcon(FLucideIcons.circleCheck), findsNothing);
    expect(find.byIcon(FLucideIcons.circleAlert), findsNothing);
    expect(find.text('Σ CNY'), findsNothing);
  });

  testWidgets('unknown account id falls back to the bare id', (tester) async {
    final postings = [
      _p(accountId: 'mystery', units: Decimal.parse('5'), unit: 'USD'),
      _p(
        accountId: 'mystery',
        units: Decimal.parse('-5'),
        unit: 'USD',
        position: 1,
      ),
    ];
    await tester.pumpWidget(
      _wrap(
        PostingsPreview(
          postings: postings,
          accounts: const <String, Account>{},
        ),
      ),
    );
    // Bare id fallback is rendered when the account dict hasn't caught
    // up with the postings yet (most common during a fresh sync pull).
    expect(find.text('mystery'), findsAtLeastNWidgets(1));
  });

  testWidgets('price annotation surfaces the realised market rate', (
    tester,
  ) async {
    final postings = [
      _p(
        accountId: 'a',
        units: Decimal.parse('-50'),
        unit: 'NASDAQ:AAPL',
        cost: Cost(
          perUnit: Decimal.parse('150'),
          currency: 'USD',
          lotId: 'lot-2026-01',
        ),
        price: Price(perUnit: Decimal.parse('160'), currency: 'USD'),
      ),
    ];
    await tester.pumpWidget(
      _wrap(
        PostingsPreview(
          postings: postings,
          accounts: <String, Account>{
            'a': _account(id: 'a', name: 'Brokerage'),
          },
        ),
      ),
    );
    expect(find.text('{150 USD, lot-2026-01}'), findsOneWidget);
    expect(find.text('@ 160 USD'), findsOneWidget);
  });
}
