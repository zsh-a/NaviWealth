import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../security/secure_key_store.dart';
import 'database_encryption.dart';

const List<int> _sqliteHeader = <int>[
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

Future<String?> resolveDatabaseEncryptionKeyImpl({
  required SecureKeyStore store,
  required String dbFileName,
}) async {
  final file = await _databaseFile(dbFileName);
  final encryptedDatabaseExists = await _hasEncryptedDatabaseArtifact(file);
  return DatabaseEncryptionKeyManager(
    store,
  ).loadOrCreate(encryptedDatabaseExists: encryptedDatabaseExists);
}

Future<void> resetEncryptedDatabaseImpl({
  required SecureKeyStore store,
  required String dbFileName,
}) async {
  final file = await _databaseFile(dbFileName);
  await resetEncryptedDatabaseAtPath(store: store, databasePath: file.path);
}

Future<void> resetEncryptedDatabaseAtPath({
  required SecureKeyStore store,
  required String databasePath,
}) async {
  for (final path in databaseArtifactPaths(databasePath)) {
    final artifact = File(path);
    if (await artifact.exists()) await artifact.delete();
  }
  await store.delete(databaseEncryptionKeyStorageKey);
}

Future<File> _databaseFile(String dbFileName) async {
  final dir = await getApplicationDocumentsDirectory();
  return File(p.join(dir.path, dbFileName));
}

Future<bool> _hasEncryptedDatabaseArtifact(File file) async {
  for (final path in <String>[file.path, '${file.path}.encrypting']) {
    final candidate = File(path);
    if (!await candidate.exists() || await candidate.length() == 0) continue;
    if (!await hasPlaintextSqliteHeader(candidate)) return true;
  }
  return false;
}

Future<bool> hasPlaintextSqliteHeader(File file) async {
  final handle = await file.open();
  try {
    final bytes = await handle.read(_sqliteHeader.length);
    if (bytes.length != _sqliteHeader.length) return false;
    for (var index = 0; index < _sqliteHeader.length; index++) {
      if (bytes[index] != _sqliteHeader[index]) return false;
    }
    return true;
  } finally {
    await handle.close();
  }
}

List<String> databaseArtifactPaths(String databasePath) => <String>[
  databasePath,
  '$databasePath-wal',
  '$databasePath-shm',
  '$databasePath-journal',
  '$databasePath.encrypting',
  '$databasePath.encrypting-wal',
  '$databasePath.encrypting-shm',
  '$databasePath.encrypting-journal',
  '$databasePath.plaintext-backup',
  '$databasePath.plaintext-backup-wal',
  '$databasePath.plaintext-backup-shm',
  '$databasePath.plaintext-backup-journal',
];
