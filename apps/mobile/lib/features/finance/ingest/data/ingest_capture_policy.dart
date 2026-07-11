import '../domain/ingest_models.dart';

const int _bytesPerMebibyte = 1024 * 1024;

abstract final class IngestCaptureLimits {
  static const int statementTextBytes = 4 * _bytesPerMebibyte;
  static const int receiptImageBytes = 8 * _bytesPerMebibyte;
  static const int statementPdfBytes = 12 * _bytesPerMebibyte;
  static const int textCodeUnits = 4_000_000;
}

enum IngestCaptureKind { statementText, receiptImage, statementPdf }

extension IngestCaptureKindPolicy on IngestCaptureKind {
  int get maxBytes => switch (this) {
    IngestCaptureKind.statementText => IngestCaptureLimits.statementTextBytes,
    IngestCaptureKind.receiptImage => IngestCaptureLimits.receiptImageBytes,
    IngestCaptureKind.statementPdf => IngestCaptureLimits.statementPdfBytes,
  };
}

enum IngestCaptureFailureCode {
  unsupported,
  empty,
  tooLarge,
  textTooLong,
  unreadable,
}

sealed class IngestCaptureOutcome {
  const IngestCaptureOutcome();
}

final class IngestCaptureSuccess extends IngestCaptureOutcome {
  const IngestCaptureSuccess(this.source);

  final IngestSource source;
}

final class IngestCaptureCancelled extends IngestCaptureOutcome {
  const IngestCaptureCancelled();
}

final class IngestCaptureFailure extends IngestCaptureOutcome {
  const IngestCaptureFailure(
    this.code, {
    this.fileName,
    this.observedBytes,
    this.maxBytes,
  });

  final IngestCaptureFailureCode code;
  final String? fileName;
  final int? observedBytes;
  final int? maxBytes;
}
