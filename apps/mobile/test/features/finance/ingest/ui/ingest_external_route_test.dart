import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/ingest/domain/ingest_models.dart';
import 'package:naviwealth/features/finance/ingest/ui/ingest_external_route.dart';

ParsedTransaction _parsed({
  int amountMinor = -12345,
  String description = 'Coffee & lunch',
  String? side,
  String? symbol,
  String? quantity,
  String? price,
}) => ParsedTransaction(
  description: description,
  amountMinor: amountMinor,
  currency: 'CNY',
  occurredAt: DateTime(2026, 8, 1),
  activitySide: side,
  instrumentSymbol: symbol,
  quantity: quantity,
  unitPrice: price,
);

void main() {
  test(
    'builds an exact transfer prefill without floating point conversion',
    () {
      final uri = Uri.parse(
        buildIngestTransferRoute(_parsed(amountMinor: -9007199254740993)),
      );

      expect(uri.path, '/activity/transfer');
      expect(uri.queryParameters, <String, String>{
        'amount': '90071992547409.93',
        'date': '2026-08-01',
        'note': 'Coffee & lunch',
      });
    },
  );

  test('includes available trade fields and the ingest marker', () {
    final uri = Uri.parse(
      buildIngestTradeRoute(
        _parsed(side: 'buy', symbol: 'BRK.B', quantity: '2', price: '510.25'),
      ),
    );

    expect(uri.path, '/activity/trade');
    expect(uri.queryParameters, <String, String>{
      'side': 'buy',
      'symbol': 'BRK.B',
      'quantity': '2',
      'price': '510.25',
      'currency': 'CNY',
      'date': '2026-08-01',
      'note': 'Coffee & lunch',
      'ingest': '1',
    });
  });

  test('omits unavailable optional trade fields', () {
    final uri = Uri.parse(buildIngestTradeRoute(_parsed()));

    expect(uri.queryParameters, isNot(contains('side')));
    expect(uri.queryParameters, isNot(contains('symbol')));
    expect(uri.queryParameters, isNot(contains('quantity')));
    expect(uri.queryParameters, isNot(contains('price')));
  });
}
