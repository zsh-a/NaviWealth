import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/accounts/domain/account_balances.dart';
import 'package:naviwealth/features/accounts/ui/account_grouped_sections.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/hlc.dart';
import 'package:naviwealth/features/finance/data/domain/sync_meta.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

final _sync = SyncMeta(
  ownerUserId: 'u-test',
  updatedAt: DateTime.utc(2026, 1, 1),
  updatedByDevice: 'dev-test',
  hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
);

Account _account({
  required String id,
  required String name,
  AccountCategory type = AccountCategory.bank,
  String currency = 'USD',
  String? institution,
  String? icon,
  String? color,
}) => Account(
  id: id,
  type: type,
  name: name,
  currency: currency,
  institution: institution,
  icon: icon,
  color: color,
  sync: _sync,
);

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUpAll(AppFormatters.ensureInitialized);

  testWidgets('renders Hub-style account cards with shared money text', (
    tester,
  ) async {
    Account? opened;
    final account = _account(
      id: 'checking',
      name: 'Everyday Checking',
      institution: 'Navi Bank',
      icon: 'account_balance',
      color: '#3B82F6',
    );

    await tester.pumpWidget(
      _wrap(
        AccountsGroupedSections(
          accounts: [account],
          balances: {
            account.id: AccountBalances(
              accountId: account.id,
              legs: [
                AccountBalanceLeg(
                  unit: 'USD',
                  units: Decimal.parse('1234.5000'),
                ),
              ],
            ),
          },
          onAccountPressed: (_, account) => opened = account,
        ),
      ),
    );

    expect(find.text('BANK'), findsOneWidget);
    expect(find.text('Everyday Checking'), findsOneWidget);
    expect(find.text('Navi Bank'), findsOneWidget);
    expect(find.text(r'$1,234.5'), findsOneWidget);

    await tester.tap(find.text('Everyday Checking'));
    await tester.pumpAndSettle();
    expect(opened, account);
  });

  testWidgets('expands multi-unit accounts on Hub surfaces', (tester) async {
    var opened = false;
    final account = _account(
      id: 'brokerage',
      name: 'Brokerage',
      type: AccountCategory.broker,
    );

    await tester.pumpWidget(
      _wrap(
        AccountsGroupedSections(
          accounts: [account],
          balances: {
            account.id: AccountBalances(
              accountId: account.id,
              legs: [
                AccountBalanceLeg(unit: 'USD', units: Decimal.one),
                AccountBalanceLeg(
                  unit: 'us_stock:AAPL',
                  units: Decimal.parse('10.0000'),
                ),
              ],
            ),
          },
          allowExpansion: true,
          onAccountPressed: (_, _) => opened = true,
        ),
      ),
    );

    expect(find.text('10 AAPL'), findsNothing);

    await tester.tap(find.text('Brokerage'));
    await tester.pumpAndSettle();

    expect(opened, isFalse);
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('10 AAPL'), findsOneWidget);
  });
}
