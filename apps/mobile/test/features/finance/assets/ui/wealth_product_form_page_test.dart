import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/forms/amount_field.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/assets/ui/wealth_product_form_page.dart';
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
        data: FTheme.neutral.light.desktop,
        child: const WealthProductFormPage(),
      ),
    ),
  );
}

void main() {
  testWidgets('optional product details start concise with submit enabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();

    final toggle = tester.widget<Semantics>(
      find.byKey(const Key('wealth-product-details-toggle-label')),
    );
    final fields = tester.widget<Offstage>(
      find.byKey(const Key('wealth-product-details-fields')),
    );
    expect(toggle.properties.expanded, isFalse);
    expect(fields.offstage, isTrue);
    expect(find.text('Issuer, dates & current value'), findsOneWidget);
    expect(find.text('Product name *', findRichText: true), findsOneWidget);
    expect(
      find.text('Expected annual return (%) *', findRichText: true),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AppFormScaffoldBody>(find.byType(AppFormScaffoldBody))
          .onSubmit,
      isNotNull,
    );
  });

  testWidgets('hidden valuation errors reveal product details', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('wealth-product-name-field')),
      'Stable income plan',
    );
    await tester.enterText(
      find.byKey(const Key('wealth-product-principal-field')),
      '50000',
    );
    await tester.enterText(
      find.byKey(const Key('wealth-product-return-field')),
      '3.8',
    );
    final valuationField = tester.widget<AmountField>(
      find.byKey(
        const Key('wealth-product-valuation-field'),
        skipOffstage: false,
      ),
    );
    valuationField.controller!.text = 'not-a-number';
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(
      tester
          .widget<Semantics>(
            find.byKey(const Key('wealth-product-details-toggle-label')),
          )
          .properties
          .expanded,
      isTrue,
    );
    expect(
      tester
          .widget<Offstage>(
            find.byKey(const Key('wealth-product-details-fields')),
          )
          .offstage,
      isFalse,
    );
    expect(find.text('Invalid amount format'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
  });
}
