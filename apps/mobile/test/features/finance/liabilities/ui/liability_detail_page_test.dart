import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/amortization_entry.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/domain/models/liability.dart';
import 'package:naviwealth/features/finance/liabilities/data/liability_repository.dart';
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';
import 'package:naviwealth/features/finance/liabilities/domain/liability_summary.dart';
import 'package:naviwealth/features/finance/liabilities/ui/liability_detail_page.dart';
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

Decimal _d(String value) => Decimal.parse(value);

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'user-1',
  updatedAt: DateTime.utc(2026, 1, 1),
  updatedByDevice: 'device-1',
  hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: 'device-1'),
);

Liability _liability({int count = 8}) => Liability(
  id: 'liability-1',
  type: LiabilityType.mortgage,
  name: 'Home loan',
  principal: Decimal.fromInt(count * 100000),
  interestRate: _d('0.04'),
  currency: 'CNY',
  termMonths: count,
  startDate: DateTime.utc(2026, 1, 1),
  sync: _meta(),
);

List<AmortizationEntry> _schedule({int count = 8}) => [
  for (var index = 1; index <= count; index++)
    AmortizationEntry(
      id: 'period-$index',
      liabilityId: 'liability-1',
      periodIndex: index,
      dueDate: DateTime.utc(2026, index + 1, 1),
      principalPayment: _d('100000'),
      interestPayment: Decimal.fromInt((count - index + 1) * 500),
      remainingBalance: Decimal.fromInt((count - index) * 100000),
      paidAt: index == 1 ? DateTime.utc(2026, 2, 1) : null,
      sync: _meta(),
    ),
];

Future<Widget> _wrapDetailPage({int count = 8}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final liability = _liability(count: count);
  final schedule = _schedule(count: count);
  final summary = LiabilitySummary.fromSchedule(
    liability: liability,
    schedule: schedule,
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      liabilitySummaryProvider.overrideWith((ref, id) => Stream.value(summary)),
      amortizationScheduleStreamProvider.overrideWith(
        (ref, id) => Stream.value(schedule),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en', 'US'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppMessenger.init(
        child: FTheme(data: FTheme.neutral.light.desktop, child: child!),
      ),
      home: const LiabilityDetailPage(id: 'liability-1'),
    ),
  );
}

void main() {
  for (final fullSchedule in [false, true]) {
    testWidgets(
      'records payment date ${fullSchedule ? 'from full schedule' : 'from overview'} and refreshes rows',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final db = makeTestDatabase();
        addTearDown(db.close);
        final outbox = InMemoryOutboxStore();
        final stamper = makeStubStamper();
        final journalRepo = JournalEntryRepository(
          db: db,
          outbox: outbox,
          stamper: stamper,
          fxRateSource: const _IdentityFx(),
          baseCurrency: 'CNY',
        );
        final repo = LiabilityRepository(
          db: db,
          outbox: outbox,
          stamper: stamper,
          journalEntryRepo: journalRepo,
          clock: () => DateTime.utc(2000, 1, 1),
        );
        final liability = await repo.create(
          type: LiabilityType.mortgage,
          name: 'Home loan',
          principal: _d('800000'),
          interestRate: _d('0.04'),
          currency: 'CNY',
          termMonths: 8,
          startDate: DateTime.utc(2026, 1, 1),
          accountId: 'payer-account',
        );
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final preferences = await SharedPreferences.getInstance();
        final today = DateTime.now();
        final selectedDate = DateTime(
          today.year,
          today.month,
          today.day,
        ).subtract(const Duration(days: 3));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              liabilityRepositoryProvider.overrideWith((_) async => repo),
            ],
            child: MaterialApp(
              locale: const Locale('en', 'US'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => AppMessenger.init(
                child: FTheme(
                  data: FTheme.neutral.light.desktop,
                  child: child!,
                ),
              ),
              home: LiabilityDetailPage(id: liability.id),
            ),
          ),
        );
        await tester.pumpAndSettle();

        if (fullSchedule) {
          final details = find.byKey(
            const ValueKey('liability-schedule-details'),
          );
          await tester.ensureVisible(details);
          await tester.pumpAndSettle();
          await tester.tap(details);
          await tester.pumpAndSettle();
        }
        final markPaid = fullSchedule
            ? find
                  .descendant(
                    of: find.byType(AppSheet),
                    matching: find.text('Mark paid'),
                  )
                  .first
            : find.text('Mark paid').first;
        await tester.ensureVisible(markPaid);
        await tester.pumpAndSettle();
        await tester.tap(markPaid);
        await tester.pumpAndSettle();

        expect(find.text('Record period 1 payment'), findsOneWidget);
        final paymentDateField = find.descendant(
          of: find.byKey(const Key('liability-payment-date')),
          matching: find.byWidgetPredicate((widget) => widget is FDateField),
        );
        expect(paymentDateField, findsOneWidget);
        expect(find.textContaining('Payment amount ·'), findsOneWidget);
        final dateControl =
            tester.widget<FDateField>(paymentDateField).selectionControl
                as FDateSelectionManagedControl<DateTime?>;
        dateControl.onChange?.call(selectedDate);
        await tester.pump();
        await tester.tap(find.byKey(const Key('liability-payment-submit')));
        await tester.pumpAndSettle();

        final paidAt = (await repo.scheduleFor(liability.id)).first.paidAt;
        expect(paidAt, isNotNull);
        expect(DateUtils.isSameDay(paidAt, selectedDate), isTrue);
        expect(paidAt?.year, isNot(2000));
        expect(find.text('Saved'), findsOneWidget);
        if (fullSchedule) {
          expect(
            find.descendant(
              of: find.byType(AppSheet),
              matching: find.text('Undo'),
            ),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('finance-detail-close')));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'undoing a paid period restores it and removes its ledger entry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = InMemoryOutboxStore();
      final stamper = makeStubStamper();
      final journalRepo = JournalEntryRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
        fxRateSource: const _IdentityFx(),
        baseCurrency: 'CNY',
      );
      final repo = LiabilityRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
        journalEntryRepo: journalRepo,
      );
      final liability = await repo.create(
        type: LiabilityType.mortgage,
        name: 'Home loan',
        principal: _d('800000'),
        interestRate: _d('0.04'),
        currency: 'CNY',
        termMonths: 8,
        startDate: DateTime.utc(2026, 1, 1),
        accountId: 'payer-account',
      );
      final journalEntryId = await repo.registerPayment(
        liabilityId: liability.id,
        periodIndex: 1,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            liabilityRepositoryProvider.overrideWith((_) async => repo),
          ],
          child: MaterialApp(
            locale: const Locale('en', 'US'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => AppMessenger.init(
              child: FTheme(data: FTheme.neutral.light.desktop, child: child!),
            ),
            home: LiabilityDetailPage(id: liability.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final undo = find.text('Undo').first;
      await tester.ensureVisible(undo);
      await tester.pumpAndSettle();
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(find.text('Undo payment for period 1?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FButton, 'Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Change undone'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
      expect((await repo.scheduleFor(liability.id)).first.paidAt, isNull);
      expect(await journalRepo.getById(journalEntryId), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opens full schedule without expanding the narrow overview', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(await _wrapDetailPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('liability-schedule-compact')), findsOneWidget);
    expect(find.byKey(const Key('liability-schedule-table')), findsNothing);
    Finder period(int index) => find.byWidgetPredicate(
      (widget) =>
          widget is Text && widget.data?.startsWith('#$index ·') == true,
    );

    expect(period(1), findsOneWidget);
    expect(period(6), findsOneWidget);
    expect(period(7), findsNothing);
    expect(find.byType(AppRevealControl), findsNothing);

    final details = find.byKey(const ValueKey('liability-schedule-details'));
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    final position = tester.getTopLeft(details);
    await tester.tap(details);
    await tester.pumpAndSettle();

    expect(find.byType(AppSheet), findsOneWidget);
    expect(period(8), findsOneWidget);
    expect(
      find.byKey(const ValueKey('liability-schedule-year')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('finance-detail-close')));
    await tester.pumpAndSettle();
    expect(period(8), findsNothing);
    expect(tester.getTopLeft(details), position);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the aligned schedule table on wide screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(await _wrapDetailPage());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('liability-schedule-table')), findsOneWidget);
    expect(find.byKey(const Key('liability-schedule-compact')), findsNothing);
    expect(find.text('Mark paid'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full schedule switches years without expanding all periods', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(await _wrapDetailPage(count: 24));
    await tester.pumpAndSettle();
    final details = find.byKey(const ValueKey('liability-schedule-details'));
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    await tester.tap(details);
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('liability-schedule-year'));
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2027').last);
    await tester.pumpAndSettle();
    final sheet = find.byType(AppSheet);
    expect(
      find.descendant(of: sheet, matching: find.textContaining('#12 ·')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('#1 ·')),
      findsNothing,
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('#24 ·')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('finance-detail-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
