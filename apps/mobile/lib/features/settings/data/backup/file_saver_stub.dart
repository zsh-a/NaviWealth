import 'dart:typed_data';

Future<bool> saveBackupFileImpl(Uint8List bytes, String fileName) {
  throw UnsupportedError('No platform file saver available for current target');
}
