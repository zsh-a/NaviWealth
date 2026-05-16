import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/privacy_mode_provider.dart';
import 'package:naviwealth/features/ingest/data/ingest_privacy_gate.dart';
import 'package:naviwealth/features/ingest/domain/ingest_models.dart';

void main() {
  group('ingestPrivacyGate', () {
    test('device-parsable kinds are never gated, in any privacy mode', () {
      for (final kind in const [
        IngestSourceKind.csv,
        IngestSourceKind.pasteText,
      ]) {
        for (final mode in AiPrivacyMode.values) {
          expect(
            ingestPrivacyGate(kind, mode),
            IngestGateVerdict.deviceParse,
            reason: '$kind / $mode',
          );
        }
      }
    });

    test('cloud kinds are blocked only when amounts are fully local', () {
      for (final kind in const [
        IngestSourceKind.receiptImage,
        IngestSourceKind.statementPdf,
        IngestSourceKind.email,
      ]) {
        expect(
          ingestPrivacyGate(kind, AiPrivacyMode.amountsLocal),
          IngestGateVerdict.blockedByPrivacy,
          reason: '$kind blocked under amountsLocal',
        );
        expect(
          ingestPrivacyGate(kind, AiPrivacyMode.amountsAllowed),
          IngestGateVerdict.cloudAllowed,
        );
        expect(
          ingestPrivacyGate(kind, AiPrivacyMode.amountsBucketed),
          IngestGateVerdict.cloudAllowed,
        );
      }
    });

    test('every kind × mode pair yields a verdict (no gaps)', () {
      for (final kind in IngestSourceKind.values) {
        for (final mode in AiPrivacyMode.values) {
          expect(ingestPrivacyGate(kind, mode), isA<IngestGateVerdict>());
        }
      }
    });
  });
}
