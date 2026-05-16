/// §5.10.10 / S5b — the privacy gate (隐私门).
///
/// Device-parsable input (CSV / pasted text) is processed entirely
/// on-device and is never gated. Image / PDF / email input *requires*
/// cloud Vision (§5.10.10 ②③); whether that is permitted is the user's
/// §5.10.5 privacy posture decision, **not** the pipeline's:
///
///   * `amountsLocal` ("金额完全本地") → cloud Vision is off. The most
///     sensitive raw artefact (a receipt image) must never leave the
///     device, so non-device sources are blocked outright.
///   * `amountsAllowed` / `amountsBucketed` → cloud Vision is allowed
///     (the backend route lands in S5b-vision).
///
/// Pure decision function — no I/O, no strings — so it is exhaustively
/// unit-testable. The caller maps the verdict to a user message.
library;

import '../../../core/ai/contracts/privacy_mode_provider.dart';
import '../domain/ingest_models.dart';

enum IngestGateVerdict {
  /// Handle entirely on-device (deterministic parser). Privacy-neutral.
  deviceParse,

  /// Needs cloud Vision and the privacy posture permits it.
  cloudAllowed,

  /// Needs cloud Vision but the user pinned amounts/data to the device.
  blockedByPrivacy,
}

IngestGateVerdict ingestPrivacyGate(
  IngestSourceKind kind,
  AiPrivacyMode mode,
) {
  if (kind.isDeviceParsable) return IngestGateVerdict.deviceParse;
  return mode == AiPrivacyMode.amountsLocal
      ? IngestGateVerdict.blockedByPrivacy
      : IngestGateVerdict.cloudAllowed;
}
