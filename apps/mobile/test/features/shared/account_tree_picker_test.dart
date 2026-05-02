import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/shared/account_tree_picker.dart';

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
  AccountType type = AccountType.other,
  AccountCategory category = AccountCategory.expense,
  String currency = 'CNY',
  String? parentId,
  bool archived = false,
  DateTime? deletedAt,
}) =>
    Account(
      id: id,
      type: type,
      name: name,
      currency: currency,
      category: category,
      parentId: parentId,
      archived: archived,
      sync: SyncMeta(
        ownerUserId: 'u',
        updatedAt: _sync.updatedAt,
        updatedByDevice: 'dev',
        hlc: _hlc,
        deletedAt: deletedAt,
      ),
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
  home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
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
    expect(find.text('• Expenses'), findsOneWidget);
    expect(find.text('› Expenses › Trading'), findsOneWidget);
    expect(find.text('› Expenses › Trading › Trading Fee'), findsOneWidget);

    await tester.tap(find.text('› Expenses › Trading › Trading Fee'));
    await tester.pumpAndSettle();
    expect(selected, 'expense:trading:fee');
  });

  testWidgets('category filter narrows the list', (tester) async {
    final accounts = <Account>[
      _account(id: 'expense', name: 'Expenses'),
      _account(
        id: 'income',
        name: 'Income',
        category: AccountCategory.income,
      ),
    ];

    await tester.pumpWidget(
      _wrap(
        AccountTreePicker(
          accounts: accounts,
          value: null,
          onChanged: (_) {},
          category: AccountCategory.expense,
        ),
      ),
    );

    await tester.tap(find.byType(AccountTreePicker));
    await tester.pumpAndSettle();
    expect(find.text('• Expenses'), findsOneWidget);
    expect(find.text('• Income'), findsNothing);
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
        AccountTreePicker(
          accounts: accounts,
          value: null,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byType(AccountTreePicker));
    await tester.pumpAndSettle();
    expect(find.text('• Live'), findsOneWidget);
    expect(find.text('• Archived'), findsNothing);
    expect(find.text('• Gone'), findsNothing);
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
    expect(find.text('• My Bank'), findsOneWidget);
    expect(find.text('• Expenses System'), findsNothing);
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
}
