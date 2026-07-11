import '../../../../l10n/gen/app_localizations.dart';
import '../data/ingest_capture_feedback.dart';
import '../data/ingest_capture_policy.dart';

String localizedIngestCaptureFeedback(
  AppLocalizations l10n,
  IngestCaptureFeedbackEvent event,
) => switch (event.feedback) {
  IngestCaptureFailureFeedback(:final failure) => localizedIngestCaptureFailure(
    l10n,
    failure,
  ),
  IngestProcessingFailureFeedback(:final code) => switch (code) {
    IngestProcessingFailureCode.rejected => l10n.ingestSharedParseRejected,
    IngestProcessingFailureCode.failed => l10n.ingestSharedParseFailed,
  },
};

String localizedIngestCaptureFailure(
  AppLocalizations l10n,
  IngestCaptureFailure failure,
) => switch (failure.code) {
  IngestCaptureFailureCode.unsupported => l10n.ingestCaptureUnsupported,
  IngestCaptureFailureCode.empty => l10n.ingestCaptureEmpty,
  IngestCaptureFailureCode.tooLarge => l10n.ingestCaptureTooLarge(
    _mebibytes(failure.maxBytes),
  ),
  IngestCaptureFailureCode.textTooLong => l10n.ingestCaptureTextTooLong(
    IngestCaptureLimits.textCodeUnits,
  ),
  IngestCaptureFailureCode.unreadable => l10n.ingestCaptureUnreadable,
};

int _mebibytes(int? bytes) => (bytes ?? 0) ~/ (1024 * 1024);
