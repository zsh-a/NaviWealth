/// §5.10.10 / S5c-pick + S5c-native — capture lanes.
///
/// `file_picker` (S5c-pick) + camera via `image_picker` and the shared
/// [xFileToIngestSource] reused by drag-drop (`desktop_drop`) and the
/// share receiver (`receive_sharing_intent`). All lanes funnel through
/// the one pure [ingestSourceFromCapture] encoder.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/ingest_models.dart';
import 'capture_encoder.dart';

/// Read an [XFile] (camera / dropped / shared) into an [IngestSource].
/// Camera files sometimes lack an extension in their `name`; default
/// such cases to `.jpg` so the encoder routes them as a receipt image.
Future<IngestSource?> xFileToIngestSource(XFile file) async {
  final bytes = await file.readAsBytes();
  var name = file.name;
  if (!name.contains('.')) name = '$name.jpg';
  return ingestSourceFromCapture(fileName: name, bytes: bytes);
}

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

/// §5.10.10 / S5c-native — snap a receipt with the camera.
class CameraIngestCapture {
  const CameraIngestCapture();

  Future<IngestSource?> capture() async {
    final shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (shot == null) return null;
    return xFileToIngestSource(shot);
  }
}

final cameraIngestCaptureProvider = Provider<CameraIngestCapture>(
  (ref) => const CameraIngestCapture(),
);
