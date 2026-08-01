import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/data/delimited_ingest_scalars.dart';

void main() {
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
