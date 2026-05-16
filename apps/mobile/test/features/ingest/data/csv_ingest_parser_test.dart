import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/ingest/data/csv_ingest_parser.dart';

void main() {
  group('parseCsvLedger', () {
    test('parses a header CSV and normalises to negative outflow', () {
      final rows = parseCsvLedger(
        'date,description,amount,currency\n'
        '2026-05-10,Starbucks Coffee,-38.00,CNY\n'
        '2026-05-11,Whole Foods,128.50,USD\n',
      );
      expect(rows, hasLength(2));
      expect(rows[0].description, 'Starbucks Coffee');
      expect(rows[0].amountMinor, -3800);
      expect(rows[0].currency, 'CNY');
      expect(rows[0].occurredAt, DateTime.utc(2026, 5, 10));
      // Positive bank column is still treated as an expense outflow.
      expect(rows[1].amountMinor, -12850);
      expect(rows[1].currency, 'USD');
    });

    test('falls back to positional columns when no header', () {
      final rows = parseCsvLedger('2026/05/12,美团外卖,-35,\n');
      expect(rows, hasLength(1));
      expect(rows[0].description, '美团外卖');
      expect(rows[0].amountMinor, -3500);
      expect(rows[0].occurredAt, DateTime.utc(2026, 5, 12));
    });

    test('merges payee + description and respects quoted commas', () {
      final rows = parseCsvLedger(
        'date,payee,description,amount\n'
        '2026-01-02,"Amazon, Inc.","order #A1",-9.99\n',
      );
      expect(rows, hasLength(1));
      expect(rows[0].description, 'Amazon, Inc. · order #A1');
      expect(rows[0].amountMinor, -999);
    });

    test('handles thousands separators, currency glyphs and parens', () {
      final rows = parseCsvLedger(
        'date,description,amount\n'
        '2026-03-01,Rent,"\$1,234.00"\n'
        '2026-03-02,Refundish,(50.00)\n',
      );
      expect(rows[0].amountMinor, -123400);
      expect(rows[1].amountMinor, -5000);
    });

    test('skips rows without a valid date or amount', () {
      final rows = parseCsvLedger(
        'date,description,amount\n'
        'not-a-date,Garbage,10\n'
        '2026-05-10,Valid,-1.00\n'
        '2026-05-11,No amount,\n'
        '\n',
      );
      expect(rows, hasLength(1));
      expect(rows.single.description, 'Valid');
    });

    test('parses US m/d/y and 2-digit years', () {
      final rows = parseCsvLedger('05/10/26,Diner,-12.00');
      expect(rows.single.occurredAt, DateTime.utc(2026, 5, 10));
    });

    test('empty input yields no rows', () {
      expect(parseCsvLedger(''), isEmpty);
      expect(parseCsvLedger('   \n  \n'), isEmpty);
    });
  });
}
