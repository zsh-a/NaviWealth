import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:charset/charset.dart' as charset;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/data/capture_encoder.dart';
import 'package:naviwealth/features/finance/ingest/data/ingest_capture_policy.dart';
import 'package:naviwealth/features/finance/ingest/data/statement_ingest_parser.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

Uint8List _xlsxBytes() {
  const strings = <String>[
    '微信支付账单明细',
    '交易时间',
    '交易类型',
    '交易对方',
    '商品',
    '收/支',
    '金额(元)',
    '支付方式',
    '当前状态',
    '示例餐厅',
    '午餐',
    '支出',
    '31.50',
    '零钱',
    '支付成功',
    '商户消费',
    '2026-07-16 12:00:00',
  ];
  final shared =
      '<sst xmlns="http://schemas.openxmlformats.org/'
      'spreadsheetml/2006/main">${strings.map((value) => '<si><t>$value</t></si>').join()}</sst>';
  const sheet =
      '<worksheet xmlns="http://schemas.openxmlformats.org/'
      'spreadsheetml/2006/main"><sheetData>'
      '<row r="1"><c r="A1" t="s"><v>0</v></c></row>'
      '<row r="16">'
      '<c r="A16" t="s"><v>1</v></c><c r="B16" t="s"><v>2</v></c>'
      '<c r="C16" t="s"><v>3</v></c><c r="D16" t="s"><v>4</v></c>'
      '<c r="E16" t="s"><v>5</v></c><c r="F16" t="s"><v>6</v></c>'
      '<c r="G16" t="s"><v>7</v></c><c r="H16" t="s"><v>8</v></c>'
      '</row><row r="17">'
      '<c r="A17" t="s"><v>16</v></c><c r="B17" t="s"><v>15</v></c>'
      '<c r="C17" t="s"><v>9</v></c><c r="D17" t="s"><v>10</v></c>'
      '<c r="E17" t="s"><v>11</v></c><c r="F17" t="s"><v>12</v></c>'
      '<c r="G17" t="s"><v>13</v></c><c r="H17" t="s"><v>14</v></c>'
      '</row></sheetData></worksheet>';
  final archive = Archive()
    ..addFile(ArchiveFile.string('xl/sharedStrings.xml', shared))
    ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', sheet));
  return ZipEncoder().encodeBytes(archive);
}

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
              '支付宝支付科技有限公司 电子客户回单\n'
              '交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,'
              '收/付款方式,交易状态,交易订单号,商家订单号,备注,\n'
              '2026-05-30 18:50:44,餐饮美食,示例餐厅,merchant@example.com,'
              '食品,支出,31.50,余额,交易成功,trade-1,order-1,,\n',
            ),
          ),
        ),
      );

      expect(source.payload, contains('交易时间'));
      expect(source.payload, contains('示例餐厅'));
      expect(source.payload, contains('支出'));
      expect(detectStatementProvider(source.payload), StatementProvider.alipay);
      final rows = parseStatementLedger(source.payload);
      expect(rows, hasLength(1));
      expect(rows.single.amountMinor, -3150);
      expect(rows.single.categoryHint, 'dining');
    });

    test('decodes an XLSX statement into deterministic CSV', () {
      final source = _source(
        encodeIngestCapture(
          kind: IngestCaptureKind.statementWorkbook,
          fileName: '微信支付账单.xlsx',
          bytes: _xlsxBytes(),
        ),
      );

      expect(source.kind, IngestSourceKind.csv);
      expect(source.payload, contains('微信支付账单明细'));
      expect(
        detectStatementProvider(source.payload),
        StatementProvider.wechatPay,
      );
      final rows = parseStatementLedger(source.payload);
      expect(rows, hasLength(1));
      expect(rows.single.description, contains('示例餐厅'));
      expect(rows.single.amountMinor, -3150);
    });

    test('rejects malformed XLSX bytes as unreadable', () {
      final outcome = encodeIngestCapture(
        kind: IngestCaptureKind.statementWorkbook,
        fileName: 'broken.xlsx',
        bytes: _bytes('not a zip'),
      );

      expect(
        (outcome as IngestCaptureFailure).code,
        IngestCaptureFailureCode.unreadable,
      );
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
