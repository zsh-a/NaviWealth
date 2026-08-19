/// §5.10.10 / S5c-pick + S5c-native — capture lanes.
///
/// `file_picker` (S5c-pick) + camera via `image_picker` and the shared bounded
/// reader reused by drag-drop (`desktop_drop`) and share intents.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'capture_encoder.dart';
import 'ingest_capture_policy.dart';

abstract interface class IngestCaptureFile {
  String get name;

  String? get mimeType;

  Future<int?> length();

  Stream<List<int>> openRead();
}

abstract class IngestCaptureSource {
  Future<IngestCaptureOutcome> pickFile();
}

class FilePickerCaptureSource implements IngestCaptureSource {
  const FilePickerCaptureSource();

  @override
  Future<IngestCaptureOutcome> pickFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: kIngestCaptureExtensions,
    );
    if (file == null) return const IngestCaptureCancelled();
    return platformFileToIngestSource(file);
  }
}

final ingestCaptureSourceProvider = Provider<IngestCaptureSource>(
  (ref) => const FilePickerCaptureSource(),
);

/// UI validation seam; encoding still enforces the immutable production limit.
final ingestCaptureTextLimitProvider = Provider<int>(
  (ref) => IngestCaptureLimits.textCodeUnits,
);

/// §5.10.10 / S5c-native — snap a receipt with the camera.
class CameraIngestCapture {
  const CameraIngestCapture();

  Future<IngestCaptureOutcome> capture() async {
    final shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (shot == null) return const IngestCaptureCancelled();
    return xFileToIngestSource(shot, trustedImage: true);
  }
}

final cameraIngestCaptureProvider = Provider<CameraIngestCapture>(
  (ref) => const CameraIngestCapture(),
);

Future<IngestCaptureOutcome> xFileToIngestSource(
  XFile file, {
  String? mimeType,
  bool trustedImage = false,
}) => readIngestCaptureFile(
  _XFileCaptureFile(file, mimeType: mimeType),
  trustedImage: trustedImage,
);

/// Public for platform-boundary tests, including Android SAF files without a
/// cached path. Unavailable content is returned as `unreadable`, never thrown.
Future<IngestCaptureOutcome> platformFileToIngestSource(PlatformFile file) =>
    readIngestCaptureFile(_PlatformFileCaptureFile(file));

Future<IngestCaptureOutcome> readIngestCaptureFile(
  IngestCaptureFile file, {
  bool trustedImage = false,
}) async {
  final descriptor = _resolveCapture(
    file.name,
    mimeType: file.mimeType,
    trustedImage: trustedImage,
  );
  if (descriptor == null) {
    return IngestCaptureFailure(
      IngestCaptureFailureCode.unsupported,
      fileName: file.name,
    );
  }

  final maxBytes = descriptor.kind.maxBytes;
  final int? lengthBefore;
  try {
    lengthBefore = _knownLength(await file.length());
  } on Object {
    return IngestCaptureFailure(
      IngestCaptureFailureCode.unreadable,
      fileName: file.name,
    );
  }
  if (lengthBefore != null && lengthBefore > maxBytes) {
    return _tooLarge(file.name, lengthBefore, maxBytes);
  }

  final builder = BytesBuilder(copy: false);
  var actualBytes = 0;
  try {
    await for (final chunk in file.openRead()) {
      final nextBytes = actualBytes + chunk.length;
      if (nextBytes > maxBytes) {
        return _tooLarge(file.name, nextBytes, maxBytes);
      }
      builder.add(chunk);
      actualBytes = nextBytes;
    }
  } on Object {
    return IngestCaptureFailure(
      IngestCaptureFailureCode.unreadable,
      fileName: file.name,
    );
  }

  if (actualBytes == 0) {
    return IngestCaptureFailure(
      IngestCaptureFailureCode.empty,
      fileName: file.name,
    );
  }

  final int? lengthAfter;
  try {
    lengthAfter = _knownLength(await file.length());
  } on Object {
    return IngestCaptureFailure(
      IngestCaptureFailureCode.unreadable,
      fileName: file.name,
    );
  }
  if (lengthAfter != null && lengthAfter > maxBytes) {
    return _tooLarge(file.name, lengthAfter, maxBytes);
  }
  if ((lengthBefore != null && lengthBefore != actualBytes) ||
      (lengthAfter != null && lengthAfter != actualBytes)) {
    return IngestCaptureFailure(
      IngestCaptureFailureCode.unreadable,
      fileName: file.name,
    );
  }

  return encodeIngestCapture(
    kind: descriptor.kind,
    fileName: file.name,
    bytes: builder.takeBytes(),
    mimeType: descriptor.mimeType,
  );
}

int? _knownLength(int? length) => switch (length) {
  null || <= 0 => null,
  _ => length,
};

IngestCaptureFailure _tooLarge(
  String fileName,
  int observedBytes,
  int maxBytes,
) => IngestCaptureFailure(
  IngestCaptureFailureCode.tooLarge,
  fileName: fileName,
  observedBytes: observedBytes,
  maxBytes: maxBytes,
);

final class _CaptureDescriptor {
  const _CaptureDescriptor(this.kind, this.mimeType);

  final IngestCaptureKind kind;
  final String? mimeType;
}

_CaptureDescriptor? _resolveCapture(
  String fileName, {
  required String? mimeType,
  required bool trustedImage,
}) {
  final extension = _extensionOf(fileName);
  if (extension.isNotEmpty) return _descriptorForExtension(extension);

  final normalizedMime = mimeType?.split(';').first.trim().toLowerCase();
  final fromMime = _descriptorForMime(normalizedMime);
  if (fromMime != null) return fromMime;
  if (trustedImage) {
    return const _CaptureDescriptor(
      IngestCaptureKind.receiptImage,
      'image/jpeg',
    );
  }
  return null;
}

String _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}

_CaptureDescriptor? _descriptorForExtension(String extension) =>
    switch (extension) {
      'csv' || 'txt' => const _CaptureDescriptor(
        IngestCaptureKind.statementText,
        'text/plain',
      ),
      'xlsx' => const _CaptureDescriptor(
        IngestCaptureKind.statementWorkbook,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
      'pdf' => const _CaptureDescriptor(
        IngestCaptureKind.statementPdf,
        'application/pdf',
      ),
      'jpg' || 'jpeg' => const _CaptureDescriptor(
        IngestCaptureKind.receiptImage,
        'image/jpeg',
      ),
      'png' => const _CaptureDescriptor(
        IngestCaptureKind.receiptImage,
        'image/png',
      ),
      'webp' => const _CaptureDescriptor(
        IngestCaptureKind.receiptImage,
        'image/webp',
      ),
      'heic' => const _CaptureDescriptor(
        IngestCaptureKind.receiptImage,
        'image/heic',
      ),
      'heif' => const _CaptureDescriptor(
        IngestCaptureKind.receiptImage,
        'image/heif',
      ),
      _ => null,
    };

_CaptureDescriptor? _descriptorForMime(String? mimeType) => switch (mimeType) {
  'text/csv' || 'text/plain' => const _CaptureDescriptor(
    IngestCaptureKind.statementText,
    'text/plain',
  ),
  'application/pdf' => const _CaptureDescriptor(
    IngestCaptureKind.statementPdf,
    'application/pdf',
  ),
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
    const _CaptureDescriptor(
      IngestCaptureKind.statementWorkbook,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ),
  'image/jpeg' || 'image/jpg' => const _CaptureDescriptor(
    IngestCaptureKind.receiptImage,
    'image/jpeg',
  ),
  'image/png' => const _CaptureDescriptor(
    IngestCaptureKind.receiptImage,
    'image/png',
  ),
  'image/webp' => const _CaptureDescriptor(
    IngestCaptureKind.receiptImage,
    'image/webp',
  ),
  'image/heic' => const _CaptureDescriptor(
    IngestCaptureKind.receiptImage,
    'image/heic',
  ),
  'image/heif' => const _CaptureDescriptor(
    IngestCaptureKind.receiptImage,
    'image/heif',
  ),
  _ => null,
};

final class _XFileCaptureFile implements IngestCaptureFile {
  const _XFileCaptureFile(this.file, {String? mimeType}) : _mimeType = mimeType;

  final XFile file;
  final String? _mimeType;

  @override
  String get name => file.name;

  @override
  String? get mimeType => _mimeType ?? file.mimeType;

  @override
  Future<int?> length() async => file.length();

  @override
  Stream<List<int>> openRead() => file.openRead();
}

final class _PlatformFileCaptureFile implements IngestCaptureFile {
  const _PlatformFileCaptureFile(this.file);

  final PlatformFile file;

  @override
  String get name => file.name;

  @override
  String? get mimeType => null;

  @override
  Future<int?> length() async => file.length();

  @override
  Stream<List<int>> openRead() => file.readAsByteStream();
}
