import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/expense/ui/expense_form_page.dart';
import 'package:naviwealth/features/finance/shared/ui/account_tree_picker.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/forms.dart';
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
    required this.repository,
  });

  final AppDatabase db;
  final InMemoryOutboxStore outbox;
  final MutationStamper stamper;
  final SharedPreferences prefs;
  final JournalEntryRepository repository;

  static Future<_Harness> create() async {
    final db = makeTestDatabase();
    final outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final repository = JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      fxRateSource: const IdentityFxRateSource(),
      baseCurrency: 'CNY',
    );
    return _Harness(
      db: db,
      outbox: outbox,
      stamper: stamper,
      prefs: prefs,
      repository: repository,
    );
  }

  Future<void> dispose() => db.close();
}

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
  required _Harness harness,
  required List<Account> accounts,
  required List<Account> allAccounts,
  required Map<String, Object> preferences,
  String? editingId,
  double keyboardInset = 0,
  Future<JournalEntryRepository>? repositoryFuture,
  Stream<List<Account>>? accountsStream,
  Stream<List<Account>>? allAccountsStream,
}) async {
  for (final entry in preferences.entries) {
    await harness.prefs.setString(entry.key, entry.value as String);
  }
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(harness.prefs),
      journalEntryRepositoryProvider.overrideWith(
        (_) => repositoryFuture ?? Future.value(harness.repository),
      ),
      accountsStreamProvider.overrideWith(
        (_) => accountsStream ?? Stream.value(accounts),
      ),
      allAccountsStreamProvider.overrideWith(
        (_) => allAccountsStream ?? Stream.value(allAccounts),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      builder: (context, child) => AppMessenger.init(child: child!),
      routerConfig: GoRouter(
        initialLocation: editingId == null ? '/new' : '/edit',
        routes: [
          GoRoute(
            path: '/new',
            builder: (_, _) => _expensePage(keyboardInset: keyboardInset),
          ),
          GoRoute(
            path: '/edit',
            builder: (_, _) => _expensePage(
              expenseId: editingId,
              keyboardInset: keyboardInset,
            ),
          ),
          GoRoute(
            path: AppRoutes.activity,
            builder: (_, _) => const SizedBox(),
          ),
        ],
      ),
    ),
  );
}

Widget _expensePage({String? expenseId, required double keyboardInset}) {
  Widget page = ExpenseFormPage(expenseId: expenseId);
  if (keyboardInset > 0) {
    page = MediaQuery(
      data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: keyboardInset)),
      child: page,
    );
  }
  return FTheme(data: FThemes.slate.light.desktop, child: page);
}

void _expectSubmitWiring(WidgetTester tester, {required bool enabled}) {
  final body = tester.widget<AppFormScaffoldBody>(
    find.byType(AppFormScaffoldBody),
  );
  final button = tester.widget<FButton>(
    find.descendant(
      of: find.byType(AppFormActionBar),
      matching: find.byType(FButton),
    ),
  );
  if (enabled) {
    expect(body.onSubmit, isNotNull);
    expect(body.onSubmit, same(button.onPress));
  } else {
    expect(body.onSubmit, isNull);
    expect(button.onPress, isNull);
  }
}

Finder _amountInput() => find.descendant(
  of: find.byType(AmountField),
  matching: find.byType(EditableText),
);

void main() {
  late _Harness harness;

  setUp(() async {
    harness = await _Harness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  testWidgets('expense creation derives currency from the remembered account', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      await _wrap(
        harness: harness,
        preferences: const {
          'naviwealth.forms.expense.account': 'cash-1',
          'naviwealth.forms.expense.category': 'dining',
          'naviwealth.forms.expense.currency': 'CHF',
        },
        accounts: [
          _account(
            id: 'cash-1',
            name: 'Cash',
            category: AccountSide.asset,
            currency: 'CHF',
          ),
          _account(id: 'cash-2', name: 'Cash', category: AccountSide.asset),
        ],
        allAccounts: [
          _account(id: 'dining', name: 'Dining', category: AccountSide.expense),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ExpenseFormPage), findsOneWidget);
    expect(
      tester.widget<AmountField>(find.byType(AmountField)).currencyCode,
      'CHF',
    );
    expect(find.byType(CurrencyPicker), findsNothing);
  });

  testWidgets(
    'edit preserves historical currency and exposes account conflict',
    (tester) async {
      final build = JournalEntryBuilders.expense(
        date: DateTime.utc(2026, 3, 1),
        expenseAccountId: 'dining',
        fromAccountId: 'cash-1',
        amount: Decimal.parse('15'),
        currency: 'CNY',
      );
      final original = await harness.repository.create(
        entry: build.entry,
        postings: build.postings,
      );
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        await _wrap(
          harness: harness,
          editingId: original.entry.id,
          preferences: const {},
          accounts: [
            _account(
              id: 'cash-1',
              name: 'Cash',
              category: AccountSide.asset,
              currency: 'USD',
            ),
          ],
          allAccounts: [
            _account(
              id: 'dining',
              name: 'Dining',
              category: AccountSide.expense,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('recorded in CNY'), findsOneWidget);
      expect(find.byType(CurrencyPicker), findsOneWidget);
      expect(
        tester.widget<AmountField>(find.byType(AmountField)).currencyCode,
        'CNY',
      );
    },
  );

  testWidgets('explicit payment-account switch adopts only its currency', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final accounts = [
      _account(id: 'cash-1', name: 'Cash CNY', category: AccountSide.asset),
      _account(
        id: 'cash-2',
        name: 'Cash USD',
        category: AccountSide.asset,
        currency: 'USD',
      ),
    ];
    await tester.pumpWidget(
      await _wrap(
        harness: harness,
        preferences: const {
          'naviwealth.forms.expense.account': 'cash-1',
          'naviwealth.forms.expense.category': 'dining',
        },
        accounts: accounts,
        allAccounts: [
          _account(id: 'dining', name: 'Dining', category: AccountSide.expense),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final categoryBefore = tester
        .widget<AccountTreePicker>(find.byType(AccountTreePicker))
        .value;

    tester
        .widget<AccountPicker>(find.byType(AccountPicker))
        .onChanged('cash-2');
    await tester.pump();

    expect(
      tester.widget<AmountField>(find.byType(AmountField)).currencyCode,
      'USD',
    );
    expect(find.byType(CurrencyPicker), findsNothing);
    expect(
      tester.widget<AccountTreePicker>(find.byType(AccountTreePicker)).value,
      categoryBefore,
    );
  });

  testWidgets(
    'later account disappearance preserves currency and requires pick',
    (tester) async {
      final controller = StreamController<List<Account>>();
      addTearDown(controller.close);
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        await _wrap(
          harness: harness,
          preferences: const {
            'naviwealth.forms.expense.account': 'cash-1',
            'naviwealth.forms.expense.category': 'dining',
          },
          accounts: const [],
          accountsStream: controller.stream,
          allAccounts: [
            _account(
              id: 'dining',
              name: 'Dining',
              category: AccountSide.expense,
            ),
          ],
        ),
      );
      controller.add([
        _account(id: 'cash-1', name: 'Cash', category: AccountSide.asset),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(CurrencyPicker), findsNothing);

      controller.add(const []);
      await tester.pumpAndSettle();
      expect(find.byType(CurrencyPicker), findsOneWidget);
      expect(
        tester.widget<AmountField>(find.byType(AmountField)).currencyCode,
        'CNY',
      );
      expect(find.text('Create an account first'), findsOneWidget);
    },
  );

  testWidgets('no-account create starts from base currency without dirtying', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      await _wrap(
        harness: harness,
        preferences: const {},
        accounts: const [],
        allAccounts: [
          _account(id: 'dining', name: 'Dining', category: AccountSide.expense),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<AmountField>(find.byType(AmountField)).currencyCode,
      'CNY',
    );
    expect(find.byType(CurrencyPicker), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
  });

  testWidgets('first non-empty account snapshot hydrates create exactly once', (
    tester,
  ) async {
    final controller = StreamController<List<Account>>();
    addTearDown(controller.close);
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      await _wrap(
        harness: harness,
        preferences: const {},
        accounts: const [],
        accountsStream: controller.stream,
        allAccounts: [
          _account(id: 'dining', name: 'Dining', category: AccountSide.expense),
        ],
      ),
    );
    controller.add(const []);
    await tester.pumpAndSettle();
    expect(
      tester.widget<AmountField>(find.byType(AmountField)).currencyCode,
      'CNY',
    );

    controller.add([
      _account(
        id: 'cash-usd',
        name: 'Cash USD',
        category: AccountSide.asset,
        currency: 'USD',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(
      tester.widget<AmountField>(find.byType(AmountField)).currencyCode,
      'USD',
    );
    expect(find.byType(CurrencyPicker), findsNothing);
  });

  testWidgets('late account snapshot never overwrites a chosen currency', (
    tester,
  ) async {
    final controller = StreamController<List<Account>>();
    addTearDown(controller.close);
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      await _wrap(
        harness: harness,
        preferences: const {},
        accounts: const [],
        accountsStream: controller.stream,
        allAccounts: [
          _account(id: 'dining', name: 'Dining', category: AccountSide.expense),
        ],
      ),
    );
    controller.add(const []);
    await tester.pumpAndSettle();

    tester.widget<CurrencyPicker>(find.byType(CurrencyPicker)).onChanged('CHF');
    await tester.pump();
    controller.add([
      _account(
        id: 'cash-usd',
        name: 'Cash USD',
        category: AccountSide.asset,
        currency: 'USD',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(
      tester.widget<AmountField>(find.byType(AmountField)).currencyCode,
      'CHF',
    );
    expect(find.byType(CurrencyPicker), findsOneWidget);
    expect(
      tester.widget<AccountPicker>(find.byType(AccountPicker)).value,
      isNull,
    );
  });

  testWidgets('expense creation keeps save action visible above keyboard', (
    tester,
  ) async {
    const size = Size(390, 844);
    const keyboardInset = 320.0;
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      await _wrap(
        harness: harness,
        keyboardInset: keyboardInset,
        preferences: const {},
        accounts: [
          _account(id: 'cash-1', name: 'Cash', category: AccountSide.asset),
        ],
        allAccounts: [
          _account(id: 'dining', name: 'Dining', category: AccountSide.expense),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FButton, 'Save');
    expect(save, findsOneWidget);
    _expectSubmitWiring(tester, enabled: true);
    expect(
      tester.getBottomLeft(save).dy,
      moreOrLessEquals(size.height - keyboardInset - 12, epsilon: 1),
    );
  });

  testWidgets('expense shortcut and button disable from the same busy state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pendingRepository = Completer<JournalEntryRepository>();
    addTearDown(() {
      if (!pendingRepository.isCompleted) {
        pendingRepository.complete(harness.repository);
      }
    });
    await tester.pumpWidget(
      await _wrap(
        harness: harness,
        repositoryFuture: pendingRepository.future,
        preferences: const {
          'naviwealth.forms.expense.account': 'cash-1',
          'naviwealth.forms.expense.category': 'dining',
          'naviwealth.forms.expense.currency': 'CNY',
        },
        accounts: [
          _account(id: 'cash-1', name: 'Cash', category: AccountSide.asset),
        ],
        allAccounts: [
          _account(id: 'dining', name: 'Dining', category: AccountSide.expense),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_amountInput(), '12.50');
    await tester.pump();
    _expectSubmitWiring(tester, enabled: true);

    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pump();
    _expectSubmitWiring(tester, enabled: false);

    pendingRepository.complete(harness.repository);
    await tester.pumpAndSettle();
    expect(
      await harness.db.select(harness.db.journalEntries).get(),
      hasLength(1),
    );
  });

  testWidgets('expense delete offers Undo and restores the entry', (
    tester,
  ) async {
    final build = JournalEntryBuilders.expense(
      date: DateTime.utc(2026, 3, 1),
      expenseAccountId: 'dining',
      fromAccountId: 'cash-1',
      amount: Decimal.parse('15'),
      currency: 'CNY',
      narration: 'Lunch',
    );
    final original = await harness.repository.create(
      entry: build.entry,
      postings: build.postings,
    );
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      await _wrap(
        harness: harness,
        editingId: original.entry.id,
        preferences: const {},
        accounts: [
          _account(id: 'cash-1', name: 'Cash', category: AccountSide.asset),
        ],
        allAccounts: [
          _account(id: 'dining', name: 'Dining', category: AccountSide.expense),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.trash2));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Delete this expense? You can undo it from the confirmation message, '
        'and the change syncs to your other devices.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(await harness.repository.getById(original.entry.id), isNull);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final restored = await harness.repository.getById(original.entry.id);
    expect(restored, isNotNull);
    expect(restored!.entry.narration, 'Lunch');
    expect(restored.postings, hasLength(2));
    expect(find.text('Change undone'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('expense create success offers Undo and tombstones the entry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      await _wrap(
        harness: harness,
        preferences: const {
          'naviwealth.forms.expense.account': 'cash-1',
          'naviwealth.forms.expense.category': 'dining',
          'naviwealth.forms.expense.currency': 'CNY',
        },
        accounts: [
          _account(id: 'cash-1', name: 'Cash', category: AccountSide.asset),
        ],
        allAccounts: [
          _account(id: 'dining', name: 'Dining', category: AccountSide.expense),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_amountInput(), '12.50');
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pumpAndSettle();

    final entry = await harness.db
        .select(harness.db.journalEntries)
        .getSingle();
    expect(entry.deletedAt, isNull);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final tombstoned = await harness.db
        .select(harness.db.journalEntries)
        .getSingle();
    expect(tombstoned.deletedAt, isNotNull);
    final postings = await harness.db.select(harness.db.postings).get();
    expect(postings.every((posting) => posting.deletedAt != null), isTrue);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('expense edit success Undo restores the prior amount', (
    tester,
  ) async {
    final build = JournalEntryBuilders.expense(
      date: DateTime.utc(2026, 3, 1),
      expenseAccountId: 'dining',
      fromAccountId: 'cash-1',
      amount: Decimal.parse('15'),
      currency: 'CNY',
      narration: 'Original expense',
    );
    final original = await harness.repository.create(
      entry: build.entry,
      postings: build.postings,
    );
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      await _wrap(
        harness: harness,
        editingId: original.entry.id,
        preferences: const {},
        accounts: [
          _account(id: 'cash-1', name: 'Cash', category: AccountSide.asset),
        ],
        allAccounts: [
          _account(id: 'dining', name: 'Dining', category: AccountSide.expense),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_amountInput(), '25');
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pumpAndSettle();

    final edited = (await harness.repository.getById(original.entry.id))!;
    expect(
      edited.postings
          .firstWhere((posting) => posting.units > Decimal.zero)
          .units,
      Decimal.parse('25'),
    );

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final restored = (await harness.repository.getById(original.entry.id))!;
    expect(restored.entry.narration, 'Original expense');
    expect(
      restored.postings
          .firstWhere((posting) => posting.units > Decimal.zero)
          .units,
      Decimal.parse('15'),
    );
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('expense Undo conflict exposes Retry and preserves later edit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      await _wrap(
        harness: harness,
        preferences: const {
          'naviwealth.forms.expense.account': 'cash-1',
          'naviwealth.forms.expense.category': 'dining',
          'naviwealth.forms.expense.currency': 'CNY',
        },
        accounts: [
          _account(id: 'cash-1', name: 'Cash', category: AccountSide.asset),
        ],
        allAccounts: [
          _account(id: 'dining', name: 'Dining', category: AccountSide.expense),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_amountInput(), '12.50');
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pumpAndSettle();

    final committed = await harness.db
        .select(harness.db.journalEntries)
        .getSingle();
    final laterBuild = JournalEntryBuilders.expense(
      date: committed.date,
      expenseAccountId: 'dining',
      fromAccountId: 'cash-1',
      amount: Decimal.parse('99'),
      currency: 'CNY',
      narration: 'Later expense edit',
    );
    await harness.repository.replacePostings(
      id: committed.id,
      entry: laterBuild.entry,
      postings: laterBuild.postings,
    );

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Couldn't undo the change. Try again."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Change undone'), findsNothing);
    var current = (await harness.repository.getById(committed.id))!;
    expect(current.entry.narration, 'Later expense edit');
    expect(
      current.postings
          .firstWhere((posting) => posting.units > Decimal.zero)
          .units,
      Decimal.parse('99'),
    );

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text("Couldn't undo the change. Try again."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Change undone'), findsNothing);
    current = (await harness.repository.getById(committed.id))!;
    expect(current.entry.narration, 'Later expense edit');
    expect(
      current.postings
          .firstWhere((posting) => posting.units > Decimal.zero)
          .units,
      Decimal.parse('99'),
    );
    await tester.pump(const Duration(seconds: 7));
  });
}
