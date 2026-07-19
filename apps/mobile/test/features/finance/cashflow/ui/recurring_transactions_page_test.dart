import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/cashflow/data/recurring_transaction_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/recurring_transaction_repository.dart';
import 'package:naviwealth/features/finance/cashflow/ui/recurring_transactions_page.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late RecurringTransactionRepository repository;

  setUp(() async {
    db = makeTestDatabase();
    repository = RecurringTransactionRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
    );
    await repository.create(
      id: 'rt-rent',
      templateJournalBuildJson: _templateJson(),
      rrule: 'FREQ=MONTHLY;BYMONTHDAY=1',
      nextDueAt: DateTime.utc(2026, 8, 1),
    );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('disables immediately and restores the rule from Undo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    expect(find.text('Monthly rent'), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.ellipsisVertical));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disable'));
    await tester.pumpAndSettle();

    expect(find.text('Rule disabled'), findsOneWidget);
    expect(find.text('Monthly rent'), findsNothing);
    expect(find.text('No recurring rules'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Monthly rent'), findsOneWidget);
    expect(find.text('Change undone'), findsOneWidget);
    expect((await repository.getById('rt-rent'))?.enabled, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('restores a deleted rule from the confirmation toast', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.ellipsisVertical));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete rule?'), findsOneWidget);
    expect(
      find.text(
        'This recurring rule will be removed. '
        'You can undo it from the confirmation message.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Rule deleted'), findsOneWidget);
    expect(await repository.getById('rt-rent'), isNull);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Monthly rent'), findsOneWidget);
    expect(find.text('Change undone'), findsOneWidget);
    expect(await repository.getById('rt-rent'), isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

Widget _wrap(RecurringTransactionRepository repository) {
  return ProviderScope(
    overrides: [
      recurringTransactionRepositoryProvider.overrideWith(
        (ref) async => repository,
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      builder: (context, child) => AppMessenger.init(child: child!),
      home: FTheme(
        data: FThemes.slate.light.desktop,
        child: const RecurringTransactionsPage(),
      ),
    ),
  );
}

String _templateJson() {
  return JournalBuildTemplateCodec.encode(
    JournalEntryBuild(
      entry: JournalEntryDraft(
        date: DateTime.utc(2026, 7, 1),
        narration: 'Monthly rent',
      ),
      postings: [
        PostingDraft(
          accountId: 'acct:cash',
          units: Decimal.parse('-3200'),
          unit: 'CNY',
        ),
        PostingDraft(
          accountId: 'acct:rent',
          units: Decimal.parse('3200'),
          unit: 'CNY',
        ),
      ],
    ),
  );
}
