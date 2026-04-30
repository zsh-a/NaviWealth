import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

bool _sqlCipherConfigured = false;

void _configureSqlCipherDynamicLibrary() {
  if (_sqlCipherConfigured) return;
  if (Platform.isAndroid) {
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
  } else if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlcipher.so'),
    );
  } else if (Platform.isWindows) {
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open('sqlcipher.dll'),
    );
  }
  // iOS and macOS link SQLCipher statically; no override needed.
  _sqlCipherConfigured = true;
}

QueryExecutor openConnectionImpl({
  required String dbFileName,
  required String encryptionKey,
}) {
  return LazyDatabase(() async {
    _configureSqlCipherDynamicLibrary();
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, dbFileName));
    return NativeDatabase.createInBackground(
      file,
      isolateSetup: _configureSqlCipherDynamicLibrary,
      setup: (raw) {
        raw.execute("PRAGMA key = \"x'$encryptionKey'\";");
        raw.execute('PRAGMA cipher_memory_security = ON;');
        final result = raw.select('PRAGMA cipher_version;');
        if (result.isEmpty || result.first.values.first == null) {
          throw StateError(
            'SQLCipher not available — got no cipher_version. '
            'Ensure sqlcipher_flutter_libs native libraries are linked.',
          );
        }
      },
    );
  });
}
