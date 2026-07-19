import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/cashflow/data/recurring_transaction_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';

import '../../../../core/persistence/test_database.dart';
import '../../../../core/sync/_outbox_test_ext.dart';
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

  test('create writes synced row and queues a dirty pointer', () async {
    final template = _templateJson();

    final tx = await recurringRepo.create(
      id: 'rt-salary',
      templateJournalBuildJson: template,
      rrule: 'FREQ=MONTHLY;BYMONTHDAY=1',
      nextDueAt: DateTime.utc(2026, 6, 1),
    );

    expect(tx.id, 'rt-salary');
    expect(tx.enabled, isTrue);

    final batch = outbox.queued;
    expect(batch, hasLength(1));
    expect(batch.single.table, 'recurring_transactions');
    expect(batch.single.rowId, 'rt-salary');
  });

  test('materialiseDue creates deterministic journal entries once', () async {
    await recurringRepo.create(
      id: 'rt-rent',
      templateJournalBuildJson: _templateJson(),
      rrule: 'FREQ=DAILY',
      nextDueAt: DateTime.utc(2026, 1, 1),
    );
    outbox.clearQueued();

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

  test('materialiseDue stops at UNTIL and completes the rule', () async {
    await recurringRepo.create(
      id: 'rt-limited',
      templateJournalBuildJson: _templateJson(),
      rrule: 'FREQ=DAILY;UNTIL=20260102',
      nextDueAt: DateTime.utc(2026, 1, 1),
    );

    final count = await service.materialiseDue(DateTime.utc(2026, 1, 5));

    expect(count, 2);
    expect(
      await journalRepo.getById(
        RecurringMaterialisationService.journalEntryId(
          recurringTransactionId: 'rt-limited',
          occurrenceDate: DateTime.utc(2026, 1, 3),
        ),
      ),
      isNull,
    );
    final tx = await recurringRepo.getById('rt-limited');
    expect(tx, isNotNull);
    expect(tx!.enabled, isFalse);
    expect(_utcDay(tx.lastMaterialisedAt!), DateTime.utc(2026, 1, 2));
    expect(_utcDay(tx.nextDueAt), DateTime.utc(2026, 1, 3));
  });

  test('watchAll keeps paused rules visible after active rules', () async {
    await recurringRepo.create(
      id: 'rt-paused',
      templateJournalBuildJson: _templateJson(),
      rrule: 'FREQ=MONTHLY',
      nextDueAt: DateTime.utc(2026, 1, 1),
      enabled: false,
    );
    await recurringRepo.create(
      id: 'rt-active',
      templateJournalBuildJson: _templateJson(),
      rrule: 'FREQ=MONTHLY',
      nextDueAt: DateTime.utc(2026, 2, 1),
    );

    final rules = await recurringRepo.watchAll().first;

    expect(rules.map((rule) => rule.id), ['rt-active', 'rt-paused']);
  });

  test('restore reverses a soft delete and queues the restored row', () async {
    await recurringRepo.create(
      id: 'rt-restorable',
      templateJournalBuildJson: _templateJson(),
      rrule: 'FREQ=MONTHLY',
      nextDueAt: DateTime.utc(2026, 2, 1),
    );
    outbox.clearQueued();

    await recurringRepo.softDelete('rt-restorable');
    expect(await recurringRepo.getById('rt-restorable'), isNull);

    await recurringRepo.restore('rt-restorable');

    expect(await recurringRepo.getById('rt-restorable'), isNotNull);
    expect(outbox.queued, hasLength(2));
    expect(outbox.queued.last.table, 'recurring_transactions');
    expect(outbox.queued.last.rowId, 'rt-restorable');
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
