import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/assets/ui/deposit_form_page.dart';
import 'package:naviwealth/features/finance/assets/ui/wealth_product_form_page.dart';
import 'package:naviwealth/features/finance/data/repositories/manual_asset_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/test_database.dart';
import '../../../finance/data/repositories/_stub_stamper.dart';

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

Future<Widget> _wrap({
  Widget page = const DepositFormPage(),
  Future<ManualAssetRepository> Function()? loadRepository,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      if (loadRepository != null)
        manualAssetRepositoryProvider.overrideWith((_) => loadRepository()),
      accountsStreamProvider.overrideWith(
        (_) => Stream.value(<Account>[_bankAccount()]),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      builder: (context, child) => AppMessenger.init(child: child!),
      home: FTheme(data: FTheme.neutral.light.desktop, child: page),
    ),
  );
}

void main() {
  for (final page in [
    const DepositFormPage(assetId: 'missing'),
    const WealthProductFormPage(assetId: 'missing'),
  ]) {
    testWidgets(
      '${page.runtimeType} never shows a create form while an edit is loading or missing',
      (tester) async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        final outbox = InMemoryOutboxStore();
        final repo = ManualAssetRepository(
          db: db,
          outbox: outbox,
          stamper: makeStubStamper(),
          priceRepo: PriceRepository(
            db: db,
            outbox: outbox,
            stamper: makeStubStamper(),
          ),
        );
        final pending = Completer<ManualAssetRepository>();
        var loads = 0;
        await tester.pumpWidget(
          await _wrap(
            page: page,
            loadRepository: () {
              loads++;
              return loads == 1 ? pending.future : Future.value(repo);
            },
          ),
        );
        await tester.pump();
        expect(find.byType(AssetDetailSkeleton), findsOneWidget);
        expect(find.text('Save'), findsNothing);
        pending.completeError(StateError('temporary failure'));
        await tester.pumpAndSettle();
        expect(find.text('Save'), findsNothing);
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(loads, 2);
        expect(
          find.text(
            'This product is unavailable or has been deleted. Reload before editing.',
          ),
          findsOneWidget,
        );
        expect(find.text('Save'), findsNothing);
        expect(await db.select(db.assets).get(), isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }

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
