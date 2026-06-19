import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/write/write.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  PersistedUndoEntry entry({
    required String token,
    required String kind,
    required DateTime createdAt,
    DateTime? expiresAt,
  }) {
    return PersistedUndoEntry(
      token: token,
      kind: kind,
      payload: <String, Object?>{'summary_zh': token},
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  test('undo consumes an entry and runs the matching reverter', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final stack = DriftUndoStack(db);
    addTearDown(stack.dispose);
    final seen = <String>[];
    final dispatcher = PersistedUndoDispatcher(
      stack: stack,
      reverters: <String, PersistedUndoReverter>{
        'known': (entry) async => seen.add(entry.token),
      },
      now: () => DateTime.utc(2026, 6, 19, 12),
    );

    await stack.put(
      entry(
        token: 't1',
        kind: 'known',
        createdAt: DateTime.utc(2026, 6, 19, 12),
        expiresAt: DateTime.utc(2026, 6, 19, 12, 1),
      ),
    );

    final result = await dispatcher.undo('t1');

    expect(result.status, PersistedUndoDispatchStatus.applied);
    expect(result.didApply, isTrue);
    expect(seen, <String>['t1']);
    expect(await stack.take('t1'), isNull);
  });

  test('undo returns missing for unknown tokens', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final stack = DriftUndoStack(db);
    addTearDown(stack.dispose);
    final dispatcher = PersistedUndoDispatcher(
      stack: stack,
      reverters: const <String, PersistedUndoReverter>{},
    );

    final result = await dispatcher.undo('missing');

    expect(result.status, PersistedUndoDispatchStatus.missing);
    expect(result.entry, isNull);
  });

  test('undo consumes but does not run expired entries', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final stack = DriftUndoStack(db);
    addTearDown(stack.dispose);
    var ran = false;
    final dispatcher = PersistedUndoDispatcher(
      stack: stack,
      reverters: <String, PersistedUndoReverter>{
        'known': (_) async => ran = true,
      },
      now: () => DateTime.utc(2026, 6, 19, 12, 2),
    );
    await stack.put(
      entry(
        token: 'expired',
        kind: 'known',
        createdAt: DateTime.utc(2026, 6, 19, 12),
        expiresAt: DateTime.utc(2026, 6, 19, 12, 1),
      ),
    );

    final result = await dispatcher.undo('expired');

    expect(result.status, PersistedUndoDispatchStatus.expired);
    expect(ran, isFalse);
    expect(await stack.take('expired'), isNull);
  });

  test('undo reports unsupported kinds', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final stack = DriftUndoStack(db);
    addTearDown(stack.dispose);
    final dispatcher = PersistedUndoDispatcher(
      stack: stack,
      reverters: const <String, PersistedUndoReverter>{},
      now: () => DateTime.utc(2026, 6, 19, 12),
    );
    await stack.put(
      entry(
        token: 'unsupported',
        kind: 'unknown',
        createdAt: DateTime.utc(2026, 6, 19, 12),
        expiresAt: DateTime.utc(2026, 6, 19, 12, 1),
      ),
    );

    final result = await dispatcher.undo('unsupported');

    expect(result.status, PersistedUndoDispatchStatus.unsupported);
    expect(result.entry!.kind, 'unknown');
  });
}
