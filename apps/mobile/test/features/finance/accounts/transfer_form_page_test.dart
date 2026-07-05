import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/accounts/ui/transfer_form_page.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/shared/ui/account_tree_picker.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';
import '../data/repositories/_stub_stamper.dart';

class _Harness {
  _Harness({
    required this.db,
    required this.outbox,
    required this.stamper,
    required this.prefs,
  });

  final AppDatabase db;
  final InMemoryOutboxStore outbox;
  final MutationStamper stamper;
  final SharedPreferences prefs;

  static Future<_Harness> create({String baseCurrency = 'CNY'}) async {
    final db = makeTestDatabase();
    final outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    SharedPreferences.setMockInitialValues(<String, Object>{
      // Same key the BaseCurrencyController persists under. Bypass
      // the controller's runtime save so cold-start reads pick up
      // the test override on the first build.
      'naviwealth.settings.base_currency': baseCurrency,
    });
    final prefs = await SharedPreferences.getInstance();
    return _Harness(db: db, outbox: outbox, stamper: stamper, prefs: prefs);
  }

  Future<void> dispose() => db.close();

  Future<void> seedAccounts(List<Account> accounts) async {
    for (final a in accounts) {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: a.id,
              type: a.type,
              name: a.name,
              currency: a.currency,
              category: Value(a.category),
              ownerUserId: a.sync.ownerUserId,
              updatedAt: a.sync.updatedAt,
              updatedByDevice: a.sync.updatedByDevice,
              hlc: a.sync.hlc,
            ),
          );
    }
  }
}

Account _account({
  required String id,
  required String name,
  required AccountSide category,
  String currency = 'CNY',
  AccountCategory type = AccountCategory.bank,
  String? parentId,
}) => Account(
  id: id,
  type: type,
  name: name,
  currency: currency,
  category: category,
  parentId: parentId,
  sync: SyncMeta(
    ownerUserId: 'u-test',
    updatedAt: DateTime.utc(2026, 1, 1),
    updatedByDevice: 'dev-test',
    hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test'),
  ),
);

Widget _wrap(
  _Harness h, {
  required List<Account> accounts,
  List<FxRate> fxRates = const <FxRate>[],
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(h.prefs),
      appDatabaseProvider.overrideWith((_) async => h.db),
      outboxStoreProvider.overrideWith((_) async => h.outbox),
      mutationStamperProvider.overrideWith((_) async => h.stamper),
      accountsStreamProvider.overrideWith((_) => Stream.value(accounts)),
      // Closed stream so the ProviderScope teardown doesn't leak a
      // pending Drift StreamQueryStore timer past pumpAndSettle.
      // Tests that exercise the FX-defaulted to-amount path pass a
      // non-empty list here.
      fxRatesStreamProvider.overrideWith((_) => Stream.value(fxRates)),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Minimal router so the form's submit navigation lands on a valid
      // stub instead of silently failing, which matters for the
      // cross-currency submit test that inspects DB state after the
      // optimistic pop.
      routerConfig: GoRouter(
        initialLocation: '/transfer',
        routes: [
          GoRoute(
            path: '/transfer',
            builder: (_, _) => const TransferFormPage(),
          ),
          GoRoute(
            path: AppRoutes.wealthAccounts,
            builder: (_, _) => const SizedBox(),
          ),
        ],
      ),
    ),
  );
}

Future<void> _enlarge(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _selectAccount(
  WidgetTester tester, {
  required int pickerIndex,
  required String accountName,
}) async {
  await tester.tap(find.byType(AccountTreePicker).at(pickerIndex));
  await tester.pumpAndSettle();
  await tester.tap(find.text(accountName).last);
  await tester.pumpAndSettle();
}

void main() {
  late _Harness h;

  setUp(() async {
    h = await _Harness.create();
  });

  tearDown(() async {
    await h.dispose();
  });

  testWidgets('renders both pickers + submit disabled until form is filled', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(
      _wrap(
        h,
        accounts: [
          _account(id: 'a-bank-a', name: 'Bank A', category: AccountSide.asset),
          _account(id: 'a-bank-b', name: 'Bank B', category: AccountSide.asset),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('From account'), findsOneWidget);
    expect(find.text('To account'), findsOneWidget);

    // Submit button is rendered but disabled (no accounts picked yet).
    final submit = tester.widget<FButton>(
      find.widgetWithText(FButton, 'Transfer'),
    );
    expect(submit.onPress, isNull);
  });

  testWidgets('PostingsPreview surfaces both legs once form is fillable', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(
      _wrap(
        h,
        accounts: [
          _account(id: 'a-bank-a', name: 'Bank A', category: AccountSide.asset),
          _account(id: 'a-bank-b', name: 'Bank B', category: AccountSide.asset),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _selectAccount(tester, pickerIndex: 0, accountName: 'Bank A');
    await _selectAccount(tester, pickerIndex: 1, accountName: 'Bank B');

    // The amount field labels include the from-account currency once
    // the from picker is filled.
    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Amount (CNY)'),
      '1000',
    );
    await tester.pumpAndSettle();

    // PostingsPreview now shows the leg amounts.
    expect(find.text('-¥1,000'), findsOneWidget);
    expect(find.text('+¥1,000'), findsOneWidget);

    final submit = tester.widget<FButton>(
      find.widgetWithText(FButton, 'Transfer'),
    );
    expect(submit.onPress, isNotNull);
  });

  testWidgets('selecting the same account on both ends keeps submit disabled', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(
      _wrap(
        h,
        accounts: [
          _account(
            id: 'a-only',
            name: 'Only Bank',
            category: AccountSide.asset,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Both pickers + amount filled, but with the same account on both
    // sides — preview should not appear and submit should stay
    // disabled (the form's `canSubmit` rule covers it).
    await _selectAccount(tester, pickerIndex: 0, accountName: 'Only Bank');
    await _selectAccount(tester, pickerIndex: 1, accountName: 'Only Bank');

    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Amount (CNY)'),
      '500',
    );
    await tester.pumpAndSettle();

    // Preview should not render with same account on both ends.
    expect(find.text('-¥500'), findsNothing);
    expect(find.text('+¥500'), findsNothing);

    final submit = tester.widget<FButton>(
      find.widgetWithText(FButton, 'Transfer'),
    );
    expect(submit.onPress, isNull);
  });

  testWidgets('cross-currency picks reveal the To-amount field + rate hint', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(
      _wrap(
        h,
        accounts: [
          _account(
            id: 'a-usd',
            name: 'USD Bank',
            category: AccountSide.asset,
            currency: 'USD',
          ),
          _account(
            id: 'a-cny',
            name: 'CNY Bank',
            category: AccountSide.asset,
            currency: 'CNY',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await _selectAccount(tester, pickerIndex: 0, accountName: 'USD Bank');
    await _selectAccount(tester, pickerIndex: 1, accountName: 'CNY Bank');

    // The To-amount field appears once both accounts disagree on
    // currency. Its label includes the destination currency.
    expect(
      find.widgetWithText(FTextFormField, 'To amount (CNY)'),
      findsOneWidget,
    );

    // No FX rate on file → helper prompts the user to enter the
    // converted amount manually.
    expect(find.textContaining('No FX rate on file'), findsOneWidget);

    // Enter both sides of the exchange.
    await tester.enterText(
      find.widgetWithText(FTextFormField, 'Amount (USD)'),
      '1000',
    );
    await tester.enterText(
      find.widgetWithText(FTextFormField, 'To amount (CNY)'),
      '7100',
    );
    await tester.pumpAndSettle();

    // Rate label surfaces underneath the to-amount input.
    expect(find.textContaining('1 USD = 7.1 CNY'), findsOneWidget);

    // PostingsPreview shows both legs in their respective currencies.
    expect(find.text(r'-$1,000'), findsAtLeastNWidgets(1));
    expect(find.text('+¥7,100'), findsAtLeastNWidgets(1));

    // Submit is enabled.
    final submit = tester.widget<FButton>(
      find.widgetWithText(FButton, 'Transfer'),
    );
    expect(submit.onPress, isNotNull);
  });

  testWidgets(
    'cross-currency submit attaches a Price annotation pinning the user rate',
    (tester) async {
      // The price annotation makes the destination leg's weight
      // resolve in the source currency (USD), so a base of USD lets
      // the JE balance without any FX rate on file. This mirrors the
      // builder unit-test that exercises the same path.
      h = await _Harness.create(baseCurrency: 'USD');
      await _enlarge(tester);
      await tester.pumpWidget(
        _wrap(
          h,
          accounts: [
            _account(
              id: 'a-usd',
              name: 'USD Bank',
              category: AccountSide.asset,
              currency: 'USD',
            ),
            _account(
              id: 'a-cny',
              name: 'CNY Bank',
              category: AccountSide.asset,
              currency: 'CNY',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _selectAccount(tester, pickerIndex: 0, accountName: 'USD Bank');
      await _selectAccount(tester, pickerIndex: 1, accountName: 'CNY Bank');

      await tester.enterText(
        find.widgetWithText(FTextFormField, 'Amount (USD)'),
        '1000',
      );
      await tester.enterText(
        find.widgetWithText(FTextFormField, 'To amount (CNY)'),
        '7100',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FButton, 'Transfer'));
      await tester.pumpAndSettle();

      // The repo persisted both legs; the destination posting carries
      // a Price annotation = amount / toAmount in the source currency.
      final postings = await h.db.select(h.db.postings).get();
      expect(postings, hasLength(2));
      final destLeg = postings.firstWhere((p) => p.unit == 'CNY');
      expect(destLeg.priceCurrency, 'USD');
      // 1000 / 7100 ≈ 0.140845070422
      expect(destLeg.pricePerUnit, isNotNull);
      expect(destLeg.pricePerUnit.toString(), '0.140845070422');

      // Source leg has no price annotation; same-currency invariant
      // (the price annotation is only on the dest leg).
      final srcLeg = postings.firstWhere((p) => p.unit == 'USD');
      expect(srcLeg.priceCurrency, isNull);
      expect(srcLeg.pricePerUnit, isNull);
    },
  );
}
