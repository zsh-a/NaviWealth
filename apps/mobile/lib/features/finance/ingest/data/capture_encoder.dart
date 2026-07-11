/// §5.10.10 / S5c-pick — turn a captured file into an [IngestSource].
///
/// Pure: already-bounded bytes become an [IngestSource]. Text (CSV / TXT)
/// rides the device parser; binary (image / PDF) rides the provider-Vision
/// path as a base64 payload + mime.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' as charset;

import '../domain/ingest_models.dart';
import 'ingest_capture_policy.dart';

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

/// Encode bytes only after the capture reader has enforced its memory budget.
/// The checks here are intentionally repeated as a defense-in-depth boundary.
IngestCaptureOutcome encodeIngestCapture({
  required IngestCaptureKind kind,
  required String fileName,
  required Uint8List bytes,
  String? mimeType,
}) {
  final label = fileName.isEmpty ? 'file' : fileName;
  if (bytes.isEmpty) {
    return IngestCaptureFailure(
      IngestCaptureFailureCode.empty,
      fileName: label,
    );
  }
  if (bytes.lengthInBytes > kind.maxBytes) {
    return IngestCaptureFailure(
      IngestCaptureFailureCode.tooLarge,
      fileName: label,
      observedBytes: bytes.lengthInBytes,
      maxBytes: kind.maxBytes,
    );
  }

  try {
    return switch (kind) {
      IngestCaptureKind.statementText => _encodeStatementText(bytes, label),
      IngestCaptureKind.receiptImage => IngestCaptureSuccess(
        IngestSource(
          kind: IngestSourceKind.receiptImage,
          payload: base64Encode(bytes),
          mime: mimeType ?? 'image/jpeg',
          originLabel: label,
        ),
      ),
      IngestCaptureKind.statementPdf => IngestCaptureSuccess(
        IngestSource(
          kind: IngestSourceKind.statementPdf,
          payload: base64Encode(bytes),
          mime: 'application/pdf',
          originLabel: label,
        ),
      ),
    };
  } on Object {
    return IngestCaptureFailure(
      IngestCaptureFailureCode.unreadable,
      fileName: label,
    );
  }
}

/// Bound direct text lanes (paste and shared text) before trimming or keeping a
/// second copy of an oversized payload.
IngestCaptureOutcome ingestSourceFromTextCapture({
  required String text,
  required String originLabel,
}) {
  if (text.length > IngestCaptureLimits.textCodeUnits) {
    return IngestCaptureFailure(
      IngestCaptureFailureCode.textTooLong,
      fileName: originLabel,
      observedBytes: text.length,
      maxBytes: IngestCaptureLimits.textCodeUnits,
    );
  }
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return IngestCaptureFailure(
      IngestCaptureFailureCode.empty,
      fileName: originLabel,
    );
  }
  return IngestCaptureSuccess(
    IngestSource(
      kind: IngestSourceKind.pasteText,
      payload: trimmed,
      originLabel: originLabel,
    ),
  );
}

IngestCaptureOutcome _encodeStatementText(Uint8List bytes, String label) {
  final text = _decodeStatementText(bytes);
  if (text.length > IngestCaptureLimits.textCodeUnits) {
    return IngestCaptureFailure(
      IngestCaptureFailureCode.textTooLong,
      fileName: label,
      observedBytes: text.length,
      maxBytes: IngestCaptureLimits.textCodeUnits,
    );
  }
  if (text.trim().isEmpty) {
    return IngestCaptureFailure(
      IngestCaptureFailureCode.empty,
      fileName: label,
    );
  }
  return IngestCaptureSuccess(
    IngestSource(kind: IngestSourceKind.csv, payload: text, originLabel: label),
  );
}

String _decodeStatementText(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return charset.gbk.decode(bytes, allowMalformed: true);
  }
}
