// Wave 24 — DriftUndoStack contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/write/drift_undo_stack.dart';

import '../../../data/db/test_database.dart';

void main() {
  PersistedUndoEntry entry({
    required String token,
    required DateTime createdAt,
    DateTime? expiresAt,
    String kind = 'memo_edit',
    Map<String, Object?>? payload,
  }) => PersistedUndoEntry(
    token: token,
    kind: kind,
    payload: payload ?? <String, Object?>{'note': 'hello'},
    createdAt: createdAt,
    expiresAt: expiresAt,
  );

  test('put + all round-trips', () async {
    final db = makeTestDatabase();
    final stack = DriftUndoStack(db);
    await stack.put(entry(token: 't1', createdAt: DateTime.utc(2026, 5, 12, 9)));
    await stack.put(entry(token: 't2', createdAt: DateTime.utc(2026, 5, 12, 10)));
    final all = await stack.all();
    expect(all, hasLength(2));
    expect(all.first.token, 't2');
    expect(all.first.payload['note'], 'hello');
    await db.close();
  });

  test('take consumes the entry atomically', () async {
    final db = makeTestDatabase();
    final stack = DriftUndoStack(db);
    await stack.put(entry(token: 't1', createdAt: DateTime.utc(2026, 5, 12)));
    final hit = await stack.take('t1');
    expect(hit, isNotNull);
    expect(hit!.token, 't1');
    // Second take of the same token returns null.
    expect(await stack.take('t1'), isNull);
    expect(await stack.all(), isEmpty);
    await db.close();
  });

  test('take of unknown token is null', () async {
    final db = makeTestDatabase();
    final stack = DriftUndoStack(db);
    expect(await stack.take('nope'), isNull);
    await db.close();
  });

  test('pruneExpiredBefore drops only expired rows', () async {
    final db = makeTestDatabase();
    final stack = DriftUndoStack(db);
    await stack.put(entry(
      token: 'expired',
      createdAt: DateTime.utc(2026, 5, 12, 9),
      expiresAt: DateTime.utc(2026, 5, 12, 10),
    ));
    await stack.put(entry(
      token: 'fresh',
      createdAt: DateTime.utc(2026, 5, 12, 9),
      expiresAt: DateTime.utc(2026, 5, 12, 23),
    ));
    await stack.put(entry(
      token: 'no_expiry',
      createdAt: DateTime.utc(2026, 5, 12, 9),
    ));

    await stack.pruneExpiredBefore(DateTime.utc(2026, 5, 12, 12));
    final remaining = (await stack.all()).map((e) => e.token).toSet();
    expect(remaining, <String>{'fresh', 'no_expiry'});
    await db.close();
  });

  test('owner partition scopes reads', () async {
    final db = makeTestDatabase();
    final alice = DriftUndoStack(db, ownerUserId: 'alice');
    final bob = DriftUndoStack(db, ownerUserId: 'bob');
    await alice.put(entry(token: 'a', createdAt: DateTime.utc(2026, 5, 12)));
    await bob.put(entry(token: 'b', createdAt: DateTime.utc(2026, 5, 12)));
    expect((await alice.all()).map((e) => e.token), <String>['a']);
    expect((await bob.all()).map((e) => e.token), <String>['b']);
    // Cross-owner take returns null.
    expect(await alice.take('b'), isNull);
    expect(await bob.all(), hasLength(1));
    await db.close();
  });

  test('Wave 35: watchAll yields the initial snapshot', () async {
    final db = makeTestDatabase();
    final stack = DriftUndoStack(db);
    await stack.put(entry(token: 'a', createdAt: DateTime.utc(2026, 5, 12)));
    // First emission must reflect the row that's already there. We use
    // .first to avoid the async* loop's broadcast-stream await-for
    // hanging the test runner on cleanup.
    final initial = await stack.watchAll().first;
    expect(initial.map((e) => e.token), <String>['a']);
    stack.dispose();
    await db.close();
  });

  test('payload round-trip preserves nested JSON', () async {
    final db = makeTestDatabase();
    final stack = DriftUndoStack(db);
    final payload = <String, Object?>{
      'entity_id': 'jrnl_123',
      'prior_note': '咖啡',
      'tags': <String>['food', 'coffee'],
      'meta': <String, Object?>{'amount_minor': '-450', 'currency': 'USD'},
    };
    await stack.put(entry(
      token: 't',
      createdAt: DateTime.utc(2026, 5, 12),
      payload: payload,
    ));
    final read = await stack.take('t');
    expect(read!.payload, payload);
    await db.close();
  });
}
