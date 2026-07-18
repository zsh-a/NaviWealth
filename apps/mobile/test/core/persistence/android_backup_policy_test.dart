import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android OS backup cannot separate SQLCipher bytes from the device key',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android:allowBackup="false"'));
      expect(
        manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );

      final legacy = File(
        'android/app/src/main/res/xml/backup_rules.xml',
      ).readAsStringSync();
      final modern = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync();
      expect(modern, contains('<cloud-backup>'));
      expect(modern, contains('<device-transfer>'));

      for (final domain in <String>[
        'root',
        'file',
        'database',
        'sharedpref',
        'external',
      ]) {
        final exclusion = '<exclude domain="$domain" path="." />';
        expect(legacy, contains(exclusion), reason: domain);
        expect(
          RegExp(RegExp.escape(exclusion)).allMatches(modern),
          hasLength(2),
          reason: domain,
        );
      }
    },
  );
}
