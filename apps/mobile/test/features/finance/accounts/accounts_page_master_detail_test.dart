import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/shell/selection_query.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/accounts/data/account_balances_provider.dart';
import 'package:naviwealth/features/finance/accounts/ui/account_form_page.dart';
import 'package:naviwealth/features/finance/accounts/ui/accounts_page.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _account = Account(
  id: 'checking-1',
  type: AccountCategory.bank,
  name: 'Checking account',
  currency: 'USD',
  sync: SyncMeta(
    ownerUserId: 'user-1',
    updatedAt: DateTime.utc(2026, 7, 10),
    updatedByDevice: 'device-1',
    hlc: Hlc.zero('device-1'),
  ),
);

Widget _wrap({required SharedPreferences prefs, required double contentWidth}) {
  final router = GoRouter(
    initialLocation: '/wealth/accounts',
    routes: [
      GoRoute(
        path: '/wealth/accounts',
        builder: (_, _) => Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: contentWidth, child: const AccountsPage()),
        ),
      ),
      GoRoute(
        path: '/wealth/accounts/:id',
        builder: (_, _) => const Text('single-account-detail'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      accountsStreamProvider.overrideWith((_) => Stream.value([_account])),
      accountBalancesByIdProvider.overrideWith((_) => Stream.value(const {})),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

Future<void> _setSurface(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('uses viewport width for inline selection at 1280', (
    tester,
  ) async {
    await _setSurface(tester, 1280);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(_wrap(prefs: prefs, contentWidth: 900));
    await tester.pumpAndSettle();

    expect(find.byType(MasterDetailLayout), findsOneWidget);
    await tester.tap(find.text('Checking account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      selectedQueryOf(tester.element(find.byType(AccountsPage))),
      _account.id,
    );
    expect(find.byType(AccountFormPage), findsOneWidget);
    expect(find.text('single-account-detail'), findsNothing);
  });

  testWidgets('pushes a detail route below 1280', (tester) async {
    await _setSurface(tester, 1279);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(_wrap(prefs: prefs, contentWidth: 900));
    await tester.pumpAndSettle();

    expect(find.byType(MasterDetailLayout), findsNothing);
    await tester.tap(find.text('Checking account'));
    await tester.pumpAndSettle();

    expect(find.text('single-account-detail'), findsOneWidget);
  });
}
