import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_privacy_gate.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';

void main() {
  test('CSV and pasted text stay local with either document permission', () {
    for (final kind in [IngestSourceKind.csv, IngestSourceKind.pasteText]) {
      for (final allowed in [false, true]) {
        expect(
          ingestPrivacyGate(kind, allowDocumentRecognition: allowed),
          IngestGateVerdict.deviceParse,
          reason: '$kind with document permission $allowed',
        );
      }
    }
  });

  test('all provider document kinds require explicit permission', () {
    for (final kind in [
      IngestSourceKind.receiptImage,
      IngestSourceKind.statementPdf,
      IngestSourceKind.email,
    ]) {
      expect(
        ingestPrivacyGate(kind, allowDocumentRecognition: false),
        IngestGateVerdict.blockedByPrivacy,
        reason: '$kind must not reach the provider by default',
      );
      expect(
        ingestPrivacyGate(kind, allowDocumentRecognition: true),
        IngestGateVerdict.providerVisionAllowed,
      );
    }
  });
}
