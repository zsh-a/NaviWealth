import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' as charset;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ingest/data/capture_encoder.dart';
import 'package:naviwealth/features/ingest/domain/ingest_models.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('ingestSourceFromCapture', () {
    test('csv / txt → device text lane (utf8 payload, no mime)', () {
      final csv = ingestSourceFromCapture(
        fileName: 'May.CSV',
        bytes: _b('date,desc,amount\n2026-05-10,Coffee,-38'),
      );
      expect(csv, isNotNull);
      expect(csv!.kind, IngestSourceKind.csv);
      expect(csv.mime, isNull);
      expect(csv.payload, contains('Coffee'));
      expect(csv.originLabel, 'May.CSV');

      final txt = ingestSourceFromCapture(
        fileName: 'note.txt',
        bytes: _b('hello'),
      );
      expect(txt!.kind, IngestSourceKind.csv);
    });

    test('csv text falls back to GBK for Alipay exports', () {
      final src = ingestSourceFromCapture(
        fileName: '支付宝交易明细.csv',
        bytes: Uint8List.fromList(
          charset.gbk.encode(
            '交易时间,交易分类,交易对方,商品说明,收/支,金额,交易状态\n'
            '2026-05-30 18:50:44,餐饮美食,麦当劳,北京麦当劳食品有限公司,支出,31.50,交易成功\n',
          ),
        ),
      );

      expect(src, isNotNull);
      expect(src!.payload, contains('交易时间'));
      expect(src.payload, contains('麦当劳'));
      expect(src.payload, contains('支出'));
    });

    test('pdf → provider Vision statement lane (base64 + mime)', () {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final src = ingestSourceFromCapture(
        fileName: 'statement.pdf',
        bytes: bytes,
      );
      expect(src!.kind, IngestSourceKind.statementPdf);
      expect(src.mime, 'application/pdf');
      expect(src.payload, base64Encode(bytes));
    });

    test('images → receipt lane with the right mime', () {
      final cases = <String, String>{
        'r.jpg': 'image/jpeg',
        'r.jpeg': 'image/jpeg',
        'r.PNG': 'image/png',
        'r.webp': 'image/webp',
        'r.heic': 'image/heic',
        'r.heif': 'image/heif',
      };
      final bytes = Uint8List.fromList(<int>[9, 9, 9]);
      cases.forEach((name, mime) {
        final src = ingestSourceFromCapture(fileName: name, bytes: bytes);
        expect(src, isNotNull, reason: name);
        expect(src!.kind, IngestSourceKind.receiptImage, reason: name);
        expect(src.mime, mime, reason: name);
        expect(src.payload, base64Encode(bytes));
      });
    });

    test('unsupported extension / missing bytes → null', () {
      expect(
        ingestSourceFromCapture(fileName: 'a.docx', bytes: _b('x')),
        isNull,
      );
      expect(
        ingestSourceFromCapture(fileName: 'noext', bytes: _b('x')),
        isNull,
      );
      expect(ingestSourceFromCapture(fileName: 'a.csv', bytes: null), isNull);
      expect(
        ingestSourceFromCapture(fileName: 'a.csv', bytes: Uint8List(0)),
        isNull,
      );
    });
  });
}
