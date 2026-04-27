import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'backup_codec.dart';

/// Tables included in a backup, in dependency order. Order matters on
/// restore: parent rows must be inserted before child rows referencing
/// them via foreign keys.
const List<String> _backupTableOrder = [
  'app_meta',
  'fx_rates',
  'accounts',
  'assets',
  'transactions',
];

class BackupService {
  BackupService(this._db, {BackupCodec? codec})
    : _codec = codec ?? BackupCodec();

  final AppDatabase _db;
  final BackupCodec _codec;

  Future<Uint8List> exportEncrypted({required String passphrase}) async {
    final dump = await _dump();
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(dump)));
    final envelope = await _codec.encrypt(
      passphrase: passphrase,
      plaintext: plaintext,
      schemaVersion: _db.schemaVersion,
    );
    return envelope.encodeBytes();
  }

  Future<BackupRestoreReport> restoreEncrypted({
    required String passphrase,
    required Uint8List bytes,
  }) async {
    final envelope = BackupEnvelope.decodeBytes(bytes);
    if (envelope.schemaVersion > _db.schemaVersion) {
      throw BackupSchemaMismatch(
        backupVersion: envelope.schemaVersion,
        appVersion: _db.schemaVersion,
      );
    }
    final plaintext = await _codec.decrypt(
      passphrase: passphrase,
      envelope: envelope,
    );
    final dump = jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
    return _applyDump(dump, envelope: envelope);
  }

  Future<Map<String, Object?>> _dump() async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final name in _backupTableOrder) {
      final rows = await _db.customSelect('SELECT * FROM $name').get();
      tables[name] = rows.map((r) => r.data).toList();
    }
    return {
      'magic': backupMagic,
      'schemaVersion': _db.schemaVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
    };
  }

  Future<BackupRestoreReport> _applyDump(
    Map<String, Object?> dump, {
    required BackupEnvelope envelope,
  }) async {
    final tables = dump['tables'] as Map<String, Object?>;
    final counts = <String, int>{};
    await _db.transaction(() async {
      // Wipe in reverse order so children go before parents.
      for (final name in _backupTableOrder.reversed) {
        await _db.customStatement('DELETE FROM $name');
      }
      // Insert in dependency order so FK references resolve.
      for (final name in _backupTableOrder) {
        final rows = (tables[name] as List<Object?>? ?? const <Object?>[])
            .cast<Map<String, Object?>>();
        for (final row in rows) {
          await _insertRow(name, row);
        }
        counts[name] = rows.length;
      }
    });
    return BackupRestoreReport(
      rowsByTable: counts,
      backupCreatedAt: envelope.createdAt,
      backupSchemaVersion: envelope.schemaVersion,
    );
  }

  Future<void> _insertRow(String table, Map<String, Object?> row) async {
    final columns = row.keys.toList();
    final placeholders = List.filled(columns.length, '?').join(', ');
    final sql =
        'INSERT OR REPLACE INTO $table '
        '(${columns.map(_quoteIdentifier).join(', ')}) '
        'VALUES ($placeholders)';
    final args = columns.map((c) => row[c]).map(_normalizeValue).toList();
    await _db.customStatement(sql, args);
  }

  static String _quoteIdentifier(String name) {
    if (!_identPattern.hasMatch(name)) {
      throw FormatException('Refusing to quote suspicious identifier: $name');
    }
    return '"$name"';
  }

  static Object? _normalizeValue(Object? value) {
    // jsonDecode hands back num for any number; SQLite is happy with
    // int, double, String, bool, Uint8List, or null. Strip any other
    // surprises so customStatement doesn't choke.
    if (value == null || value is String || value is int || value is double) {
      return value;
    }
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value.toDouble();
    throw FormatException(
      'Unsupported backup value of type ${value.runtimeType}',
    );
  }

  static final RegExp _identPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
}

class BackupRestoreReport {
  const BackupRestoreReport({
    required this.rowsByTable,
    required this.backupCreatedAt,
    required this.backupSchemaVersion,
  });

  final Map<String, int> rowsByTable;
  final DateTime backupCreatedAt;
  final int backupSchemaVersion;

  int get totalRows => rowsByTable.values.fold<int>(0, (a, b) => a + b);
}

class BackupSchemaMismatch implements Exception {
  const BackupSchemaMismatch({
    required this.backupVersion,
    required this.appVersion,
  });

  final int backupVersion;
  final int appVersion;

  @override
  String toString() =>
      'Backup is from a newer schema (v$backupVersion) than this app '
      'supports (v$appVersion). Update the app before restoring.';
}
