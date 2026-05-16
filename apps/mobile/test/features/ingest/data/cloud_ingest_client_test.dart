import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ingest/data/cloud_ingest_client.dart';
import 'package:naviwealth/features/ingest/domain/ingest_models.dart';

void main() {
  group('cloudIngestKindWire', () {
    test('maps cloud kinds to the backend snake_case contract', () {
      expect(
        cloudIngestKindWire(IngestSourceKind.receiptImage),
        'receipt_image',
      );
      expect(
        cloudIngestKindWire(IngestSourceKind.statementPdf),
        'statement_pdf',
      );
    });
  });

  group('parsedTransactionFromWire', () {
    test('maps a full row and normalises to negative outflow', () {
      final p = parsedTransactionFromWire(<String, Object?>{
        'description': 'Starbucks',
        'amount_minor': 3800,
        'currency': 'cny',
        'occurred_at': '2026-05-10',
        'category_hint': 'coffee',
        'confidence': 0.92,
      });
      expect(p, isNotNull);
      expect(p!.amountMinor, -3800);
      expect(p.currency, 'CNY');
      expect(p.categoryHint, 'coffee');
      expect(p.occurredAt, DateTime.utc(2026, 5, 10));
      expect(p.confidence, 0.92);
    });

    test('defaults confidence and description when omitted', () {
      final p = parsedTransactionFromWire(<String, Object?>{
        'amount_minor': -120,
        'currency': 'USD',
        'occurred_at': '2026-01-02',
      });
      expect(p, isNotNull);
      expect(p!.confidence, 0.6);
      expect(p.description, '未命名交易');
      expect(p.categoryHint, isNull);
    });

    test('rejects rows missing amount / currency / date', () {
      expect(
        parsedTransactionFromWire(<String, Object?>{
          'currency': 'USD',
          'occurred_at': '2026-01-02',
        }),
        isNull,
      );
      expect(
        parsedTransactionFromWire(<String, Object?>{
          'amount_minor': -1,
          'currency': '',
          'occurred_at': '2026-01-02',
        }),
        isNull,
      );
      expect(
        parsedTransactionFromWire(<String, Object?>{
          'amount_minor': -1,
          'currency': 'USD',
          'occurred_at': 'not-a-date',
        }),
        isNull,
      );
      expect(
        parsedTransactionFromWire(<String, Object?>{
          'amount_minor': 0,
          'currency': 'USD',
          'occurred_at': '2026-01-02',
        }),
        isNull,
      );
    });
  });

  group('parseCloudIngestResponse', () {
    test('extracts the drafts array and skips malformed rows', () {
      final list = parseCloudIngestResponse(<String, Object?>{
        'model': 'mimo-v2.5-pro',
        'drafts': <Object?>[
          <String, Object?>{
            'description': 'A',
            'amount_minor': -100,
            'currency': 'USD',
            'occurred_at': '2026-01-02',
          },
          <String, Object?>{'description': 'bad'},
          'not-a-map',
        ],
      });
      expect(list, hasLength(1));
      expect(list.single.description, 'A');
    });

    test('empty / missing drafts yields an empty list', () {
      expect(parseCloudIngestResponse(<String, Object?>{}), isEmpty);
      expect(
        parseCloudIngestResponse(<String, Object?>{'drafts': <Object?>[]}),
        isEmpty,
      );
    });
  });
}
