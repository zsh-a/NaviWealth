import 'package:decimal/decimal.dart';

import '../domain/dca/dca_simulator.dart';
import '../domain/trade_entry/trade_draft.dart';
import '../domain/trade_entry/trade_entry_prefill.dart';

typedef DcaTradeNoteBuilder = String Function(DcaAllocation allocation);

List<TradeEntryPrefill> buildDcaTradeEntryPrefills({
  required DcaSimulationRequestContract request,
  required DateTime tradeDate,
  required DcaTradeNoteBuilder noteBuilder,
}) {
  return [
    for (final allocation in request.allocations)
      TradeEntryPrefill(
        type: TradeType.buy,
        quantity: Decimal.one,
        price: request.amountFor(allocation),
        currency: request.currency,
        tradeDate: tradeDate,
        fee: null,
        tax: null,
        note: noteBuilder(allocation),
      ),
  ];
}

/// Stable bridge from the DCA simulator to the investment trade-entry flow.
///
/// The simulator remains read-only; callers that want to turn a periodic plan
/// into drafts pass this contract through [buildDcaTradeEntryPrefills], then
/// route each [TradeEntryPrefill] to `TradeEntryFormPage` just like rebalance.
class DcaSimulationRequestContract {
  const DcaSimulationRequestContract({
    required this.allocations,
    required this.amountPerContribution,
    required this.currency,
  });

  final List<DcaAllocation> allocations;
  final Decimal amountPerContribution;
  final String currency;

  Decimal amountFor(DcaAllocation allocation) =>
      amountPerContribution * allocation.weight;
}
