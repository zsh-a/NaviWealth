import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/invariants.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/liabilities/data/liability_repository.dart';

import '../../../core/persistence/test_database.dart';
import '../../../core/sync/_outbox_test_ext.dart';
import '../../../features/finance/data/repositories/_stub_stamper.dart';

Decimal d(String s) => Decimal.parse(s);

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
  late LiabilityRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = LiabilityRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
      journalEntryRepo: JournalEntryRepository(
        db: db,
        outbox: outbox,
        stamper: makeStubStamper(),
        fxRateSource: const _IdentityFx(),
        baseCurrency: 'CNY',
      ),
      clock: () => DateTime.utc(2026, 1, 1),
    );
  });

  tearDown(() async => db.close());

  test(
    'create persists liability + full schedule and queues insert ops',
    () async {
      final l = await repo.create(
        type: LiabilityType.mortgage,
        name: 'Home',
        principal: d('120000'),
        interestRate: d('0.05'),
        currency: 'CNY',
        paymentMethod: RepaymentMethod.equalPrincipal,
        termMonths: 12,
        startDate: DateTime.utc(2026, 1, 1),
      );

      expect(l.name, 'Home');

      final list = await repo.watchAll().first;
      expect(list, hasLength(1));

      final schedule = await repo.scheduleFor(l.id);
      expect(schedule, hasLength(12));
      expect(schedule.first.periodIndex, 1);
      expect(schedule.last.remainingBalance, Decimal.zero);

      final batch = outbox.queued;
      // 1 liability insert + 12 amortization inserts = 13 dirty pointers.
      expect(batch, hasLength(13));
      expect(batch.first.table, 'liabilities');
      expect(batch.first.rowId, l.id);
      expect(
        batch.skip(1).every((o) => o.table == 'amortization_entries'),
        isTrue,
      );
    },
  );

  test('credit-card liability persists without a schedule', () async {
    final cc = await repo.create(
      type: LiabilityType.creditCard,
      name: 'Visa',
      principal: d('1'),
      interestRate: d('0.18'),
      currency: 'CNY',
      statementDay: 5,
      paymentDueDay: 25,
    );
    final schedule = await repo.scheduleFor(cc.id);
    expect(schedule, isEmpty);

    final batch = outbox.queued;
    expect(batch, hasLength(1));
    expect(batch.single.table, 'liabilities');
  });

  test(
    'updateMetadata changes name and note without regenerating schedule',
    () async {
      final l = await repo.create(
        type: LiabilityType.mortgage,
        name: 'Home',
        principal: d('120000'),
        interestRate: d('0.05'),
        currency: 'CNY',
        paymentMethod: RepaymentMethod.equalPrincipal,
        termMonths: 12,
        startDate: DateTime.utc(2026, 1, 1),
      );
      final before = await repo.scheduleFor(l.id);
      outbox.clearQueued();

      final updated = await repo.updateMetadata(
        id: l.id,
        name: 'Primary home',
        note: 'Refinance review in Q4',
      );

      expect(updated.name, 'Primary home');
      expect(updated.note, 'Refinance review in Q4');
      expect(await repo.scheduleFor(l.id), before);
      expect(outbox.queued, hasLength(1));
      expect(outbox.queued.single.table, 'liabilities');
      expect(outbox.queued.single.rowId, l.id);
    },
  );

  test('registerPayment marks period paid, writes a journal entry, and queues '
      'amortization-update + journal-entry/posting ops', () async {
    final l = await repo.create(
      type: LiabilityType.mortgage,
      name: 'Home',
      principal: d('120000'),
      interestRate: d('0.05'),
      currency: 'CNY',
      paymentMethod: RepaymentMethod.equalPrincipal,
      termMonths: 12,
      startDate: DateTime.utc(2026, 1, 1),
      accountId: 'acc-1',
    );
    // Drain create-time pointers so the next assertion is easier to read.
    outbox.clearQueued();

    final journalEntryId = await repo.registerPayment(
      liabilityId: l.id,
      periodIndex: 1,
    );
    expect(journalEntryId, isNotEmpty);

    final schedule = await repo.scheduleFor(l.id);
    expect(schedule.first.paidAt, isNotNull);
    expect(schedule[1].paidAt, isNull);

    final batch = outbox.queued;
    expect(batch, hasLength(5));
    final amortOp = batch.firstWhere((o) => o.table == 'amortization_entries');
    expect(amortOp.table, 'amortization_entries');
    final jeOp = batch.firstWhere((o) => o.table == 'journal_entries');
    expect(jeOp.rowId, journalEntryId);
    final postingOps = batch.where((o) => o.table == 'postings');
    expect(postingOps, hasLength(3));
  });

  test('registerPayment refuses to mark a period twice', () async {
    final l = await repo.create(
      type: LiabilityType.mortgage,
      name: 'Home',
      principal: d('120000'),
      interestRate: d('0.05'),
      currency: 'CNY',
      paymentMethod: RepaymentMethod.equalPrincipal,
      termMonths: 12,
      startDate: DateTime.utc(2026, 1, 1),
      accountId: 'acc-1',
    );
    await repo.registerPayment(liabilityId: l.id, periodIndex: 1);
    expect(
      () => repo.registerPayment(liabilityId: l.id, periodIndex: 1),
      throwsA(isA<StateError>()),
    );
  });

  test('registerPayment requires accountId on the liability', () async {
    final l = await repo.create(
      type: LiabilityType.mortgage,
      name: 'Home',
      principal: d('120000'),
      interestRate: d('0.05'),
      currency: 'CNY',
      paymentMethod: RepaymentMethod.equalPrincipal,
      termMonths: 12,
      startDate: DateTime.utc(2026, 1, 1),
    );
    expect(
      () => repo.registerPayment(liabilityId: l.id, periodIndex: 1),
      throwsA(isA<StateError>()),
    );
  });
}
