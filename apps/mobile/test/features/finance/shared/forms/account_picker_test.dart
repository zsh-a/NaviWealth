import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/shared/forms/account_picker.dart';
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
      data: FThemes.slate.light.desktop,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
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
