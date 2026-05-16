/// §5.10.10 / S5c-pick — file capture via the existing `file_picker`.
///
/// One verifiable capture lane that works on every platform (mobile /
/// desktop / web) with no new dependency. Camera (`image_picker`) and
/// drag-and-drop (`desktop_drop`) + the iOS Share Extension / Android
/// Intent receiver are S5c-native (separate, need device/IDE).
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ingest_models.dart';
import 'capture_encoder.dart';

abstract class IngestCaptureSource {
  /// Opens the platform picker. Returns null when the user cancels or
  /// the chosen file's type is unsupported.
  Future<IngestSource?> pickFile();
}

class FilePickerCaptureSource implements IngestCaptureSource {
  const FilePickerCaptureSource();

  @override
  Future<IngestSource?> pickFile() async {
    final result = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: kIngestCaptureExtensions,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    return ingestSourceFromCapture(fileName: file.name, bytes: file.bytes);
  }
}

final ingestCaptureSourceProvider = Provider<IngestCaptureSource>(
  (ref) => const FilePickerCaptureSource(),
);
