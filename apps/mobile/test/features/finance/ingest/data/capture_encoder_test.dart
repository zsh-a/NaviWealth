import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' as charset;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/data/capture_encoder.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_capture_policy.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

IngestSource _source(IngestCaptureOutcome outcome) => switch (outcome) {
  IngestCaptureSuccess(:final source) => source,
  _ => throw TestFailure('Expected capture success, got $outcome'),
};

void main() {
  group('encodeIngestCapture', () {
    test('encodes UTF-8 statement text without a mime', () {
      final source = _source(
        encodeIngestCapture(
          kind: IngestCaptureKind.statementText,
          fileName: 'May.CSV',
          bytes: _bytes('date,desc,amount\n2026-05-10,Coffee,-38'),
        ),
      );

      expect(source.kind, IngestSourceKind.csv);
      expect(source.mime, isNull);
      expect(source.payload, contains('Coffee'));
      expect(source.originLabel, 'May.CSV');
    });

    test('falls back to GBK for Alipay exports', () {
      final source = _source(
        encodeIngestCapture(
          kind: IngestCaptureKind.statementText,
          fileName: '支付宝交易明细.csv',
          bytes: Uint8List.fromList(
            charset.gbk.encode(
              '交易时间,交易分类,交易对方,商品说明,收/支,金额,交易状态\n'
              '2026-05-30 18:50:44,餐饮美食,麦当劳,食品,支出,31.50,交易成功\n',
            ),
          ),
        ),
      );

      expect(source.payload, contains('交易时间'));
      expect(source.payload, contains('麦当劳'));
      expect(source.payload, contains('支出'));
    });

    test('encodes PDF and image bytes only after the boundary', () {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final pdf = _source(
        encodeIngestCapture(
          kind: IngestCaptureKind.statementPdf,
          fileName: 'statement.pdf',
          bytes: bytes,
        ),
      );
      final image = _source(
        encodeIngestCapture(
          kind: IngestCaptureKind.receiptImage,
          fileName: 'receipt.webp',
          bytes: bytes,
          mimeType: 'image/webp',
        ),
      );

      expect(pdf.kind, IngestSourceKind.statementPdf);
      expect(pdf.mime, 'application/pdf');
      expect(pdf.payload, base64Encode(bytes));
      expect(image.kind, IngestSourceKind.receiptImage);
      expect(image.mime, 'image/webp');
      expect(image.payload, base64Encode(bytes));
    });

    test('rejects empty and oversized bytes without encoding', () {
      final empty = encodeIngestCapture(
        kind: IngestCaptureKind.receiptImage,
        fileName: 'empty.jpg',
        bytes: Uint8List(0),
      );
      final tooLarge = encodeIngestCapture(
        kind: IngestCaptureKind.receiptImage,
        fileName: 'large.jpg',
        bytes: Uint8List(IngestCaptureLimits.receiptImageBytes + 1),
      );

      expect(
        (empty as IngestCaptureFailure).code,
        IngestCaptureFailureCode.empty,
      );
      expect(
        (tooLarge as IngestCaptureFailure).code,
        IngestCaptureFailureCode.tooLarge,
      );
    });

    test('rejects decoded text above the code-unit budget', () {
      final outcome = encodeIngestCapture(
        kind: IngestCaptureKind.statementText,
        fileName: 'long.csv',
        bytes: Uint8List(IngestCaptureLimits.textCodeUnits + 1),
      );

      expect(
        (outcome as IngestCaptureFailure).code,
        IngestCaptureFailureCode.textTooLong,
      );
    });
  });

  group('ingestSourceFromTextCapture', () {
    test('checks the raw length before trimming', () {
      final outcome = ingestSourceFromTextCapture(
        text: ' ${''.padRight(IngestCaptureLimits.textCodeUnits, 'a')}',
        originLabel: 'paste',
      );

      expect(
        (outcome as IngestCaptureFailure).code,
        IngestCaptureFailureCode.textTooLong,
      );
    });

    test('rejects blank text and trims a successful payload', () {
      final blank = ingestSourceFromTextCapture(
        text: '  \n ',
        originLabel: 'paste',
      );
      final success = _source(
        ingestSourceFromTextCapture(
          text: '  statement row  ',
          originLabel: 'paste',
        ),
      );

      expect(
        (blank as IngestCaptureFailure).code,
        IngestCaptureFailureCode.empty,
      );
      expect(success.payload, 'statement row');
      expect(success.kind, IngestSourceKind.pasteText);
    });
  });
}
