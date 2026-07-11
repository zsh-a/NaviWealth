import '../../../../l10n/gen/app_localizations.dart';
import '../data/ingest_capture_policy.dart';

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
