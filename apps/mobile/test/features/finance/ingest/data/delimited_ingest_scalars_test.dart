import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/data/delimited_ingest_scalars.dart';

void main() {
  test('preserves statement timestamps and explicit timezone offsets', () {
    expect(
      parseIngestDate('2026-06-18 10:30:45'),
      DateTime(2026, 6, 18, 10, 30, 45).toUtc(),
    );
    expect(
      parseIngestDate('2026-06-18T10:30:45+08:00'),
      DateTime.utc(2026, 6, 18, 2, 30, 45),
    );
    expect(
      parseIngestDate('2026年6月18日 10:30:45'),
      DateTime(2026, 6, 18, 10, 30, 45).toUtc(),
    );
    expect(parseIngestDate('2026-06-18'), DateTime.utc(2026, 6, 18));
  });

  test('parses common statement amount decorations exactly', () {
    expect(parseIngestAmountMinor(r'$1,234.50'), 123450);
    expect(parseIngestAmountMinor('(50.05)'), -5005);
    expect(parseIngestAmountMinor('-0.01'), -1);
    expect(parseIngestAmountMinor('90,071,992,547,409.93'), 9007199254740993);
  });

  test('rejects excess precision and signed 64-bit overflow', () {
    expect(parseIngestAmountMinor('1.234'), isNull);
    expect(parseIngestAmountMinor('92233720368547758.08'), isNull);
    expect(parseIngestAmountMinor('-92233720368547758.09'), isNull);
  });

  test('keeps empty statement placeholders invalid', () {
    for (final value in <String?>[null, '', '/', '--', '-']) {
      expect(parseIngestAmountMinor(value), isNull);
    }
  });
}
