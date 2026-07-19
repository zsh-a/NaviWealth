import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/assets/ui/deposit_form_page.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Account _bankAccount() => Account(
  id: 'bank-1',
  type: AccountCategory.bank,
  name: 'Everyday bank',
  currency: 'CNY',
  category: AccountSide.asset,
  sync: SyncMeta(
    ownerUserId: 'user-test',
    updatedAt: DateTime.utc(2026, 1, 1),
    updatedByDevice: 'device-test',
    hlc: Hlc.zero('device-test'),
  ),
);

Future<Widget> _wrap() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      accountsStreamProvider.overrideWith(
        (_) => Stream.value(<Account>[_bankAccount()]),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      builder: (context, child) => AppMessenger.init(child: child!),
      home: FTheme(
        data: FThemes.slate.light.desktop,
        child: const DepositFormPage(),
      ),
    ),
  );
}

void main() {
  testWidgets('type selector updates the concise details summary', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();

    expect(find.text('Maturity, renewal & current value'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deposit-type-demand')));
    await tester.pump();

    expect(find.text('Value date & current value'), findsOneWidget);
    expect(find.text('Maturity, renewal & current value'), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('details stay concise and reveal hidden maturity errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();

    final toggle = tester.widget<Semantics>(
      find.byKey(const Key('deposit-details-toggle-label')),
    );
    final fields = tester.widget<Offstage>(
      find.byKey(const Key('deposit-details-fields')),
    );
    expect(toggle.properties.expanded, isFalse);
    expect(fields.offstage, isTrue);
    expect(find.text('Maturity, renewal & current value'), findsOneWidget);
    expect(find.text('Name *', findRichText: true), findsOneWidget);
    expect(find.text('Annual rate (%) *', findRichText: true), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('deposit-name-field')),
      'One-year deposit',
    );
    await tester.enterText(
      find.byKey(const Key('deposit-principal-field')),
      '10000',
    );
    await tester.enterText(find.byKey(const Key('deposit-rate-field')), '2.4');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(
      tester
          .widget<Semantics>(
            find.byKey(const Key('deposit-details-toggle-label')),
          )
          .properties
          .expanded,
      isTrue,
    );
    expect(
      tester
          .widget<Offstage>(find.byKey(const Key('deposit-details-fields')))
          .offstage,
      isFalse,
    );
    expect(find.text('Pick a date'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 150));
  });
}
