import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/settings/data/backup/file_saver_native.dart';

void main() {
  test(
    'mobile backup share uses in-memory data with the requested name',
    () async {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

      final params = buildMobileBackupShareParams(
        bytes,
        'naviwealth-backup-2026-07-19.bak',
      );

      expect(params.files, hasLength(1));
      expect(await params.files!.single.readAsBytes(), bytes);
      expect(params.files!.single.mimeType, 'application/octet-stream');
      expect(params.fileNameOverrides, <String>[
        'naviwealth-backup-2026-07-19.bak',
      ]);
    },
  );
}
