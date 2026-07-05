import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/shared/ui/account_tree_picker.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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
  AccountCategory type = AccountCategory.asset,
  AccountSide category = AccountSide.expense,
  String currency = 'CNY',
  String? parentId,
  bool archived = false,
  DateTime? deletedAt,
  String? icon,
  String? color,
}) => Account(
  id: id,
  type: type,
  name: name,
  currency: currency,
  category: category,
  parentId: parentId,
  icon: icon,
  color: color,
  archived: archived,
  sync: SyncMeta(
    ownerUserId: 'u',
    updatedAt: _sync.updatedAt,
    updatedByDevice: 'dev',
    hlc: _hlc,
    deletedAt: deletedAt,
  ),
);

Widget _wrap(Widget child, {Locale locale = const Locale('en', 'US')}) =>
    MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: FTheme(
        data: FThemes.slate.light.desktop,
        child: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );

void main() {
  testWidgets('renders breadcrumb path for nested accounts', (tester) async {
    final accounts = <Account>[
      _account(id: 'expense', name: 'Expenses'),
      _account(id: 'expense:trading', name: 'Trading', parentId: 'expense'),
      _account(
        id: 'expense:trading:fee',
        name: 'Trading Fee',
        parentId: 'expense:trading',
      ),
    ];

    String? selected;
    await tester.pumpWidget(
      _wrap(
        AccountTreePicker(
          accounts: accounts,
          value: null,
          onChanged: (v) => selected = v,
        ),
      ),
    );

    // The dropdown is closed by default; tap to open and verify all
    // three rows appear with the expected breadcrumb path.
    await tester.tap(find.byType(AccountTreePicker));
    await tester.pumpAndSettle();
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Expenses › Trading'), findsOneWidget);
    expect(find.text('Expenses › Trading › Trading Fee'), findsOneWidget);

    await tester.tap(find.text('Expenses › Trading › Trading Fee'));
    await tester.pumpAndSettle();
    expect(selected, 'expense:trading:fee');
  });

  testWidgets('category filter narrows the list', (tester) async {
    final accounts = <Account>[
      _account(id: 'expense', name: 'Expenses'),
      _account(id: 'income', name: 'Income', category: AccountSide.income),
    ];

    await tester.pumpWidget(
      _wrap(
        AccountTreePicker(
          accounts: accounts,
          value: null,
          onChanged: (_) {},
          category: AccountSide.expense,
        ),
      ),
    );

    await tester.tap(find.byType(AccountTreePicker));
    await tester.pumpAndSettle();
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Income'), findsNothing);
  });

  testWidgets('leafOnly hides grouping nodes and deduplicates paths', (
    tester,
  ) async {
    final accounts = <Account>[
      _account(id: 'system-account:u:expense', name: 'System Expenses'),
      _account(
        id: 'system-account:u:expense:trading',
        name: 'Trading',
        parentId: 'system-account:u:expense',
      ),
      _account(
        id: 'system-account:u:expense:trading:fee',
        name: 'Trading Fee',
        parentId: 'system-account:u:expense:trading',
      ),
      _account(
        id: 'user:expense:trading:fee',
        name: 'Trading Fee',
        parentId: 'system-account:u:expense:trading',
      ),
      _account(
        id: 'system-account:u:expense:trading:interest',
        name: 'Trading Interest',
        parentId: 'system-account:u:expense:trading',
      ),
    ];

    String? selected;
    await tester.pumpWidget(
      _wrap(
        AccountTreePicker(
          accounts: accounts,
          value: null,
          onChanged: (v) => selected = v,
          category: AccountSide.expense,
          leafOnly: true,
        ),
      ),
    );

    await tester.tap(find.byType(AccountTreePicker));
    await tester.pumpAndSettle();

    final fee = find.text('Trading › Trading Fee');
    final interest = find.text('Trading › Trading Interest');
    expect(find.text('System Expenses'), findsNothing);
    expect(find.text('Trading'), findsNothing);
    expect(fee, findsOneWidget);
    expect(interest, findsOneWidget);

    await tester.tap(interest);
    await tester.pumpAndSettle();
    expect(selected, 'system-account:u:expense:trading:interest');
  });

  testWidgets('localizes seeded system account paths', (tester) async {
    final accounts = <Account>[
      _account(id: 'system-account:u:expense', name: 'System Expenses'),
      _account(
        id: 'system-account:u:expense:trading',
        name: 'Trading',
        parentId: 'system-account:u:expense',
      ),
      _account(
        id: 'system-account:u:expense:trading:fee',
        name: 'Trading Fee',
        parentId: 'system-account:u:expense:trading',
      ),
    ];

    await tester.pumpWidget(
      _wrap(
        AccountTreePicker(
          accounts: accounts,
          value: 'system-account:u:expense:trading:fee',
          onChanged: (_) {},
          category: AccountSide.expense,
          leafOnly: true,
        ),
        locale: const Locale('zh', 'CN'),
      ),
    );

    expect(find.text('交易 › 手续费'), findsOneWidget);
    expect(find.text('Trading › Trading Fee'), findsNothing);
  });

  testWidgets('archived and deleted rows are hidden by default', (
    tester,
  ) async {
    final accounts = <Account>[
      _account(id: 'live', name: 'Live'),
      _account(id: 'arch', name: 'Archived', archived: true),
      _account(id: 'gone', name: 'Gone', deletedAt: DateTime.utc(2026, 4)),
    ];

    await tester.pumpWidget(
      _wrap(
        AccountTreePicker(accounts: accounts, value: null, onChanged: (_) {}),
      ),
    );
    await tester.tap(find.byType(AccountTreePicker));
    await tester.pumpAndSettle();
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Archived'), findsNothing);
    expect(find.text('Gone'), findsNothing);
  });

  testWidgets('allowSystemAccounts=false hides system-account rows', (
    tester,
  ) async {
    final accounts = <Account>[
      _account(id: 'a-user-bank', name: 'My Bank'),
      _account(id: 'system-account:u:expense', name: 'Expenses System'),
    ];

    await tester.pumpWidget(
      _wrap(
        AccountTreePicker(
          accounts: accounts,
          value: null,
          onChanged: (_) {},
          allowSystemAccounts: false,
        ),
      ),
    );
    await tester.tap(find.byType(AccountTreePicker));
    await tester.pumpAndSettle();
    expect(find.text('My Bank'), findsOneWidget);
    expect(find.text('Expenses System'), findsNothing);
  });

  testWidgets('value not in current list is reset to null', (tester) async {
    // The picker is fed accounts that don't include the supplied
    // value (e.g. the user just deleted the previously-selected
    // account). The widget must render without throwing — Material
    // throws if the dropdown's value isn't one of its items.
    final accounts = <Account>[_account(id: 'a', name: 'A')];
    await tester.pumpWidget(
      _wrap(
        AccountTreePicker(
          accounts: accounts,
          value: 'no-such-account',
          onChanged: (_) {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('helperText surfaces below the field', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AccountTreePicker(
          accounts: <Account>[_account(id: 'a', name: 'A')],
          value: null,
          onChanged: (_) {},
          helperText: 'Pick a category',
        ),
      ),
    );
    expect(find.text('Pick a category'), findsOneWidget);
  });

  testWidgets(
    'renders a leading icon when account.icon resolves to the catalogue',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          AccountTreePicker(
            accounts: [
              _account(
                id: 'a',
                name: 'Bank',
                icon: 'account_balance',
                color: '#3B82F6',
              ),
            ],
            value: null,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.byType(AccountTreePicker));
      await tester.pumpAndSettle();
      // The catalogued icon shows up; the bullet-glyph fallback does
      // *not* as part of the title (otherwise the row reads as `• Bank`
      // which would duplicate the leading affordance).
      expect(find.byIcon(FLucideIcons.landmark), findsAtLeastNWidgets(1));
      expect(find.text('• Bank'), findsNothing);
    },
  );

  testWidgets('falls back to bullet glyph when account.icon is unknown', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AccountTreePicker(
          accounts: [_account(id: 'a', name: 'Bank', icon: 'no_such_icon')],
          value: null,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byType(AccountTreePicker));
    await tester.pumpAndSettle();
    expect(find.text('•'), findsAtLeastNWidgets(1));
    expect(find.text('Bank'), findsOneWidget);
  });
}
