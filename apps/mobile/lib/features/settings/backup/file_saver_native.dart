import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/logging/app_logger.dart';

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
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save backup',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['bak'],
    );
    logger.d('file_saver: saveFile returned path=$path');
    if (path == null) return false; // user cancelled
    await File(path).writeAsBytes(bytes);
    logger.i('file_saver: wrote ${bytes.length} bytes to $path');
    return true;
  }

  // Mobile: share sheet.
  logger.d('file_saver: mobile platform, using share sheet');
  final dir = await getTemporaryDirectory();
  // Write into the share_plus/ subdirectory so the plugin's FileProvider
  // can serve the file (its paths config only exposes cache/share_plus/).
  final shareDir = Directory('${dir.path}/share_plus');
  if (!await shareDir.exists()) {
    await shareDir.create(recursive: true);
  }
  final file = File('${shareDir.path}/$fileName');
  await file.writeAsBytes(bytes);
  logger.d('file_saver: wrote temp file ${file.path}');
  await Share.shareXFiles([XFile(file.path)]);
  return true;
}
