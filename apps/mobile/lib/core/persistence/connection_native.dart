import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database_encryption.dart';

QueryExecutor openConnectionImpl({
  required String dbFileName,
  required String? encryptionKey,
}) {
  if (encryptionKey == null ||
      !DatabaseEncryptionKeyManager.isValidKey(encryptionKey)) {
    throw const DatabaseEncryptionException(
      DatabaseEncryptionFailureCode.invalidKey,
      'A valid 256-bit key is required for the native database.',
    );
  }

  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, dbFileName));
    await Isolate.run(
      () => prepareEncryptedDatabaseFile(file.path, encryptionKey),
    );
    return encryptedNativeDatabase(file, encryptionKey);
  });
}

/// Opens one SQLCipher-backed Drift executor after migration has completed.
/// Exposed so native tests can verify real encrypted bytes without
/// `path_provider` or the application documents directory.
QueryExecutor encryptedNativeDatabase(File file, String encryptionKey) {
  if (!DatabaseEncryptionKeyManager.isValidKey(encryptionKey)) {
    throw const DatabaseEncryptionException(
      DatabaseEncryptionFailureCode.invalidKey,
      'A valid 256-bit key is required for the native database.',
    );
  }
  return NativeDatabase.createInBackground(
    file,
    setup: (database) => configureSqlCipher(database, encryptionKey),
  );
}

void configureSqlCipher(Database database, String encryptionKey) {
  final versions = database.select('PRAGMA cipher_version;');
  if (versions.isEmpty || versions.first.values.firstOrNull == null) {
    throw const DatabaseEncryptionException(
      DatabaseEncryptionFailureCode.cipherUnavailable,
      'The native SQLite library does not provide SQLCipher.',
    );
  }

  database.execute(_keyPragma(encryptionKey));
  database.execute('PRAGMA cipher_memory_security = ON;');
  try {
    database.select('SELECT count(*) FROM sqlite_master;');
  } on Object catch (error) {
    throw DatabaseEncryptionException(
      DatabaseEncryptionFailureCode.unlockFailed,
      'The local database could not be unlocked with the device key.',
      cause: error,
    );
  }
}

/// Makes a native database ready for SQLCipher.
///
/// New and already-encrypted files need no rewrite. A legacy plaintext SQLite
/// file is exported into an encrypted temporary database, validated, and then
/// swapped into place. The explicit backup/temp states let the next launch
/// finish or roll back a process interruption without discarding user data.
void prepareEncryptedDatabaseFile(String databasePath, String encryptionKey) {
  if (!DatabaseEncryptionKeyManager.isValidKey(encryptionKey)) {
    throw const DatabaseEncryptionException(
      DatabaseEncryptionFailureCode.invalidKey,
      'A valid 256-bit key is required for the native database.',
    );
  }

  final database = File(databasePath);
  final encryptedTemp = File('$databasePath.encrypting');
  final plaintextBackup = File('$databasePath.plaintext-backup');

  try {
    _recoverInterruptedMigration(
      database: database,
      encryptedTemp: encryptedTemp,
      plaintextBackup: plaintextBackup,
      encryptionKey: encryptionKey,
    );

    if (!database.existsSync() || database.lengthSync() == 0) return;

    if (!_hasPlaintextHeaderSync(database)) {
      _validateEncryptedFile(database, encryptionKey);
      _deleteIfExists(encryptedTemp);
      _deleteIfExists(plaintextBackup);
      return;
    }

    _migratePlaintextDatabase(
      database: database,
      encryptedTemp: encryptedTemp,
      plaintextBackup: plaintextBackup,
      encryptionKey: encryptionKey,
    );
  } on DatabaseEncryptionException {
    rethrow;
  } on Object catch (error) {
    throw DatabaseEncryptionException(
      DatabaseEncryptionFailureCode.migrationFailed,
      'The plaintext database could not be migrated safely.',
      cause: error,
    );
  }
}

void _recoverInterruptedMigration({
  required File database,
  required File encryptedTemp,
  required File plaintextBackup,
  required String encryptionKey,
}) {
  if (database.existsSync()) return;

  if (encryptedTemp.existsSync()) {
    try {
      _validateEncryptedFile(encryptedTemp, encryptionKey);
      encryptedTemp.renameSync(database.path);
      _validateEncryptedFile(database, encryptionKey);
      _deleteIfExists(plaintextBackup);
      return;
    } on Object {
      if (!plaintextBackup.existsSync()) rethrow;
      _deleteIfExists(encryptedTemp);
    }
  }

  if (plaintextBackup.existsSync()) {
    plaintextBackup.renameSync(database.path);
  }
}

void _migratePlaintextDatabase({
  required File database,
  required File encryptedTemp,
  required File plaintextBackup,
  required String encryptionKey,
}) {
  _deleteIfExists(encryptedTemp);
  _deleteDatabaseSidecars(encryptedTemp.path);

  final source = sqlite3.open(database.path);
  try {
    _requireSqlCipher(source);
    source.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    final userVersion =
        source.select('PRAGMA user_version;').first.columnAt(0) as int;
    source.execute(
      'ATTACH DATABASE ${_sqlString(encryptedTemp.path)} '
      'AS encrypted KEY "x\'$encryptionKey\'";',
    );
    try {
      source.select("SELECT sqlcipher_export('encrypted');");
      source.execute('PRAGMA encrypted.user_version = $userVersion;');
    } finally {
      source.execute('DETACH DATABASE encrypted;');
    }
  } finally {
    source.close();
  }

  _validateEncryptedFile(encryptedTemp, encryptionKey);
  _deleteIfExists(plaintextBackup);
  database.renameSync(plaintextBackup.path);
  _deleteDatabaseSidecars(database.path);

  try {
    encryptedTemp.renameSync(database.path);
    _validateEncryptedFile(database, encryptionKey);
    _deleteIfExists(plaintextBackup);
  } on Object {
    // The promoted file was already validated before the rename, but a second
    // validation can still fail because of an I/O error. Restore the known
    // plaintext backup instead of leaving a database that cannot be opened.
    if (database.existsSync()) _deleteIfExists(database);
    if (plaintextBackup.existsSync()) {
      plaintextBackup.renameSync(database.path);
    }
    rethrow;
  }
}

void _validateEncryptedFile(File file, String encryptionKey) {
  final database = sqlite3.open(file.path);
  try {
    configureSqlCipher(database, encryptionKey);
  } finally {
    database.close();
  }
}

void _requireSqlCipher(Database database) {
  final versions = database.select('PRAGMA cipher_version;');
  if (versions.isEmpty || versions.first.values.firstOrNull == null) {
    throw const DatabaseEncryptionException(
      DatabaseEncryptionFailureCode.cipherUnavailable,
      'The native SQLite library does not provide SQLCipher.',
    );
  }
}

bool _hasPlaintextHeaderSync(File file) {
  final handle = file.openSync();
  try {
    final bytes = handle.readSync(16);
    const header = <int>[
      0x53,
      0x51,
      0x4c,
      0x69,
      0x74,
      0x65,
      0x20,
      0x66,
      0x6f,
      0x72,
      0x6d,
      0x61,
      0x74,
      0x20,
      0x33,
      0x00,
    ];
    if (bytes.length != header.length) return false;
    for (var index = 0; index < header.length; index++) {
      if (bytes[index] != header[index]) return false;
    }
    return true;
  } finally {
    handle.closeSync();
  }
}

String _keyPragma(String encryptionKey) =>
    'PRAGMA key = "x\'$encryptionKey\'";';

String _sqlString(String value) => "'${value.replaceAll("'", "''")}'";

void _deleteDatabaseSidecars(String databasePath) {
  for (final suffix in <String>['-wal', '-shm', '-journal']) {
    _deleteIfExists(File('$databasePath$suffix'));
  }
}

void _deleteIfExists(File file) {
  if (file.existsSync()) file.deleteSync();
}
