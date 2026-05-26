/// Shared adapter: project a stored [Expense] into the neutral
/// [TransactionInput] shape every skill in this directory consumes.
///
/// The signed-amount convention is: outflows (the always-true case
/// for `Expense`) carry a negative `amountMinor` string. Cents are
/// floored — the ledger amount is already aligned to the currency's
/// minor unit, so `*100 → floor → BigInt` round-trips losslessly.
///
/// Originally duplicated in `drift_query_plan_executor.dart` and the
/// chat repository's `providers.dart`; promoted here once a third
/// caller (`duplicate_charge_insight_provider.dart`) showed up.
library;

import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/data/domain/expense.dart';
import 'transaction_input.dart';

TransactionInput expenseToTransactionInput(Expense e) {
  final cents = (e.amount * Decimal.fromInt(100)).floor().toBigInt();
  return TransactionInput(
    id: e.id,
    description: e.note ?? '',
    amountMinor: '-$cents',
    currency: e.currency,
    occurredAt: e.tradeDate,
    accountId: e.expenseAccountId,
    categoryId: e.expenseAccountId,
  );
}
