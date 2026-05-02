import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/invariants.dart';
import 'package:naviwealth/data/domain/posting.dart';
import 'package:naviwealth/data/repositories/journal_entry_repository.dart';

import '../db/test_database.dart';
import '_stub_stamper.dart';

class _IdentityFx implements FxRateSource {
  const _IdentityFx();
  @override
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  }) => from == to ? Decimal.one : Decimal.one;
}

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late JournalEntryRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = JournalEntryRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
      fxRateSource: const _IdentityFx(),
      baseCurrency: 'USD',
    );
  });

  tearDown(() async {
    await db.close();
  });

  PostingDraft cashLeg(String accountId, String units) => PostingDraft(
    accountId: accountId,
    units: Decimal.parse(units),
    unit: 'USD',
  );

  test('create writes JE + postings and queues one op per row', () async {
    final je = await repo.create(
      entry: JournalEntryDraft(
        date: DateTime.utc(2026, 1, 15),
        narration: 'Transfer',
      ),
      postings: [
        cashLeg('acct:bank:a', '-100.00'),
        cashLeg('acct:bank:b', '100.00'),
      ],
    );
    expect(je.entry.narration, 'Transfer');
    expect(je.postings, hasLength(2));
    expect(je.postings[0].position, 0);
    expect(je.postings[1].position, 1);

    final batch = await outbox.peekBatch();
    // 1 JE op + 2 posting ops.
    expect(batch, hasLength(3));
    expect(batch.map((o) => o.tableName).toSet(), {
      'journal_entries',
      'postings',
    });
    final je0 = batch.firstWhere((o) => o.tableName == 'journal_entries');
    expect(je0.opType, OpType.insert);
    expect(je0.fieldsDiff!['narration'], 'Transfer');
    expect(je0.fieldsDiff!['flag'], 'confirmed');
    expect(je0.fieldsDiff!['tag_ids_json'], '[]');
  });

  test('create rejects unbalanced postings before touching the DB', () async {
    expect(
      () => repo.create(
        entry: JournalEntryDraft(
          date: DateTime.utc(2026, 1, 15),
          narration: 'Bad',
        ),
        postings: [
          cashLeg('a', '-100.00'),
          cashLeg('b', '50.00'), // Σ = -50 USD.
        ],
      ),
      throwsA(isA<JournalEntryUnbalancedException>()),
    );
    // Nothing was written.
    final entries = await db.select(db.journalEntries).get();
    expect(entries, isEmpty);
    final ops = await outbox.peekBatch();
    expect(ops, isEmpty);
  });

  test('getById returns the JE plus postings in position order', () async {
    final je = await repo.create(
      entry: JournalEntryDraft(
        date: DateTime.utc(2026, 1, 15),
        narration: 'Trade',
      ),
      postings: [
        PostingDraft(
          accountId: 'broker:hk',
          units: Decimal.parse('100'),
          unit: 'us_stock:AAPL',
          cost: Cost(perUnit: Decimal.parse('150'), currency: 'USD'),
        ),
        cashLeg('broker:cash', '-15000.00'),
      ],
    );
    final reloaded = await repo.getById(je.entry.id);
    expect(reloaded, isNotNull);
    expect(reloaded!.postings.map((p) => p.position), [0, 1]);
    expect(reloaded.postings.first.cost?.perUnit, Decimal.parse('150'));
    expect(reloaded.postings.first.unit, 'us_stock:AAPL');
  });

  test(
    'softDelete tombstones JE + every posting and queues delete ops',
    () async {
      final je = await repo.create(
        entry: JournalEntryDraft(
          date: DateTime.utc(2026, 1, 15),
          narration: 'Tx',
        ),
        postings: [cashLeg('a', '-50.00'), cashLeg('b', '50.00')],
      );
      await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

      await repo.softDelete(je.entry.id);

      expect(await repo.getById(je.entry.id), isNull);
      final batch = await outbox.peekBatch();
      expect(batch, hasLength(3));
      expect(batch.every((o) => o.opType == OpType.delete), isTrue);
      expect(batch.every((o) => o.fieldsDiff == null), isTrue);
      final tables = batch.map((o) => o.tableName).toSet();
      expect(tables, {'journal_entries', 'postings'});
    },
  );

  test(
    'queued ops are well-formed for the sync wire (validateOpForQueue)',
    () async {
      await repo.create(
        entry: JournalEntryDraft(
          date: DateTime.utc(2026, 1, 15),
          narration: 'Validate',
        ),
        postings: [cashLeg('a', '-1.00'), cashLeg('b', '1.00')],
      );
      final batch = await outbox.peekBatch();
      for (final op in batch) {
        expect(validateOpForQueue(op), isNull, reason: 'op=$op');
      }
    },
  );
}
