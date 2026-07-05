import 'dart:typed_data';

import 'file_saver_stub.dart'
    if (dart.library.io) 'file_saver_native.dart'
    if (dart.library.html) 'file_saver_web.dart';

/// Save backup bytes to a file and share/download it.
///
/// On desktop (macOS, Windows, Linux), opens a system Save dialog so the
/// user can pick the destination. Returns `true` if the file was saved,
/// `false` if the user cancelled.
///
/// On mobile (iOS, Android), uses the system share sheet. Always returns
/// `true`.
///
/// On web, triggers a browser download. Always returns `true`.
Future<bool> saveBackupFile(Uint8List bytes, String fileName) =>
    saveBackupFileImpl(bytes, fileName);
