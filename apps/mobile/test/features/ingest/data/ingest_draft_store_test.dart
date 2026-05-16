import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ingest/data/ingest_draft_store.dart';
import 'package:naviwealth/features/ingest/domain/ingest_models.dart';

import '../../../data/db/test_database.dart';

IngestDraft _draft(
  String id, {
  DedupVerdict verdict = DedupVerdict.newTxn,
  DraftStatus status = DraftStatus.pending,
}) => IngestDraft(
  draftId: id,
  ownerUserId: 'u1',
  createdAt: DateTime.utc(2026, 5, 10, 9),
  sourceKind: IngestSourceKind.csv,
  parsed: ParsedTransaction(
    description: 'Coffee $id',
    amountMinor: -3800,
    currency: 'CNY',
    occurredAt: DateTime.utc(2026, 5, 10),
    categoryHint: 'coffee',
  ),
  verdict: verdict,
  status: status,
  originLabel: '粘贴文本',
);

void main() {
  test('putAll + listByStatus round-trips and preserves parsed fields',
      () async {
    final db = makeTestDatabase();
    final store = IngestDraftStore(db, ownerUserId: 'u1');

    await store.putAll([_draft('d1'), _draft('d2')]);
    final pending = await store.listByStatus(DraftStatus.pending);

    expect(pending, hasLength(2));
    final d = pending.firstWhere((x) => x.draftId == 'd1');
    expect(d.parsed.amountMinor, -3800);
    expect(d.parsed.categoryHint, 'coffee');
    expect(d.parsed.currency, 'CNY');
    expect(d.sourceKind, IngestSourceKind.csv);
    expect(d.originLabel, '粘贴文本');
    await db.close();
  });

  test('updateStatus moves a draft out of the pending queue', () async {
    final db = makeTestDatabase();
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    await store.putAll([_draft('d1'), _draft('d2')]);

    await store.updateStatus('d1', DraftStatus.confirmed);

    expect(await store.countByStatus(DraftStatus.pending), 1);
    expect(await store.countByStatus(DraftStatus.confirmed), 1);
    final pending = await store.listByStatus(DraftStatus.pending);
    expect(pending.single.draftId, 'd2');
    await db.close();
  });

  test('owner partitioning isolates drafts', () async {
    final db = makeTestDatabase();
    final mine = IngestDraftStore(db, ownerUserId: 'u1');
    final theirs = IngestDraftStore(db, ownerUserId: 'u2');
    await mine.putAll([_draft('d1')]);

    expect(await theirs.listByStatus(DraftStatus.pending), isEmpty);
    expect(await mine.listByStatus(DraftStatus.pending), hasLength(1));
    await db.close();
  });

  test('watchByStatus yields the initial pending snapshot', () async {
    final db = makeTestDatabase();
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    await store.putAll([_draft('d1'), _draft('d2')]);

    final initial = await store.watchByStatus(DraftStatus.pending).first;
    expect(initial.map((d) => d.draftId), containsAll(<String>['d1', 'd2']));

    store.dispose();
    await db.close();
  });

  test('pruneSettledBefore drops old non-pending rows only', () async {
    final db = makeTestDatabase();
    final store = IngestDraftStore(db, ownerUserId: 'u1');
    await store.putAll([
      _draft('old-confirmed', status: DraftStatus.confirmed),
      _draft('pending-keep'),
    ]);

    await store.pruneSettledBefore(DateTime.utc(2026, 5, 11));

    expect(await store.countByStatus(DraftStatus.confirmed), 0);
    expect(await store.countByStatus(DraftStatus.pending), 1);
    await db.close();
  });
}
