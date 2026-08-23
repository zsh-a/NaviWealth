import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/data_management/maintenance.dart';
import 'package:naviwealth/core/persistence/app_database.dart';

import '../persistence/test_database.dart';

void main() {
  test('retention removes expired local history and records the run', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 7, 12, 8);
    final oldIso = now.subtract(const Duration(days: 40)).toIso8601String();
    final freshIso = now.subtract(const Duration(days: 1)).toIso8601String();
    final oldMillis = now
        .subtract(const Duration(days: 200))
        .millisecondsSinceEpoch;

    await db.customStatement(
      'INSERT INTO ai_traces '
      '(request_id, owner_user_id, started_at_iso, payload_json) VALUES '
      "('old', 'user-a', ?, '{}'), ('fresh', 'user-a', ?, '{}')",
      <Object?>[oldIso, freshIso],
    );
    await db.customStatement(
      'INSERT INTO ai_undo_stack '
      '(token, owner_user_id, created_at_iso, expires_at_iso, kind, payload_json) '
      "VALUES ('expired', 'user-a', ?, ?, 'test', '{}')",
      <Object?>[oldIso, oldIso],
    );
    await db.customStatement(
      'INSERT INTO events '
      '(id, type, timestamp, source, owner_user_id, summary, payload_json, '
      "entities_json) VALUES ('old-event', 'test', ?, 'test', 'user-a', "
      "'old', '{}', '[]')",
      <Object?>[oldMillis],
    );
    await db.customStatement(
      'INSERT INTO memory_candidates '
      '(id, proposal_id, owner_user_id, target_type, operation, status, payload_json, '
      'created_at, updated_at, decided_at) VALUES '
      "('old-terminal', 'proposal-old', 'user-a', 'memory', 'create', 'rejected', "
      "'{}', ?, ?, ?), "
      "('old-pending', 'proposal-pending', 'user-a', 'memory', 'create', 'pending', "
      "'{}', ?, ?, NULL), "
      "('other-owner', 'proposal-other', 'user-b', 'memory', 'create', 'rejected', "
      "'{}', ?, ?, ?)",
      <Object?>[
        oldMillis,
        oldMillis,
        oldMillis,
        oldMillis,
        oldMillis,
        oldMillis,
        oldMillis,
        oldMillis,
      ],
    );

    final service = DataMaintenanceService(database: db, ownerUserId: 'user-a');
    final run = await service.runRetention(now: now);

    expect(run.status, 'completed');
    expect(run.rowsAffected, 4);
    expect(await _count(db, 'ai_traces'), 1);
    expect(await _count(db, 'ai_undo_stack'), 0);
    expect(await _count(db, 'events'), 0);
    expect(await _ids(db, 'memory_candidates'), {'old-pending', 'other-owner'});
    expect((await service.latestRun())?.id, run.id);
    expect(await service.isDue(now.add(const Duration(hours: 23))), isFalse);
  });

  test('automatic maintenance defaults on and persists changes', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final service = DataMaintenanceService(database: db, ownerUserId: 'user-a');

    expect(await service.readAutomaticEnabled(), isTrue);
    await service.setAutomaticEnabled(false);
    expect(await service.readAutomaticEnabled(), isFalse);
  });
}

Future<int> _count(AppDatabase db, String table) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM $table')
      .getSingle();
  return row.read<int>('c');
}

Future<Set<String>> _ids(AppDatabase db, String table) async {
  final rows = await db.customSelect('SELECT id FROM $table').get();
  return {for (final row in rows) row.read<String>('id')};
}
