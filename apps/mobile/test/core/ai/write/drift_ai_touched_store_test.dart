// Wave 39 — DriftAiTouchedStore contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/write/drift_ai_touched_store.dart';

import '../../../data/db/test_database.dart';

void main() {
  AiTouchedEntity touch({
    required String id,
    required DateTime at,
    String type = 'journal_entries',
    String? kind = 'expense',
    String? traceId,
  }) => AiTouchedEntity(
    entityType: type,
    entityId: id,
    touchedAt: at,
    kindLabel: kind,
    traceId: traceId,
  );

  test('recordTouch + latestTouch round-trips fields', () async {
    final db = makeTestDatabase();
    final store = DriftAiTouchedStore(db);
    await store.recordTouch(
      touch(id: 'e1', at: DateTime.utc(2026, 5, 12, 9), traceId: 'r_42'),
    );
    final hit = await store.latestTouch('journal_entries', 'e1');
    expect(hit, isNotNull);
    expect(hit!.entityId, 'e1');
    expect(hit.kindLabel, 'expense');
    expect(hit.traceId, 'r_42');
    expect(
      hit.touchedAt.toUtc().toIso8601String(),
      startsWith('2026-05-12T09:00'),
    );
    store.dispose();
    await db.close();
  });

  test('latestTouch returns null when entity has no record', () async {
    final db = makeTestDatabase();
    final store = DriftAiTouchedStore(db);
    expect(await store.latestTouch('journal_entries', 'nope'), isNull);
    store.dispose();
    await db.close();
  });

  test('recordTouch overwrites the previous touch (latest wins)', () async {
    final db = makeTestDatabase();
    final store = DriftAiTouchedStore(db);
    await store.recordTouch(touch(id: 'e1', at: DateTime.utc(2026, 5, 12, 9)));
    await store.recordTouch(touch(id: 'e1', at: DateTime.utc(2026, 5, 12, 10)));
    final hit = await store.latestTouch('journal_entries', 'e1');
    expect(
      hit!.touchedAt.toUtc().toIso8601String(),
      startsWith('2026-05-12T10:00'),
    );
    store.dispose();
    await db.close();
  });

  test('forget removes the row', () async {
    final db = makeTestDatabase();
    final store = DriftAiTouchedStore(db);
    await store.recordTouch(touch(id: 'e1', at: DateTime.utc(2026, 5, 12)));
    await store.forget('journal_entries', 'e1');
    expect(await store.latestTouch('journal_entries', 'e1'), isNull);
    store.dispose();
    await db.close();
  });

  test('owner partition scopes reads', () async {
    final db = makeTestDatabase();
    final alice = DriftAiTouchedStore(db, ownerUserId: 'alice');
    final bob = DriftAiTouchedStore(db, ownerUserId: 'bob');
    await alice.recordTouch(touch(id: 'e1', at: DateTime.utc(2026, 5, 12)));
    expect(await alice.latestTouch('journal_entries', 'e1'), isNotNull);
    expect(await bob.latestTouch('journal_entries', 'e1'), isNull);
    alice.dispose();
    bob.dispose();
    await db.close();
  });

  test('different entity types share id space without collision', () async {
    final db = makeTestDatabase();
    final store = DriftAiTouchedStore(db);
    await store.recordTouch(
      touch(
        id: 'shared_id',
        at: DateTime.utc(2026, 5, 12),
        type: 'journal_entries',
        kind: 'expense',
      ),
    );
    await store.recordTouch(
      touch(
        id: 'shared_id',
        at: DateTime.utc(2026, 5, 13),
        type: 'accounts',
        kind: 'account_create',
      ),
    );
    final exp = await store.latestTouch('journal_entries', 'shared_id');
    final acc = await store.latestTouch('accounts', 'shared_id');
    expect(exp!.kindLabel, 'expense');
    expect(acc!.kindLabel, 'account_create');
    store.dispose();
    await db.close();
  });

  test('watchLatest yields the initial snapshot for an existing row', () async {
    final db = makeTestDatabase();
    final store = DriftAiTouchedStore(db);
    await store.recordTouch(touch(id: 'e1', at: DateTime.utc(2026, 5, 12)));
    final first = await store.watchLatest('journal_entries', 'e1').first;
    expect(first!.entityId, 'e1');
    store.dispose();
    await db.close();
  });

  test('watchLatest yields null when no row exists', () async {
    final db = makeTestDatabase();
    final store = DriftAiTouchedStore(db);
    final first = await store.watchLatest('journal_entries', 'missing').first;
    expect(first, isNull);
    store.dispose();
    await db.close();
  });
}
