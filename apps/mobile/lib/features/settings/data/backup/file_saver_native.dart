import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:share_plus/share_plus.dart';

/// Save backup bytes to a file.
///
/// On desktop (macOS, Windows, Linux), opens a system Save dialog so the
/// user can pick the destination. Returns `true` if the file was saved,
/// `false` if the user cancelled.
///
/// On mobile (iOS, Android), uses the system share sheet since there is
/// no standard "Save As" dialog. Always returns `true`.
Future<bool> saveBackupFileImpl(Uint8List bytes, String fileName) async {
  final logger = AppLogger.instance;

  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    logger.d('file_saver: desktop platform, opening save dialog');
    // file_picker 12: `saveFile` now requires `bytes` and writes them itself
    // (see FilePickerUtils.saveBytesToFile in the platform impls); no manual
    // writeAsBytes follow-up.
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save backup',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['bak'],
      bytes: bytes,
    );
    logger.d('file_saver: saveFile returned path=$path');
    if (path == null) return false; // user cancelled
    logger.i('file_saver: wrote ${bytes.length} bytes to $path');
    return true;
  }

  // Mobile: share sheet. Let share_plus materialize the in-memory file in its
  // own cache. On Android the plugin rejects source files already located in
  // cache/share_plus because it clears that directory before every share.
  logger.d('file_saver: mobile platform, using share sheet');
  await SharePlus.instance.share(buildMobileBackupShareParams(bytes, fileName));
  return true;
}

@visibleForTesting
ShareParams buildMobileBackupShareParams(Uint8List bytes, String fileName) {
  return ShareParams(
    files: <XFile>[XFile.fromData(bytes, mimeType: 'application/octet-stream')],
    fileNameOverrides: <String>[fileName],
  );
}
