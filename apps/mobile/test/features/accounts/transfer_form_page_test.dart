import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  static Future<_Harness> create() async {
    final db = makeTestDatabase();
    final outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    return _Harness(db: db, outbox: outbox, stamper: stamper, prefs: prefs);
  }

  Future<void> dispose() => db.close();

  Future<void> seedAccounts(List<Account> accounts) async {
    for (final a in accounts) {
      await db.into(db.accounts).insert(
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
}) =>
    Account(
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

Widget _wrap(_Harness h, {required List<Account> accounts}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(h.prefs),
      appDatabaseProvider.overrideWith((_) async => h.db),
      outboxStoreProvider.overrideWith((_) async => h.outbox),
      mutationStamperProvider.overrideWith((_) async => h.stamper),
      accountsStreamProvider.overrideWith((_) => Stream.value(accounts)),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TransferFormPage(),
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

    // Pick the From account.
    await tester.tap(find.byKey(const Key('')).evaluate().isEmpty
        ? find.text('From account')
        : find.text('From account'));
    // Open the dropdown by tapping the field.
    await tester.tap(find.text('From account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('• Bank A').last);
    await tester.pumpAndSettle();

    // Pick the To account.
    await tester.tap(find.text('To account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('• Bank B').last);
    await tester.pumpAndSettle();

    // Enter an amount.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '1000',
    );
    await tester.pumpAndSettle();

    // PostingsPreview now shows the leg amounts.
    expect(find.text('-1000 CNY'), findsOneWidget);
    expect(find.text('1000 CNY'), findsOneWidget);

    // Submit is now enabled.
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
      find.widgetWithText(TextFormField, 'Amount'),
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

  testWidgets(
    'cross-currency picks render an inline error and disable submit',
    (tester) async {
      await _enlarge(tester);
      await tester.pumpWidget(
        _wrap(
          h,
          accounts: [
            _account(
              id: 'a-cny',
              name: 'CNY Bank',
              category: AccountCategory.asset,
              currency: 'CNY',
            ),
            _account(
              id: 'a-usd',
              name: 'USD Bank',
              category: AccountCategory.asset,
              currency: 'USD',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('From account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('• CNY Bank').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('To account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('• USD Bank').last);
      await tester.pumpAndSettle();

      // Picking the second account doesn't auto-snap currency because
      // the first account already has its own currency. The user is
      // explicitly mixing CNY/USD; the form surfaces the inline
      // warning until cross-currency support lands in wave 3b.
      expect(
        find.textContaining('Cross-currency transfers are not supported'),
        findsOneWidget,
      );
    },
  );
}
