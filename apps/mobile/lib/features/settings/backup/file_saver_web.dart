// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

import '../../../core/logging/app_logger.dart';

Future<bool> saveBackupFileImpl(Uint8List bytes, String fileName) async {
  AppLogger.instance.d('file_saver: web download triggered — '
      '$fileName (${bytes.length} bytes)');
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  // Defer revocation so the browser has time to start the download.
  // Immediate revocation causes silent failures in Firefox/Safari.
  Future<void>.delayed(const Duration(seconds: 1), () {
    html.Url.revokeObjectUrl(url);
  });
  return true;
}
