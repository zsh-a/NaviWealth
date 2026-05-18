import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/investment/application/dca_trade_entry_prefills.dart';
import 'package:naviwealth/features/investment/domain/dca/dca_simulator.dart';
import 'package:naviwealth/features/investment/domain/trade_entry/trade_draft.dart';

void main() {
  test('builds buy prefills for the next DCA basket allocation', () {
    final tradeDate = DateTime.utc(2026, 5, 18);
    final prefills = buildDcaTradeEntryPrefills(
      request: DcaSimulationRequestContract(
        allocations: [
          DcaAllocation(symbol: 'VOO', weight: Decimal.parse('0.6')),
          DcaAllocation(symbol: 'QQQ', weight: Decimal.parse('0.4')),
        ],
        amountPerContribution: Decimal.parse('1000'),
        currency: 'USD',
      ),
      tradeDate: tradeDate,
      noteBuilder: (allocation) => 'DCA ${allocation.symbol}',
    );

    expect(prefills, hasLength(2));
    expect(prefills.first.type, TradeType.buy);
    expect(prefills.first.quantity, Decimal.one);
    expect(prefills.first.price, Decimal.parse('600.0'));
    expect(prefills.first.currency, 'USD');
    expect(prefills.first.tradeDate, tradeDate);
    expect(prefills.first.note, 'DCA VOO');
  });
}
