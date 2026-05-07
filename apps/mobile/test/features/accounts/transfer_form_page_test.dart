import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/route_paths.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/db/providers.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/repositories/mutation_context.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/domain/entities/fx_rate.dart';
import 'package:naviwealth/features/accounts/transfer_form_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

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
  required AccountCategory category,
  String currency = 'CNY',
  AccountType type = AccountType.bank,
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
            path: AppRoutes.activityAccounts,
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
          _account(
            id: 'a-bank-a',
            name: 'Bank A',
            category: AccountCategory.asset,
          ),
          _account(
            id: 'a-bank-b',
            name: 'Bank B',
            category: AccountCategory.asset,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('From account'), findsOneWidget);
    expect(find.text('To account'), findsOneWidget);

    // Submit button is rendered but disabled (no accounts picked yet).
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Transfer'),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets('PostingsPreview surfaces both legs once form is fillable', (
    tester,
  ) async {
    await _enlarge(tester);
    await tester.pumpWidget(
      _wrap(
        h,
        accounts: [
          _account(
            id: 'a-bank-a',
            name: 'Bank A',
            category: AccountCategory.asset,
          ),
          _account(
            id: 'a-bank-b',
            name: 'Bank B',
            category: AccountCategory.asset,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('From account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('• Bank A').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('To account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('• Bank B').last);
    await tester.pumpAndSettle();

    // The amount field labels include the from-account currency once
    // the from picker is filled.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (CNY)'),
      '1000',
    );
    await tester.pumpAndSettle();

    // PostingsPreview now shows the leg amounts.
    expect(find.text('-1000 CNY'), findsOneWidget);
    expect(find.text('1000 CNY'), findsOneWidget);

    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Transfer'),
    );
    expect(submit.onPressed, isNotNull);
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
            category: AccountCategory.asset,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Both pickers + amount filled, but with the same account on both
    // sides — preview should not appear and submit should stay
    // disabled (the form's `canSubmit` rule covers it).
    await tester.tap(find.text('From account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('• Only Bank').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('To account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('• Only Bank').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (CNY)'),
      '500',
    );
    await tester.pumpAndSettle();

    // Preview should not render with same account on both ends.
    expect(find.text('-500 CNY'), findsNothing);
    expect(find.text('500 CNY'), findsNothing);

    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Transfer'),
    );
    expect(submit.onPressed, isNull);
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
            category: AccountCategory.asset,
            currency: 'USD',
          ),
          _account(
            id: 'a-cny',
            name: 'CNY Bank',
            category: AccountCategory.asset,
            currency: 'CNY',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('From account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('• USD Bank').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('To account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('• CNY Bank').last);
    await tester.pumpAndSettle();

    // The To-amount field appears once both accounts disagree on
    // currency. Its label includes the destination currency.
    expect(
      find.widgetWithText(TextFormField, 'To amount (CNY)'),
      findsOneWidget,
    );

    // No FX rate on file → helper prompts the user to enter the
    // converted amount manually.
    expect(find.textContaining('No FX rate on file'), findsOneWidget);

    // Enter both sides of the exchange.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount (USD)'),
      '1000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'To amount (CNY)'),
      '7100',
    );
    await tester.pumpAndSettle();

    // Rate label surfaces underneath the to-amount input.
    expect(find.textContaining('1 USD = 7.1 CNY'), findsOneWidget);

    // PostingsPreview shows both legs in their respective currencies.
    expect(find.text('-1000 USD'), findsOneWidget);
    expect(find.text('7100 CNY'), findsOneWidget);

    // Submit is enabled.
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Transfer'),
    );
    expect(submit.onPressed, isNotNull);
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
              category: AccountCategory.asset,
              currency: 'USD',
            ),
            _account(
              id: 'a-cny',
              name: 'CNY Bank',
              category: AccountCategory.asset,
              currency: 'CNY',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('From account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('• USD Bank').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('To account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('• CNY Bank').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (USD)'),
        '1000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'To amount (CNY)'),
        '7100',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
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
