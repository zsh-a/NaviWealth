/// §5.10.10 / S5c-pick — turn a captured file into an [IngestSource].
///
/// Pure: the file extension picks the lane. Text (CSV / TXT) rides the
/// device parser as a UTF-8 payload; binary (image / PDF) rides the
/// S5b-vision cloud path as a base64 payload + mime. Anything else is
/// rejected here so the caller can say so instead of the pipeline
/// failing opaquely later.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../domain/ingest_models.dart';

/// Extensions accepted by the file picker / drop target.
const List<String> kIngestCaptureExtensions = <String>[
  'csv',
  'txt',
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'heif',
];

String _extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}

/// Map a captured file → [IngestSource]. Returns null for an
/// unsupported extension or absent bytes (caller surfaces a message).
IngestSource? ingestSourceFromCapture({
  required String fileName,
  required Uint8List? bytes,
}) {
  if (bytes == null || bytes.isEmpty) return null;
  final ext = _extensionOf(fileName);
  final label = fileName.isEmpty ? 'file' : fileName;

  switch (ext) {
    case 'csv':
    case 'txt':
      return IngestSource(
        kind: IngestSourceKind.csv,
        payload: utf8.decode(bytes, allowMalformed: true),
        originLabel: label,
      );
    case 'pdf':
      return IngestSource(
        kind: IngestSourceKind.statementPdf,
        payload: base64Encode(bytes),
        mime: 'application/pdf',
        originLabel: label,
      );
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'webp':
    case 'heic':
    case 'heif':
      return IngestSource(
        kind: IngestSourceKind.receiptImage,
        payload: base64Encode(bytes),
        mime: _imageMime(ext),
        originLabel: label,
      );
    default:
      return null;
  }
}

String _imageMime(String ext) => switch (ext) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  'webp' => 'image/webp',
  'heic' => 'image/heic',
  'heif' => 'image/heif',
  _ => 'application/octet-stream',
};
