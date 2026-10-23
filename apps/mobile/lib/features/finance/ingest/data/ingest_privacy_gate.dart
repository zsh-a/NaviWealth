/// CSV and pasted text stay on device. Raw images, PDFs and emails require
/// explicit permission before they can be sent to the configured provider.
library;

import '../domain/ingest_models.dart';

enum IngestGateVerdict { deviceParse, providerVisionAllowed, blockedByPrivacy }

IngestGateVerdict ingestPrivacyGate(
  IngestSourceKind kind, {
  required bool allowDocumentRecognition,
}) {
  if (kind.isDeviceParsable) return IngestGateVerdict.deviceParse;
  return allowDocumentRecognition
      ? IngestGateVerdict.providerVisionAllowed
      : IngestGateVerdict.blockedByPrivacy;
}
