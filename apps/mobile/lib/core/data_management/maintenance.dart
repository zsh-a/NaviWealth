import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../persistence/app_database.dart';

class DataMaintenanceRun {
  const DataMaintenanceRun({
    required this.id,
    required this.status,
    required this.startedAt,
    required this.rowsAffected,
    this.finishedAt,
    this.error,
  });

  final String id;
  final String status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int rowsAffected;
  final String? error;
}

class DataMaintenanceService {
  DataMaintenanceService({
    required AppDatabase database,
    required String ownerUserId,
  }) : _database = database,
       _ownerUserId = ownerUserId;

  final AppDatabase _database;
  final String _ownerUserId;

  static const _autoKey = 'data.maintenance.auto_enabled';
  static const automaticInterval = Duration(hours: 24);

  Future<bool> readAutomaticEnabled() async {
    final row = await _database
        .customSelect(
          'SELECT value FROM sync_meta WHERE key = ?',
          variables: [Variable.withString(_autoKey)],
        )
        .getSingleOrNull();
    return row?.read<String>('value') != 'false';
  }

  Future<void> setAutomaticEnabled(bool enabled) => _database.customStatement(
    'INSERT INTO sync_meta(key, value) VALUES (?, ?) '
    'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    <Object?>[_autoKey, '$enabled'],
  );

  Future<DataMaintenanceRun?> latestRun() async {
    final row = await _database
        .customSelect(
          'SELECT id, status, started_at, finished_at, rows_affected, error '
          'FROM data_maintenance_runs WHERE owner_user_id = ? '
          'ORDER BY started_at DESC LIMIT 1',
          variables: [Variable.withString(_ownerUserId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    final finishedMillis = row.readNullable<int>('finished_at');
    return DataMaintenanceRun(
      id: row.read<String>('id'),
      status: row.read<String>('status'),
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('started_at'),
        isUtc: true,
      ),
      finishedAt: finishedMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(finishedMillis, isUtc: true),
      rowsAffected: row.read<int>('rows_affected'),
      error: row.readNullable<String>('error'),
    );
  }

  Future<bool> isDue(DateTime now) async {
    final latest = await latestRun();
    return latest == null ||
        now.toUtc().difference(latest.startedAt) >= automaticInterval;
  }

  Future<DataMaintenanceRun> runRetention({DateTime? now}) async {
    final started = (now ?? DateTime.now()).toUtc();
    final id = const Uuid().v4();
    await _database.customStatement(
      'INSERT INTO data_maintenance_runs '
      '(id, owner_user_id, action, status, started_at, detail_json) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      <Object?>[
        id,
        _ownerUserId,
        'retention',
        'running',
        started.millisecondsSinceEpoch,
        '{}',
      ],
    );

    final counts = <String, int>{};
    try {
      await _database.transaction(() async {
        counts['ai_undo_stack'] = await _deleteIsoBefore(
          table: 'ai_undo_stack',
          column: 'expires_at_iso',
          cutoff: started,
          requireNonNull: true,
        );
        counts['ai_traces'] = await _deleteIsoBefore(
          table: 'ai_traces',
          column: 'started_at_iso',
          cutoff: started.subtract(const Duration(days: 30)),
        );
        counts['agent_runtime_checkpoints'] = await _deleteMillisBefore(
          table: 'agent_runtime_checkpoints',
          column: 'expires_at',
          cutoff: started,
          requireNonNull: true,
        );
        counts['agent_artifacts'] = await _database.customUpdate(
          'DELETE FROM agent_artifacts WHERE owner_user_id = ? AND '
          '((expires_at IS NOT NULL AND expires_at <= ?) OR '
          '(dismissed_at IS NOT NULL AND created_at < ?))',
          variables: <Variable<Object>>[
            Variable<Object>(_ownerUserId),
            Variable<Object>(started.millisecondsSinceEpoch),
            Variable<Object>(
              started.subtract(const Duration(days: 90)).millisecondsSinceEpoch,
            ),
          ],
        );
        counts['agent_runs'] = await _database.customUpdate(
          'DELETE FROM agent_runs WHERE owner_user_id = ? '
          'AND finished_at IS NOT NULL AND finished_at < ?',
          variables: <Variable<Object>>[
            Variable<Object>(_ownerUserId),
            Variable<Object>(
              started.subtract(const Duration(days: 90)).millisecondsSinceEpoch,
            ),
          ],
        );
        counts['events'] = await _deleteMillisBefore(
          table: 'events',
          column: 'timestamp',
          cutoff: started.subtract(const Duration(days: 180)),
        );
        counts['ingest_attachments'] = await _deleteIsoBefore(
          table: 'ingest_attachments',
          column: 'expires_at_iso',
          cutoff: started,
          requireNonNull: true,
        );
        counts['ingest_drafts'] = await _deleteIsoBefore(
          table: 'ingest_drafts',
          column: 'expires_at_iso',
          cutoff: started,
          requireNonNull: true,
        );
      });
      final finished = DateTime.now().toUtc();
      final total = counts.values.fold<int>(0, (sum, count) => sum + count);
      await _finishRun(
        id: id,
        status: 'completed',
        finishedAt: finished,
        rowsAffected: total,
        detail: counts,
      );
      return DataMaintenanceRun(
        id: id,
        status: 'completed',
        startedAt: started,
        finishedAt: finished,
        rowsAffected: total,
      );
    } catch (error) {
      final finished = DateTime.now().toUtc();
      await _finishRun(
        id: id,
        status: 'failed',
        finishedAt: finished,
        rowsAffected: 0,
        detail: counts,
        error: '$error',
      );
      rethrow;
    }
  }

  Future<int> _deleteIsoBefore({
    required String table,
    required String column,
    required DateTime cutoff,
    bool requireNonNull = false,
  }) => _database.customUpdate(
    'DELETE FROM $table WHERE owner_user_id = ? AND '
    '${requireNonNull ? '$column IS NOT NULL AND ' : ''}$column <= ?',
    variables: <Variable<Object>>[
      Variable<Object>(_ownerUserId),
      Variable<Object>(cutoff.toIso8601String()),
    ],
  );

  Future<int> _deleteMillisBefore({
    required String table,
    required String column,
    required DateTime cutoff,
    bool requireNonNull = false,
  }) => _database.customUpdate(
    'DELETE FROM $table WHERE owner_user_id = ? AND '
    '${requireNonNull ? '$column IS NOT NULL AND ' : ''}$column <= ?',
    variables: <Variable<Object>>[
      Variable<Object>(_ownerUserId),
      Variable<Object>(cutoff.millisecondsSinceEpoch),
    ],
  );

  Future<void> _finishRun({
    required String id,
    required String status,
    required DateTime finishedAt,
    required int rowsAffected,
    required Map<String, int> detail,
    String? error,
  }) => _database.customStatement(
    'UPDATE data_maintenance_runs SET status = ?, finished_at = ?, '
    'rows_affected = ?, detail_json = ?, error = ? WHERE id = ?',
    <Object?>[
      status,
      finishedAt.millisecondsSinceEpoch,
      rowsAffected,
      jsonEncode(detail),
      error,
      id,
    ],
  );
}
