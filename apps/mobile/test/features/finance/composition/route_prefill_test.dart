import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/composition/route_prefill.dart';
import 'package:naviwealth/features/finance/investment/domain/trade_entry/trade_draft.dart'
    show TradeType;

void main() {
  group('tradeTypeFromSideQuery', () {
    test('parses buy and sell', () {
      expect(tradeTypeFromSideQuery(const {'side': 'buy'}), TradeType.buy);
      expect(tradeTypeFromSideQuery(const {'side': 'sell'}), TradeType.sell);
    });

    test('returns null for missing or unrecognised side', () {
      expect(tradeTypeFromSideQuery(const {}), isNull);
      expect(tradeTypeFromSideQuery(const {'side': 'short'}), isNull);
    });
  });

  group('decimalFromQuery', () {
    test('parses a valid decimal', () {
      expect(
        decimalFromQuery(const {'amount': '123.45'}, 'amount'),
        Decimal.parse('123.45'),
      );
    });

    test('returns null for missing, blank, or unparseable values', () {
      expect(decimalFromQuery(const {}, 'amount'), isNull);
      expect(decimalFromQuery(const {'amount': ''}, 'amount'), isNull);
      expect(decimalFromQuery(const {'amount': 'abc'}, 'amount'), isNull);
    });
  });

  group('tradeEntryPrefillFromQuery', () {
    test('returns null without the ingest marker', () {
      expect(tradeEntryPrefillFromQuery(const {'side': 'buy'}), isNull);
    });

    test('builds a full prefill from ingest query params', () {
      final prefill = tradeEntryPrefillFromQuery(const {
        'ingest': '1',
        'side': 'sell',
        'symbol': 'BRK.B',
        'quantity': '2',
        'price': '510.25',
        'currency': 'CNY',
        'date': '2026-08-01',
        'note': 'Coffee & lunch',
      }, initialType: TradeType.sell)!;

      expect(prefill.type, TradeType.sell);
      expect(prefill.quantity, Decimal.parse('2'));
      expect(prefill.price, Decimal.parse('510.25'));
      expect(prefill.currency, 'CNY');
      expect(prefill.tradeDate, DateTime(2026, 8, 1));
      expect(prefill.note, 'Coffee & lunch');
      expect(prefill.symbol, 'BRK.B');
    });

    test('falls back to buy / zero / USD when params are absent', () {
      final prefill = tradeEntryPrefillFromQuery(const {'ingest': '1'})!;

      expect(prefill.type, TradeType.buy);
      expect(prefill.quantity, Decimal.zero);
      expect(prefill.price, isNull);
      expect(prefill.currency, 'USD');
      expect(prefill.tradeDate, isNull);
      expect(prefill.note, isNull);
      expect(prefill.symbol, isNull);
    });
  });
}
