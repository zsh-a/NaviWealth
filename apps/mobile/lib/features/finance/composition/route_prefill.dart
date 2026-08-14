/// Query-param parsing and prefill/model construction for FinanceOS routes.
///
/// Pure helpers consumed by `finance_routes.dart` route builders: they take
/// `state.uri.queryParameters` and return the parsed model, so the routes
/// file stays a thin declarative mapping. No GoRouter builder boilerplate
/// lives here.
library;

import 'package:decimal/decimal.dart';

import '../investment/domain/trade_entry/trade_draft.dart' show TradeType;
import '../investment/domain/trade_entry/trade_entry_prefill.dart';

/// `?side=buy|sell` → [TradeType]; a missing or unrecognised value returns
/// null so the form keeps its own default side.
TradeType? tradeTypeFromSideQuery(Map<String, String> params) =>
    switch (params['side']) {
      'buy' => TradeType.buy,
      'sell' => TradeType.sell,
      _ => null,
    };

/// Optional decimal query param: missing, blank, or unparseable → null.
Decimal? decimalFromQuery(Map<String, String> params, String key) =>
    Decimal.tryParse(params[key] ?? '');

/// Layer-4 ingest handoff prefill (`?ingest=1&…`, §5.10.10 / S5a). Null when
/// the trade route was not reached from the ingest review queue.
TradeEntryPrefill? tradeEntryPrefillFromQuery(
  Map<String, String> params, {
  TradeType? initialType,
}) {
  if (params['ingest'] != '1') return null;
  return TradeEntryPrefill(
    type: initialType ?? TradeType.buy,
    quantity: Decimal.tryParse(params['quantity'] ?? '') ?? Decimal.zero,
    price: Decimal.tryParse(params['price'] ?? ''),
    currency: params['currency'] ?? 'USD',
    tradeDate: DateTime.tryParse(params['date'] ?? ''),
    note: params['note'],
    symbol: params['symbol'],
  );
}
