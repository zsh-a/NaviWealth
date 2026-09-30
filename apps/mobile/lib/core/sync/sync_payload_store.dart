import 'dart:convert';

import 'package:drift/drift.dart';

import '../persistence/app_database.dart';

/// Local-only compatibility state. It does not participate in Sync or backups.
class SyncPayloadStore {
  SyncPayloadStore(this.db);

  final AppDatabase db;

  Future<Map<String, Object?>> extras(
    String table,
    String id,
    String owner,
  ) async {
    final row = await db
        .customSelect(
          'SELECT fields_json FROM sync_row_extras '
          'WHERE table_name = ? AND row_id = ? AND owner_user_id = ?',
          variables: [Variable(table), Variable(id), Variable(owner)],
        )
        .getSingleOrNull();
    return row == null
        ? <String, Object?>{}
        : (jsonDecode(row.read<String>('fields_json')) as Map<String, dynamic>)
              .cast<String, Object?>();
  }

  Future<void> writeExtras(
    String table,
    String id,
    String owner,
    Map<String, Object?> fields,
  ) async {
    if (fields.isEmpty) {
      await db.customStatement(
        'DELETE FROM sync_row_extras '
        'WHERE table_name = ? AND row_id = ? AND owner_user_id = ?',
        [table, id, owner],
      );
      return;
    }
    await db.customStatement(
      'INSERT INTO sync_row_extras '
      '(owner_user_id, table_name, row_id, fields_json) VALUES (?, ?, ?, ?) '
      'ON CONFLICT(owner_user_id, table_name, row_id) '
      'DO UPDATE SET fields_json = excluded.fields_json',
      [owner, table, id, jsonEncode(fields)],
    );
  }
}
