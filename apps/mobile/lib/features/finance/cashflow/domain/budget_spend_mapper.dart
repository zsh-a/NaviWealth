import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';

/// Build the realised spend map that [buildMonthlyBudgetSummary] expects.
///
/// Expenses are keyed by their expense account id, which is the same value
/// stored as `BudgetRow.categoryId`. Non-convertible foreign-currency
/// expenses are skipped so a missing FX rate does not poison the whole
/// budget signal.
Map<String, Money> buildBudgetSpendByCategoryId({
  required String periodMonth,
  required Iterable<Expense> expenses,
  required String targetCurrency,
  required CurrencyConverter converter,
}) {
  final currency = targetCurrency.trim().toUpperCase();
  final spendByCategory = <String, Money>{};

  for (final expense in expenses) {
    if (_periodMonth(expense.tradeDate) != periodMonth) continue;
    final raw = Money(expense.amount, expense.currency);
    final converted = _convertOrNull(
      raw,
      currency,
      converter: converter,
      on: expense.tradeDate,
    );
    if (converted == null) continue;
    spendByCategory.update(
      expense.expenseAccountId,
      (current) => current + converted,
      ifAbsent: () => converted,
    );
  }

  return Map.unmodifiable(spendByCategory);
}

Money? _convertOrNull(
  Money amount,
  String targetCurrency, {
  required CurrencyConverter converter,
  required DateTime on,
}) {
  if (amount.currency == targetCurrency) return amount;
  try {
    return converter.convert(amount, targetCurrency, on: on);
  } on FxRateNotFoundError {
    return null;
  }
}

String _periodMonth(DateTime date) {
  final utc = date.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}';
}
