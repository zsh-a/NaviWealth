import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/invariants.dart';
import 'package:naviwealth/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/liabilities/data/liability_repository.dart';

import '../../../core/sync/_outbox_test_ext.dart';
import '../../../data/db/test_database.dart';
import '../../../data/repositories/_stub_stamper.dart';

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

  test('create persists liability + full schedule and queues insert ops',
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

    final batch = await outbox.peekBatch();
    // 1 liability insert + 12 amortization inserts = 13 ops.
    expect(batch, hasLength(13));
    expect(batch.first.tableName, 'liabilities');
    expect(batch.first.opType, OpType.insert);
    expect(batch.skip(1).every((o) => o.tableName == 'amortization_entries'),
        isTrue);
    expect(batch.skip(1).every((o) => o.opType == OpType.insert), isTrue);
  });

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

    final batch = await outbox.peekBatch();
    expect(batch, hasLength(1));
    expect(batch.single.tableName, 'liabilities');
  });

  test(
    'registerPayment marks period paid, writes a journal entry, and queues '
    'amortization-update + journal-entry/posting ops',
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
        accountId: 'acc-1',
      );
      // Drain create-time ops so the next assertion is easier to read.
      await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

      final journalEntryId = await repo.registerPayment(
        liabilityId: l.id,
        periodIndex: 1,
      );
      expect(journalEntryId, isNotEmpty);

      final schedule = await repo.scheduleFor(l.id);
      expect(schedule.first.paidAt, isNotNull);
      expect(schedule[1].paidAt, isNull);

      final batch = await outbox.peekBatch();
      expect(batch, hasLength(5));
      final amortOp = batch.firstWhere(
        (o) => o.tableName == 'amortization_entries',
      );
      expect(amortOp.opType, OpType.update);
      expect(amortOp.fieldsDiff!.containsKey('paid_at'), isTrue);
      final jeOp = batch.firstWhere((o) => o.tableName == 'journal_entries');
      expect(jeOp.opType, OpType.insert);
      expect(jeOp.rowId, journalEntryId);
      final postingOps = batch.where((o) => o.tableName == 'postings');
      expect(postingOps, hasLength(3));
    },
  );

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
