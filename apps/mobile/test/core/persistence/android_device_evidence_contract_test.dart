import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android runner fails closed when database evidence is incomplete', () {
    final runner = File('tool/run-android-integration.sh').readAsStringSync();
    final databaseTest = File(
      'integration_test/database_boot_integration_test.dart',
    ).readAsStringSync();
    final backupTest = File(
      'integration_test/backup_restore_integration_test.dart',
    ).readAsStringSync();

    const databaseMarkers = <String>[
      'database-encryption: sqlcipher available',
      'database-encryption: encrypted header verified',
      'database-encryption: correct key reopen verified',
      'database-encryption: wrong key rejected',
      'database-encryption: plaintext migration verified',
      'database-encryption: android keystore key persisted',
      'database-encryption: missing keystore key failed closed',
      'database-encryption: restored keystore key reopened',
    ];
    const backupMarkers = <String>[
      'backup: encrypted restore completed on file database',
      'backup: failed restore rollback persisted after reopen',
    ];

    for (final marker in databaseMarkers) {
      expect(databaseTest, contains(marker), reason: marker);
      expect(runner, contains("'$marker'"), reason: marker);
    }
    for (final marker in backupMarkers) {
      expect(backupTest, contains(marker), reason: marker);
      expect(runner, contains("'$marker'"), reason: marker);
    }

    expect(runner, contains('set -euo pipefail'));
    expect(runner, contains(r'grep -Fq "$marker"'));
  });
}
