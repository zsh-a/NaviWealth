import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/expense/ui/expense_form_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u-test',
  updatedAt: DateTime.utc(2026, 1, 1),
  updatedByDevice: 'dev-test',
  hlc: Hlc.zero('dev-test'),
);

Account _account({
  required String id,
  required String name,
  required AccountSide category,
  AccountCategory type = AccountCategory.bank,
  String currency = 'CNY',
}) {
  return Account(
    id: id,
    type: type,
    name: name,
    currency: currency,
    category: category,
    sync: _meta(),
  );
}

Future<Widget> _wrap({
  required List<Account> accounts,
  required List<Account> allAccounts,
  required Map<String, Object> preferences,
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      accountsStreamProvider.overrideWith((_) => Stream.value(accounts)),
      allAccountsStreamProvider.overrideWith((_) => Stream.value(allAccounts)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: FTheme(
        data: FThemes.slate.light.desktop,
        child: const ExpenseFormPage(),
      ),
    ),
  );
}

void main() {
  testWidgets('expense creation renders with a remembered uncommon currency', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      await _wrap(
        preferences: const {
          'naviwealth.forms.expense.account': 'cash-1',
          'naviwealth.forms.expense.category': 'food',
          'naviwealth.forms.expense.currency': 'CHF',
        },
        accounts: [
          _account(id: 'cash-1', name: 'Cash', category: AccountSide.asset),
          _account(id: 'cash-2', name: 'Cash', category: AccountSide.asset),
        ],
        allAccounts: [
          _account(id: 'food', name: 'Food', category: AccountSide.expense),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ExpenseFormPage), findsOneWidget);
    expect(find.text('CHF · CHF'), findsOneWidget);
  });
}
