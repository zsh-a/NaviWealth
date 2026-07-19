import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/features/finance/monthly_close/data/account_reconciliation_repository.dart';
import 'package:naviwealth/features/finance/monthly_close/domain/account_reconciliation.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late AccountReconciliationRepository repository;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repository = AccountReconciliationRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
  });

  tearDown(() => db.close());

  test('compares statement balance with exact period-end ledger sum', () async {
    await _insertPosting(
      db,
      entryId: 'july',
      postingId: 'p-july',
      date: DateTime.utc(2026, 7, 20),
      units: Decimal.parse('1234.56'),
    );
    await _insertPosting(
      db,
      entryId: 'august',
      postingId: 'p-august',
      date: DateTime.utc(2026, 8, 1),
      units: Decimal.parse('10'),
    );

    final balanced = await repository.verify(
      periodMonth: '2026-07',
      accountId: 'cash',
      unit: 'CNY',
      statementBalance: Decimal.parse('1234.56'),
      now: DateTime.utc(2026, 7, 31),
    );
    expect(balanced.status, AccountReconciliationStatus.balanced);
    expect(balanced.difference, Decimal.zero);

    final mismatch = await repository.verify(
      periodMonth: '2026-07',
      accountId: 'cash',
      unit: 'CNY',
      statementBalance: Decimal.parse('1235.56'),
      now: DateTime.utc(2026, 7, 31),
    );
    expect(mismatch.status, AccountReconciliationStatus.mismatch);
    expect(mismatch.difference, Decimal.one);

    final overridden = await repository.overrideMismatch(
      reconciliation: mismatch,
      note: 'Pending bank fee',
      now: DateTime.utc(2026, 7, 31),
    );
    expect(overridden.status, AccountReconciliationStatus.overridden);
    expect(overridden.note, 'Pending bank fee');
    expect(await outbox.depth(), 3);
  });
}

Future<void> _insertPosting(
  AppDatabase db, {
  required String entryId,
  required String postingId,
  required DateTime date,
  required Decimal units,
}) async {
  const hlc = Hlc(wallMillis: 1, counter: 0, nodeId: 'dev-test');
  await db
      .into(db.journalEntries)
      .insert(
        JournalEntriesCompanion.insert(
          id: entryId,
          date: date,
          narration: entryId,
          ownerUserId: 'u-test',
          updatedAt: date,
          updatedByDevice: 'dev-test',
          hlc: hlc,
        ),
      );
  await db
      .into(db.postings)
      .insert(
        PostingsCompanion.insert(
          id: postingId,
          journalEntryId: entryId,
          position: 0,
          accountId: 'cash',
          units: units,
          unit: 'CNY',
          ownerUserId: 'u-test',
          updatedAt: date,
          updatedByDevice: 'dev-test',
          hlc: hlc,
        ),
      );
}
