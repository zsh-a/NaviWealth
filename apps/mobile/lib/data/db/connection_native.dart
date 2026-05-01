import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

QueryExecutor openConnectionImpl({
  required String dbFileName,
  required String encryptionKey,
}) {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, dbFileName));
    return NativeDatabase.createInBackground(
      file,
      setup: (raw) {
        raw.execute("PRAGMA key = \"x'$encryptionKey'\";");
        raw.execute('PRAGMA cipher_memory_security = ON;');
        final result = raw.select('PRAGMA cipher_version;');
        if (result.isEmpty || result.first.values.first == null) {
          throw StateError(
            'SQLCipher not available — got no cipher_version. '
            'Ensure SQLite3MultipleCiphers is configured in pubspec.yaml.',
          );
        }
      },
    );
  });
}
