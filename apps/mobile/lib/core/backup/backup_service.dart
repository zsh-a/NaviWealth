import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/persistence/app_database.dart';
import '../../data/domain/hlc.dart';
import '../logging/app_logger.dart';
import '../sync/op_outbox.dart';
import '../sync/row_applier.dart';
import 'backup_codec.dart';

const _backupMagic = 'naviwealth.backup.v1';

/// Result of a successful backup restore.
class RestoreResult {
  const RestoreResult({required this.tableCounts});
  final Map<String, int> tableCounts;

  int get totalRows => tableCounts.values.fold(0, (sum, c) => sum + c);
}

/// Thrown when the backup's schema version is newer than the app's.
class BackupSchemaTooNewException implements Exception {
  const BackupSchemaTooNewException(this.backupVersion, this.currentVersion);
  final int backupVersion;
  final int currentVersion;

  @override
  String toString() =>
      'Backup schema v$backupVersion is newer than app schema v$currentVersion';
}

/// Thrown when the backup payload fails structural validation.
class BackupValidationException implements Exception {
  const BackupValidationException(this.message);
  final String message;

  @override
  String toString() => 'Backup validation failed: $message';
}

/// Orchestrates encrypted backup export and restore.
class BackupService {
  BackupService({
    required AppDatabase db,
    required BackupCodec codec,
    required OutboxStore outbox,
    // Retained for call-site compatibility. The sync-v2 outbox is a pure
    // dirty-pointer log, so the restore enqueue no longer needs a device id
    // or an HLC stamp — the sync engine reads each restored row's current
    // state (including its own `hlc`) directly at push time.
    String? deviceId,
    Future<Hlc> Function()? stampHlc,
    AppLogger? logger,
  }) : _db = db,
       _codec = codec,
       _outbox = outbox,
       _logger = logger ?? AppLogger.instance;

  final AppDatabase _db;
  final BackupCodec _codec;
  final OutboxStore _outbox;
  final AppLogger _logger;

  /// Export all syncable user data as an encrypted backup envelope.
  Future<Uint8List> exportBackup({
    required String passphrase,
    int? overrideIterations,
  }) async {
    final sw = Stopwatch()..start();
    _logger.i('backup: export starting (schema=${_db.schemaVersion})');
    final schemaVersion = _db.schemaVersion;
    final tableCounts = <String, int>{};
    final data = <String, List<Map<String, Object?>>>{};

    for (final tableName in kSyncableTables) {
      final rows = await _db.customSelect('SELECT * FROM $tableName').get();
      final rowMaps = <Map<String, Object?>>[];
      for (final row in rows) {
        rowMaps.add(_rowToMap(row));
      }
      data[tableName] = rowMaps;
      tableCounts[tableName] = rowMaps.length;
      _logger.d('backup: exported $tableName (${rowMaps.length} rows)');
    }

    final totalRows = tableCounts.values.fold(0, (s, c) => s + c);
    _logger.d(
      'backup: collected $totalRows rows across '
      '${tableCounts.length} tables, encoding payload',
    );

    final payload = {
      'header': {
        'magic': _backupMagic,
        'schemaVersion': schemaVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'tables': tableCounts,
      },
      'data': data,
    };

    final plaintext = utf8.encode(jsonEncode(payload));
    _logger.d(
      'backup: plaintext size=${plaintext.length} bytes, encrypting '
      '(iterations=${overrideIterations ?? backupPbkdf2Iterations})',
    );
    final envelope = await _codec.encrypt(
      passphrase: passphrase,
      plaintext: Uint8List.fromList(plaintext),
      schemaVersion: schemaVersion,
      iterations: overrideIterations ?? backupPbkdf2Iterations,
    );
    final bytes = envelope.encodeBytes();
    sw.stop();
    _logger.i(
      'backup: export complete (${bytes.length} bytes, '
      '$totalRows rows, ${sw.elapsedMilliseconds}ms)',
    );
    return bytes;
  }

  /// Decrypt and restore from backup bytes. Wipes all local data first.
  ///
  /// [pauseSync] and [resumeSync] are called before and after the restore
  /// transaction to prevent the sync engine from interfering.
  Future<RestoreResult> restoreBackup({
    required String passphrase,
    required Uint8List fileBytes,
    void Function()? pauseSync,
    void Function()? resumeSync,
  }) async {
    final sw = Stopwatch()..start();
    _logger.i('backup: restore starting (file=${fileBytes.length} bytes)');

    // 1. Decode and validate envelope.
    _logger.d('backup: decoding envelope');
    final envelope = BackupEnvelope.decodeBytes(fileBytes);
    _logger.d(
      'backup: envelope decoded — schema=${envelope.schemaVersion}, '
      'iterations=${envelope.iterations}, '
      'created=${envelope.createdAt.toIso8601String()}',
    );

    // 2. Reject newer schema versions.
    if (envelope.schemaVersion > _db.schemaVersion) {
      _logger.e(
        'backup: schema too new (backup=${envelope.schemaVersion}, '
        'current=${_db.schemaVersion})',
      );
      throw BackupSchemaTooNewException(
        envelope.schemaVersion,
        _db.schemaVersion,
      );
    }

    // 3. Decrypt.
    _logger.d('backup: decrypting (PBKDF2 ${envelope.iterations} iterations)');
    final decryptSw = Stopwatch()..start();
    final plaintext = await _codec.decrypt(
      passphrase: passphrase,
      envelope: envelope,
    );
    decryptSw.stop();
    _logger.d(
      'backup: decrypted ${plaintext.length} bytes '
      '(${decryptSw.elapsedMilliseconds}ms)',
    );

    // 4. Parse and validate JSON structure.
    _logger.d('backup: parsing and validating JSON');
    final json = jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
    final header = json['header'] as Map<String, Object?>?;
    if (header == null || header['magic'] != _backupMagic) {
      _logger.e(
        'backup: invalid magic — '
        'got=${header?['magic']}, expected=$_backupMagic',
      );
      throw const BackupValidationException('Invalid backup magic');
    }

    final backupSchema = header['schemaVersion'] as int?;
    final createdAt = header['createdAt'] as String?;
    final headerTables = header['tables'] as Map<String, Object?>?;
    _logger.d(
      'backup: header — schema=$backupSchema, created=$createdAt, '
      'tables=${headerTables?.keys.toList()}',
    );

    final data = json['data'] as Map<String, Object?>?;
    if (data == null) {
      _logger.e('backup: missing data section');
      throw const BackupValidationException('Missing data section');
    }

    for (final key in data.keys) {
      if (!kSyncableTables.contains(key)) {
        _logger.e('backup: unknown table "$key"');
        throw BackupValidationException('Unknown table: $key');
      }
    }

    final restoreTableCounts = <String, int>{};
    for (final entry in data.entries) {
      restoreTableCounts[entry.key] = (entry.value as List<Object?>).length;
    }
    final totalIncoming = restoreTableCounts.values.fold(0, (s, c) => s + c);
    _logger.d(
      'backup: validation passed — $totalIncoming rows across '
      '${restoreTableCounts.length} tables',
    );

    // 5. Pause sync to prevent concurrent mutations.
    _logger.d('backup: pausing sync');
    pauseSync?.call();

    try {
      final tableCounts = <String, int>{};

      // 6. Restore in a single transaction.
      _logger.d(
        'backup: starting restore transaction '
        '(wipe + insert + outbox enqueue)',
      );
      final txSw = Stopwatch()..start();
      await _db.transaction(() async {
        // Clear all existing data.
        for (final tableName in kSyncableTables) {
          await _db.customStatement('DELETE FROM $tableName');
        }
        await _db.customStatement('DELETE FROM op_outbox');
        _logger.d('backup: cleared all syncable tables + op_outbox');

        // Insert restored rows and enqueue ops.
        for (final entry in data.entries) {
          final tableName = entry.key;
          final rows = entry.value as List<Object?>;
          var count = 0;

          for (final rowRaw in rows) {
            final row = rowRaw as Map<String, Object?>;
            await _insertRow(tableName, row);
            await _enqueueRestoreOp(tableName, row);
            count++;
          }

          tableCounts[tableName] = count;
          _logger.d('backup: restored $tableName ($count rows)');
        }
      });
      txSw.stop();
      _logger.d(
        'backup: transaction committed '
        '(${txSw.elapsedMilliseconds}ms)',
      );

      final result = RestoreResult(tableCounts: tableCounts);
      sw.stop();
      _logger.i(
        'backup: restore complete (${result.totalRows} rows, '
        '${sw.elapsedMilliseconds}ms total)',
      );
      return result;
    } finally {
      _logger.d('backup: resuming sync');
      resumeSync?.call();
    }
  }

  /// Convert a Drift [QueryRow] to a JSON-serializable map.
  Map<String, Object?> _rowToMap(QueryRow row) {
    final map = <String, Object?>{};
    for (final column in row.data.keys) {
      final value = row.data[column];
      if (value is DateTime) {
        map[column] = value.toUtc().toIso8601String();
      } else {
        map[column] = value;
      }
    }
    return map;
  }

  /// Insert a single row from backup data into the database.
  Future<void> _insertRow(String tableName, Map<String, Object?> row) async {
    final columns = row.keys.toList();
    final placeholders = List.generate(columns.length, (_) => '?').join(', ');
    final columnList = columns.join(', ');
    final values = columns.map((c) => row[c]).toList();

    try {
      await _db.customStatement(
        'INSERT INTO $tableName ($columnList) VALUES ($placeholders)',
        values,
      );
    } catch (e) {
      _logger.e(
        'backup: insert failed for $tableName — '
        'columns=$columns, error=$e',
      );
      rethrow;
    }
  }

  /// Mark a restored row dirty so the sync engine re-pushes it. The
  /// sync-v2 outbox only needs `(table, rowId)` — the engine reads the
  /// row's current state at push time.
  Future<void> _enqueueRestoreOp(
    String tableName,
    Map<String, Object?> row,
  ) async {
    final rowId = _extractRowId(tableName, row);
    await _outbox.enqueue(table: tableName, rowId: rowId);
  }

  /// Extract the primary key value from a row map.
  ///
  /// Most tables use `id` as PK. `settings` uses `userId` (mapped to
  /// `user_id` in SQL). We handle the known cases.
  String _extractRowId(String tableName, Map<String, Object?> row) {
    if (tableName == 'settings') {
      return row['user_id'] as String? ?? row['userId'] as String? ?? '';
    }
    return row['id'] as String? ?? '';
  }
}
