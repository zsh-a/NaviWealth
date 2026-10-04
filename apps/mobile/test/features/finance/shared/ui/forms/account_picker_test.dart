import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/account_picker.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u-test',
  updatedAt: DateTime.utc(2026, 1, 1),
  updatedByDevice: 'dev-test',
  hlc: Hlc.zero('dev-test'),
);

Account _account(String id, String name, String currency) {
  return Account(
    id: id,
    type: AccountCategory.bank,
    name: name,
    currency: currency,
    sync: _meta(),
  );
}

Widget _wrap(Widget child, {Locale locale = const Locale('en', 'US')}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets(
    'searches by name and currency and keeps selection on no results',
    (tester) async {
      String? selected = 'checking';
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) => AccountPicker(
              accounts: [
                _account('checking', 'Checking', 'CNY'),
                _account('broker', 'Brokerage cash', 'USD'),
                _account('savings', 'Savings', 'USD'),
              ],
              value: selected,
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Checking · CNY'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, '  uSd broker  ');
      await tester.pumpAndSettle();
      expect(find.text('Brokerage cash · USD'), findsOneWidget);
      expect(find.text('Savings · USD'), findsNothing);
      await tester.tap(find.text('Brokerage cash · USD'));
      await tester.pumpAndSettle();
      expect(selected, 'broker');
      await tester.tap(find.text('Brokerage cash · USD'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'missing account');
      await tester.pumpAndSettle();
      expect(
        find.text('No matching accounts. Try another name or currency.'),
        findsOneWidget,
      );
      expect(selected, 'broker');
      await tester.enterText(find.byType(EditableText).last, '');
      await tester.pumpAndSettle();
      expect(find.text('Savings · USD'), findsOneWidget);
    },
  );

  testWidgets(
    'search preserves distinct ids for accounts with the same label',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        _wrap(
          AccountPicker(
            accounts: [
              _account('cash-1', 'Cash', 'CNY'),
              _account('cash-2', 'Cash', 'CNY'),
            ],
            value: null,
            onChanged: (value) => selected = value,
          ),
        ),
      );
      await tester.tap(find.byType(AccountPicker));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'cash');
      await tester.pumpAndSettle();
      expect(find.text('Cash · CNY'), findsNWidgets(2));
      await tester.tap(find.text('Cash · CNY').last);
      await tester.pumpAndSettle();
      expect(selected, 'cash-2');
    },
  );

  for (final required in [true, false]) {
    testWidgets('empty account validates only when optional: $required', (
      tester,
    ) async {
      final formKey = GlobalKey<FormState>();
      await tester.pumpWidget(
        _wrap(
          Form(
            key: formKey,
            child: AccountPicker(
              accounts: [_account('bank', 'Bank', 'CNY')],
              value: null,
              onChanged: (_) {},
              required: required,
            ),
          ),
        ),
      );
      expect(formKey.currentState!.validate(), !required);
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AccountPicker));
      expect(
        find.text(AppLocalizations.of(context).formAccountPickerRequired),
        required ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('renders selected account when labels are duplicated', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AccountPicker(
          accounts: [
            _account('cash-1', 'Cash', 'CNY'),
            _account('cash-2', 'Cash', 'CNY'),
          ],
          value: 'cash-1',
          onChanged: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Cash · CNY'), findsOneWidget);
  });

  testWidgets('localizes seeded system account labels', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AccountPicker(
          accounts: [
            _account(
              'system-account:u-test:expense:trading:fee',
              'Trading Fee',
              'CNY',
            ),
          ],
          value: 'system-account:u-test:expense:trading:fee',
          onChanged: (_) {},
        ),
        locale: const Locale('zh', 'CN'),
      ),
    );

    expect(find.text('手续费 · CNY'), findsOneWidget);
    expect(find.text('Trading Fee · CNY'), findsNothing);
  });

  testWidgets('updates displayed account when lifted value changes', (
    tester,
  ) async {
    final accounts = [
      _account('cash-1', 'Checking', 'CNY'),
      _account('cash-2', 'Brokerage cash', 'USD'),
    ];

    await tester.pumpWidget(
      _wrap(
        AccountPicker(accounts: accounts, value: 'cash-1', onChanged: (_) {}),
      ),
    );
    expect(find.text('Checking · CNY'), findsOneWidget);

    await tester.pumpWidget(
      _wrap(
        AccountPicker(accounts: accounts, value: 'cash-2', onChanged: (_) {}),
      ),
    );
    await tester.pump();

    expect(find.text('Brokerage cash · USD'), findsOneWidget);
    expect(find.text('Checking · CNY'), findsNothing);
  });
}
