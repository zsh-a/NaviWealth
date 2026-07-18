import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naviwealth/core/sync/hlc.dart';

import '../../core/persistence/app_database.dart';
import '../auth/domain_scope.dart';
import '../logging/app_logger.dart';
import '../sync/drift_sync_storage.dart';
import '../sync/op_outbox.dart';
import '../sync/sync_table_registry.dart';
import 'backup_codec.dart';
import 'backup_table_registry.dart';

const _backupMagic = 'naviwealth.backup.v1';

/// Result of a successful backup restore.
class RestoreResult {
  const RestoreResult({
    required this.tableCounts,
    required this.archiveSchemaVersion,
    required this.archiveDomain,
  });

  final Map<String, int> tableCounts;
  final int archiveSchemaVersion;
  final DomainScope? archiveDomain;

  int get totalRows => tableCounts.values.fold(0, (sum, c) => sum + c);
  int get tableCount => tableCounts.length;

  /// Machine-readable diagnostics without table names, row ids, or payloads.
  Map<String, Object> toDiagnosticJson() => <String, Object>{
    'schema_version': archiveSchemaVersion,
    'domain': archiveDomain?.wire ?? 'full',
    'table_count': tableCount,
    'row_count': totalRows,
  };
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
    // Retained for call-site compatibility. The sync-v3 outbox is a pure
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

  /// Export all backup-eligible local data as an encrypted backup envelope.
  Future<Uint8List> exportBackup({
    required String passphrase,
    int? overrideIterations,
    DomainScope? domain,
  }) async {
    final sw = Stopwatch()..start();
    _logger.i('backup: export starting (schema=${_db.schemaVersion})');
    final schemaVersion = _db.schemaVersion;
    final tableCounts = <String, int>{};
    final data = <String, List<Map<String, Object?>>>{};

    final backupTables = domain == null
        ? kBackupTables
        : <String>[
            for (final registration in kSyncTableRegistrations)
              if (registration.backupEligible &&
                  registration.domainPrefix == _prefixForScope(domain))
                registration.table,
          ];
    for (final tableName in backupTables) {
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
        'domain': domain?.wire,
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
    _logger.event(
      'core.backup.export.completed',
      fields: <String, Object?>{
        'schema_version': schemaVersion,
        'domain': domain?.wire ?? 'full',
        'table_count': tableCounts.length,
        'row_count': totalRows,
        'file_bytes_count': bytes.length,
        'duration_ms': sw.elapsedMilliseconds,
        'outcome': 'success',
      },
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
    DomainScope? expectedDomain,
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

    // 4. Parse and validate the entire logical payload before pausing sync or
    // opening the destructive transaction. A malformed archive must never get
    // far enough to clear a table.
    _logger.d('backup: parsing and validating JSON');
    final root = _decodeJsonObject(plaintext);
    final header = _requireObject(root['header'], 'header');
    if (header['magic'] != _backupMagic) {
      _logger.e(
        'backup: invalid magic — '
        'got=${header['magic']}, expected=$_backupMagic',
      );
      throw const BackupValidationException('Invalid backup magic');
    }

    final backupSchema = _requireInt(header['schemaVersion'], 'schemaVersion');
    if (backupSchema != envelope.schemaVersion) {
      throw const BackupValidationException(
        'Envelope and payload schema versions do not match',
      );
    }
    final createdAt = _requireString(header['createdAt'], 'createdAt');
    if (DateTime.tryParse(createdAt) == null) {
      throw const BackupValidationException('Invalid createdAt timestamp');
    }
    final headerTables = _requireObject(header['tables'], 'header.tables');
    _logger.d(
      'backup: header — schema=$backupSchema, created=$createdAt, '
      'tables=${headerTables.keys.toList()}',
    );

    final dataRaw = _requireObject(root['data'], 'data');
    final data = <String, List<Map<String, Object?>>>{};

    for (final entry in dataRaw.entries) {
      final key = entry.key;
      if (!isBackupTable(key)) {
        _logger.e('backup: unknown table "$key"');
        throw BackupValidationException('Unknown table: $key');
      }
      data[key] = _requireRows(entry.value, key);
    }
    final backupDomainValue = header['domain'];
    if (backupDomainValue != null && backupDomainValue is! String) {
      throw const BackupValidationException('Invalid backup domain');
    }
    final backupDomainWire = backupDomainValue as String?;
    if (expectedDomain != null && backupDomainWire != expectedDomain.wire) {
      throw BackupValidationException(
        'Expected ${expectedDomain.wire} backup, got '
        '${backupDomainWire ?? 'full archive'}',
      );
    }
    final backupDomain = backupDomainWire == null
        ? null
        : DomainScope.tryParse(backupDomainWire);
    if (backupDomainWire != null) {
      if (backupDomain == null) {
        throw BackupValidationException(
          'Unknown backup domain: $backupDomainWire',
        );
      }
      final expectedPrefix = _prefixForScope(backupDomain);
      for (final key in data.keys) {
        if (kSyncTableRegistry[key]?.domainPrefix != expectedPrefix) {
          throw BackupValidationException(
            'Table $key does not belong to $backupDomainWire',
          );
        }
      }
    }

    final declaredTables = headerTables.keys.toSet();
    final actualTables = data.keys.toSet();
    if (!_setsEqual(declaredTables, actualTables)) {
      throw BackupValidationException(
        'Header/data table mismatch: declared=${declaredTables.length}, '
        'actual=${actualTables.length}',
      );
    }

    // Current-schema archives must be complete for their declared scope.
    // Older logical archives may legitimately predate newly registered tables;
    // their rows still migrate through the current Drift schema on insertion.
    if (backupSchema == _db.schemaVersion) {
      final expectedTables = backupDomainWire == null
          ? kBackupTables.toSet()
          : <String>{
              for (final registration in kSyncTableRegistrations)
                if (registration.backupEligible &&
                    registration.domainPrefix ==
                        _prefixForScope(
                          DomainScope.tryParse(backupDomainWire)!,
                        ))
                  registration.table,
            };
      if (!_setsEqual(actualTables, expectedTables)) {
        throw BackupValidationException(
          'Incomplete current-schema archive: expected '
          '${expectedTables.length} tables, got ${actualTables.length}',
        );
      }
    }

    final restoreTableCounts = <String, int>{};
    for (final entry in data.entries) {
      final declaredCount = _requireInt(
        headerTables[entry.key],
        'header.tables.${entry.key}',
      );
      if (declaredCount < 0 || declaredCount != entry.value.length) {
        throw BackupValidationException(
          'Row count mismatch for ${entry.key}: declared=$declaredCount, '
          'actual=${entry.value.length}',
        );
      }
      for (final row in entry.value) {
        if (row.isEmpty) {
          throw BackupValidationException('Empty row in ${entry.key}');
        }
        if (shouldEnqueueRestoreOpForBackupTable(entry.key) &&
            _extractRowId(entry.key, row).isEmpty) {
          throw BackupValidationException(
            'Missing primary key in ${entry.key}',
          );
        }
      }
      restoreTableCounts[entry.key] = entry.value.length;
    }
    final totalIncoming = restoreTableCounts.values.fold(0, (s, c) => s + c);
    _logger.d(
      'backup: validation passed — $totalIncoming rows across '
      '${restoreTableCounts.length} tables',
    );

    if (!isOutboxBoundToDatabase(_outbox, _db)) {
      throw StateError(
        'Backup restore requires a transaction-bound outbox store',
      );
    }

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
        await _db.customStatement('PRAGMA defer_foreign_keys = ON');
        // Full archives contain the complete registry; domain archives contain
        // only that domain. Replace exactly the tables declared by the archive.
        for (final tableName in data.keys) {
          await _db.customStatement('DELETE FROM $tableName');
        }
        final outboxTables = data.keys.toList(growable: false);
        if (outboxTables.isNotEmpty) {
          final placeholders = List<String>.filled(
            outboxTables.length,
            '?',
          ).join(',');
          await _db.customStatement(
            'DELETE FROM op_outbox WHERE table_name IN ($placeholders)',
            outboxTables,
          );
        }
        _logger.d('backup: cleared archive tables + matching outbox rows');

        // Insert restored rows and enqueue ops.
        for (final entry in data.entries) {
          final tableName = entry.key;
          final rows = entry.value;
          var count = 0;

          for (final row in rows) {
            await _insertRow(tableName, row);
            if (shouldEnqueueRestoreOpForBackupTable(tableName)) {
              await _enqueueRestoreOp(tableName, row);
            }
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

      final result = RestoreResult(
        tableCounts: tableCounts,
        archiveSchemaVersion: backupSchema,
        archiveDomain: backupDomain,
      );
      sw.stop();
      _logger.i(
        'backup: restore complete (${result.totalRows} rows, '
        '${sw.elapsedMilliseconds}ms total)',
      );
      _logger.event(
        'core.backup.restore.completed',
        fields: <String, Object?>{
          ...result.toDiagnosticJson(),
          'duration_ms': sw.elapsedMilliseconds,
          'outcome': 'success',
        },
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
  /// sync-v3 outbox only needs `(table, rowId)` — the engine reads the
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
  /// Most tables use `id` as PK. Singleton user-scoped tables use the backup
  /// table registry's PK override.
  String _extractRowId(String tableName, Map<String, Object?> row) {
    final pk = backupPrimaryKeyForTable(tableName);
    final value = row[pk] ?? (pk == 'user_id' ? row['userId'] : null);
    return value?.toString() ?? '';
  }
}

Map<String, Object?> _decodeJsonObject(Uint8List plaintext) {
  try {
    return _requireObject(jsonDecode(utf8.decode(plaintext)), 'root');
  } on BackupValidationException {
    rethrow;
  } on Object catch (error) {
    throw BackupValidationException('Malformed backup payload: $error');
  }
}

Map<String, Object?> _requireObject(Object? value, String field) {
  if (value is! Map<Object?, Object?>) {
    throw BackupValidationException('$field must be an object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw BackupValidationException('$field contains a non-string key');
    }
    result[key] = entry.value;
  }
  return result;
}

List<Map<String, Object?>> _requireRows(Object? value, String table) {
  if (value is! List<Object?>) {
    throw BackupValidationException('Table $table must contain a row list');
  }
  return <Map<String, Object?>>[
    for (var index = 0; index < value.length; index++)
      _requireObject(value[index], '$table[$index]'),
  ];
}

int _requireInt(Object? value, String field) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw BackupValidationException('$field must be an integer');
}

String _requireString(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw BackupValidationException('$field must be a non-empty string');
}

bool _setsEqual<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);

String _prefixForScope(DomainScope scope) => switch (scope) {
  DomainScope.finance => kFinanceDomainPrefix,
  DomainScope.health => kHealthDomainPrefix,
  DomainScope.knowledge => kKnowledgeDomainPrefix,
  DomainScope.execution => kExecutionDomainPrefix,
};
