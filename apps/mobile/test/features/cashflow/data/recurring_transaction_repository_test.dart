import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/invariants.dart';
import 'package:naviwealth/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/cashflow/data/recurring_transaction_repository.dart';

import '../../../data/db/test_database.dart';
import '../../../data/repositories/_stub_stamper.dart';

class _IdentityFx implements FxRateSource {
  const _IdentityFx();

  @override
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  }) => Decimal.one;
}

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late RecurringTransactionRepository recurringRepo;
  late JournalEntryRepository journalRepo;
  late RecurringMaterialisationService service;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    final stamper = makeStubStamper();
    recurringRepo = RecurringTransactionRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
    );
    journalRepo = JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: stamper,
      fxRateSource: const _IdentityFx(),
      baseCurrency: 'USD',
    );
    service = RecurringMaterialisationService(
      recurringRepository: recurringRepo,
      journalEntryRepository: journalRepo,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('create writes synced row and queues insert op', () async {
    final template = _templateJson();

    final tx = await recurringRepo.create(
      id: 'rt-salary',
      templateJournalBuildJson: template,
      rrule: 'FREQ=MONTHLY;BYMONTHDAY=1',
      nextDueAt: DateTime.utc(2026, 6, 1),
    );

    expect(tx.id, 'rt-salary');
    expect(tx.enabled, isTrue);

    final batch = await outbox.peekBatch();
    expect(batch, hasLength(1));
    expect(batch.single.tableName, 'recurring_transactions');
    expect(batch.single.opType, OpType.insert);
    expect(batch.single.fieldsDiff!['rrule'], 'FREQ=MONTHLY;BYMONTHDAY=1');
    expect(batch.single.fieldsDiff!['template_journal_build_json'], template);
  });

  test('materialiseDue creates deterministic journal entries once', () async {
    await recurringRepo.create(
      id: 'rt-rent',
      templateJournalBuildJson: _templateJson(),
      rrule: 'FREQ=DAILY',
      nextDueAt: DateTime.utc(2026, 1, 1),
    );
    await outbox.ack((await outbox.peekBatch()).map((op) => op.opId));

    final firstRun = await service.materialiseDue(DateTime.utc(2026, 1, 3));
    final secondRun = await service.materialiseDue(DateTime.utc(2026, 1, 3));

    expect(firstRun, 3);
    expect(secondRun, 0);
    expect(
      await journalRepo.getById(
        RecurringMaterialisationService.journalEntryId(
          recurringTransactionId: 'rt-rent',
          occurrenceDate: DateTime.utc(2026, 1, 2),
        ),
      ),
      isNotNull,
    );
    final tx = await recurringRepo.getById('rt-rent');
    expect(_utcDay(tx!.lastMaterialisedAt!), DateTime.utc(2026, 1, 3));
    expect(_utcDay(tx.nextDueAt), DateTime.utc(2026, 1, 4));
  });
}

DateTime _utcDay(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

String _templateJson() {
  return JournalBuildTemplateCodec.encode(
    JournalEntryBuild(
      entry: JournalEntryDraft(
        date: DateTime.utc(2026, 1, 1),
        narration: 'Template',
      ),
      postings: [
        PostingDraft(
          accountId: 'acct:cash',
          units: Decimal.parse('100'),
          unit: 'USD',
        ),
        PostingDraft(
          accountId: 'acct:income',
          units: Decimal.parse('-100'),
          unit: 'USD',
        ),
      ],
    ),
  );
}
