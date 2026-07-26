import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/liabilities/data/liability_repository.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';
import 'package:naviwealth/features/finance/liabilities/ui/liability_form_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

class _IdentityFx implements FxRateSource {
  const _IdentityFx();

  @override
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  }) => Decimal.one;
}

class _ControlledOutbox implements OutboxStore {
  final firstWrite = Completer<void>();
  int calls = 0;

  @override
  Future<int> depth() async => calls;

  @override
  Future<void> enqueue({required String table, required String rowId}) {
    calls += 1;
    return calls == 1 ? firstWrite.future : Future<void>.value();
  }
}

Account _payerAccount({
  String id = 'payer-account',
  String name = 'Daily checking',
  String currency = 'CNY',
}) => Account(
  id: id,
  type: AccountCategory.bank,
  name: name,
  currency: currency,
  sync: SyncMeta(
    ownerUserId: 'user-1',
    updatedAt: DateTime.utc(2026, 1, 1),
    updatedByDevice: 'device-1',
    hlc: Hlc.zero('device-1'),
  ),
);

Finder _field(String label) {
  final field = find.ancestor(
    of: find.text('$label *', findRichText: true),
    matching: find.byType(FTextFormField),
  );
  return find.descendant(of: field, matching: find.byType(EditableText));
}

Future<Widget> _wrapCreatePage({List<Account>? accounts}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      accountsStreamProvider.overrideWith(
        (_) => Stream.value(accounts ?? [_payerAccount()]),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en', 'US'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppMessenger.init(
        child: FTheme(data: FThemes.slate.light.desktop, child: child!),
      ),
      home: const LiabilityFormPage(),
    ),
  );
}

Future<void> _selectPayerAccount(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('liability-payer-account-field')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Daily checking · CNY').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('payer account drives currency on a narrow create form', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      await _wrapCreatePage(
        accounts: [
          _payerAccount(),
          _payerAccount(
            id: 'usd-account',
            name: 'Travel checking',
            currency: 'USD',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final picker = find.byKey(const Key('liability-payer-account-field'));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Travel checking · USD').last);
    await tester.pumpAndSettle();

    expect(
      tester.widget<EditableText>(_field('Currency')).controller.text,
      'USD',
    );
    expect(
      find.text('Scheduled repayments will be recorded against this account.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty payer accounts explain the next action', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(await _wrapCreatePage(accounts: const []));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No eligible payment account is available. Create a cash or bank account first.',
      ),
      findsOneWidget,
    );
    expect(find.text('New account'), findsOneWidget);
    expect(
      tester.widget<FButton>(find.widgetWithText(FButton, 'Save')).onPress,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit mode loads and replaces the payer account', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = makeTestDatabase();
    addTearDown(db.close);
    final outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    final repo = LiabilityRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      journalEntryRepo: JournalEntryRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
        fxRateSource: const _IdentityFx(),
        baseCurrency: 'CNY',
      ),
    );
    final liability = await repo.create(
      type: LiabilityType.mortgage,
      name: 'Home loan',
      principal: Decimal.parse('120000'),
      interestRate: Decimal.parse('0.048'),
      currency: 'CNY',
      termMonths: 12,
      startDate: DateTime.utc(2026, 1, 1),
      accountId: 'payer-account',
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final editPath = FinanceRoutes.wealthLiabilityEdit(liability.id);
    final detailPath = FinanceRoutes.wealthLiability(liability.id);
    final router = GoRouter(
      initialLocation: editPath,
      routes: [
        GoRoute(
          path: '/wealth/liabilities/:id/edit',
          builder: (_, state) =>
              LiabilityFormPage(liabilityId: state.pathParameters['id']),
        ),
        GoRoute(
          path: '/wealth/liabilities/:id',
          builder: (_, _) => const Text('Liability destination'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          accountsStreamProvider.overrideWith(
            (_) => Stream.value([
              _payerAccount(),
              _payerAccount(id: 'backup-account', name: 'Backup checking'),
            ]),
          ),
          liabilityRepositoryProvider.overrideWith((_) async => repo),
        ],
        child: MaterialApp.router(
          locale: const Locale('en', 'US'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (context, child) => AppMessenger.init(
            child: FTheme(data: FThemes.slate.light.desktop, child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Daily checking · CNY'), findsOneWidget);
    await tester.tap(find.byKey(const Key('liability-payer-account-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup checking · CNY').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, detailPath);
    expect(find.text('Liability destination'), findsOneWidget);
    final stored = await repo.findById(liability.id);
    expect(stored?.accountId, 'backup-account');
    expect(tester.takeException(), isNull);
  });

  testWidgets('schedule details expose state and reveal hidden day errors', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(await _wrapCreatePage());
    await tester.pumpAndSettle();
    await _selectPayerAccount(tester);

    final toggle = find.byKey(const Key('liability-details-toggle-label'));
    final details = find.byKey(const Key('liability-details-fields'));
    expect(tester.widget<Semantics>(toggle).properties.expanded, isFalse);
    expect(tester.widget<Offstage>(details).offstage, isTrue);
    expect(find.text('Rate type, start date & repayment'), findsOneWidget);
    expect(find.text('Name *', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Mortgage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credit card').last);
    await tester.pumpAndSettle();
    expect(find.text('Billing dates & note'), findsOneWidget);

    await tester.tap(find.text('Schedule details'));
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(toggle).properties.expanded, isTrue);
    expect(tester.widget<Offstage>(details).offstage, isFalse);
    await tester.enterText(
      find.byKey(const Key('liability-statement-day-field')),
      '32',
    );

    await tester.tap(find.text('Schedule details'));
    await tester.pumpAndSettle();
    expect(tester.widget<Semantics>(toggle).properties.expanded, isFalse);
    await tester.tap(find.widgetWithText(FButton, 'Save'));
    await tester.pumpAndSettle();

    expect(tester.widget<Semantics>(toggle).properties.expanded, isTrue);
    expect(find.text('Must be 1–31'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed create remains editable and retries after pending write unlocks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = _ControlledOutbox();
      final stamper = makeStubStamper();
      final repo = LiabilityRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
        journalEntryRepo: JournalEntryRepository(
          db: db,
          outbox: outbox,
          stamper: stamper,
          fxRateSource: const _IdentityFx(),
          baseCurrency: 'CNY',
        ),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(
        initialLocation: '/new',
        routes: [
          GoRoute(path: '/new', builder: (_, _) => const LiabilityFormPage()),
          GoRoute(
            path: FinanceRoutes.wealthLiabilities,
            builder: (_, _) => const Text('Liabilities destination'),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            accountsStreamProvider.overrideWith(
              (_) => Stream.value([_payerAccount()]),
            ),
            liabilityRepositoryProvider.overrideWith((_) async => repo),
          ],
          child: MaterialApp.router(
            locale: const Locale('en', 'US'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
            builder: (context, child) => AppMessenger.init(
              child: FTheme(data: FThemes.slate.light.desktop, child: child!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _selectPayerAccount(tester);
      await tester.enterText(_field('Name'), 'Draft mortgage');
      await tester.enterText(_field('Principal'), '120000');
      await tester.enterText(_field('Annual rate (%)'), '4.8');
      await tester.enterText(_field('Term (months)'), '12');
      await tester.tap(find.widgetWithText(FButton, 'Save'));
      await tester.pump();

      expect(outbox.calls, 1);
      expect(find.byType(LiabilityFormPage), findsOneWidget);
      expect(
        tester
            .widget<FButton>(
              find.ancestor(
                of: find.text('Saving…'),
                matching: find.byType(FButton),
              ),
            )
            .onPress,
        isNull,
      );

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(LiabilityFormPage), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('app.back')));
      await tester.pump();
      expect(find.byType(LiabilityFormPage), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/new');

      outbox.firstWrite.completeError(StateError('write failed'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(LiabilityFormPage), findsOneWidget);
      expect(find.text('Draft mortgage'), findsOneWidget);
      expect(find.text("Couldn't save your changes. Try again."), findsWidgets);
      expect(
        tester.widget<FButton>(find.widgetWithText(FButton, 'Save')).onPress,
        isNotNull,
      );

      await tester.tap(find.widgetWithText(FButton, 'Save'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(outbox.calls, greaterThan(1));
      expect(find.byType(LiabilityFormPage), findsNothing);
      expect(find.text('Liabilities destination'), findsOneWidget);
      final stored = await db.select(db.liabilities).get();
      expect(stored.single.accountId, 'payer-account');
      await tester.pump(const Duration(seconds: 7));
    },
  );
}
