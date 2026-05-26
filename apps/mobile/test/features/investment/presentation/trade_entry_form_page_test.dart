import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/hlc.dart';
import 'package:naviwealth/features/finance/data/domain/sync_meta.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/data/securities_catalog/providers.dart';
import 'package:naviwealth/features/finance/data/securities_catalog/securities_search_service.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/trade_draft.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/trade_entry_prefill.dart';
import 'package:naviwealth/features/investment/presentation/trade_entry_form_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';

Account _account({
  required String id,
  required String name,
  required AccountCategory type,
  String currency = 'CHF',
}) {
  return Account(
    id: id,
    type: type,
    name: name,
    currency: currency,
    category: AccountSide.asset,
    sync: SyncMeta(
      ownerUserId: 'u-test',
      updatedAt: DateTime.utc(2026),
      updatedByDevice: 'dev-test',
      hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
    ),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en', 'US'),
    home: FTheme(data: FThemes.slate.light.desktop, child: child),
  );
}

void main() {
  testWidgets('renders when persisted trade currency is outside common list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'naviwealth.forms.trade.currency': 'CHF',
    });
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWith((_) async => db),
          accountsStreamProvider.overrideWith(
            (_) => Stream.value([
              _account(
                id: 'broker',
                name: 'Broker',
                type: AccountCategory.broker,
              ),
              _account(id: 'cash', name: 'Cash', type: AccountCategory.cash),
            ]),
          ),
          securitiesSearchServiceProvider.overrideWith(
            (_) async => SecuritiesSearchService(db: db),
          ),
        ],
        child: _wrap(const TradeEntryFormPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('CHF · CHF'), findsOneWidget);
  });

  testWidgets('applies upstream trade-entry prefill as pristine defaults', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWith((_) async => db),
          accountsStreamProvider.overrideWith(
            (_) => Stream.value([
              _account(
                id: 'broker',
                name: 'Broker',
                type: AccountCategory.broker,
                currency: 'CNY',
              ),
              _account(
                id: 'cash',
                name: 'Cash',
                type: AccountCategory.cash,
                currency: 'CNY',
              ),
            ]),
          ),
          securitiesSearchServiceProvider.overrideWith(
            (_) async => SecuritiesSearchService(db: db),
          ),
        ],
        child: _wrap(
          TradeEntryFormPage(
            prefill: TradeEntryPrefill(
              type: TradeType.sell,
              quantity: Decimal.one,
              price: Decimal.parse('1250.75'),
              currency: 'CNY',
              fee: Decimal.parse('1.25'),
              tax: Decimal.parse('2.50'),
              note: 'Rebalance suggestion',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Sell'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('1250.75'), findsOneWidget);
    expect(find.text('1.25'), findsOneWidget);
    expect(find.text('2.5'), findsOneWidget);
    expect(find.text('Rebalance suggestion'), findsOneWidget);
  });
}
