import 'dart:developer' as dev;
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
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
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    dev.log('saveBackupFileImpl: desktop platform detected');
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save backup',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['bak'],
    );
    dev.log('saveBackupFileImpl: saveFile returned path=$path');
    if (path == null) return false; // user cancelled
    await File(path).writeAsBytes(bytes);
    dev.log('saveBackupFileImpl: wrote ${bytes.length} bytes to $path');
    return true;
  }

  // Mobile: share sheet.
  dev.log('saveBackupFileImpl: mobile platform, using share sheet');
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes);
  dev.log('saveBackupFileImpl: wrote temp file ${file.path}');
  await Share.shareXFiles([XFile(file.path)]);
  return true;
}
