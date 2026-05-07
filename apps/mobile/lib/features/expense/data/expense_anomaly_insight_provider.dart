import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/domain/expense.dart';
import '../../../data/repositories/journal_entry_providers.dart';
import '../../../domain/services/currency_converter.dart';
import '../../../domain/values/money.dart';
import '../../home/data/dashboard_providers.dart';

const double kExpenseAnomalyThreshold = 0.25;

class ExpenseAnomalySummary {
  const ExpenseAnomalySummary({required this.deltaRatio});

  /// Projected current-month spend vs. the previous 3-month average.
  /// Positive means the current month is projected higher.
  final double deltaRatio;
}

ExpenseAnomalySummary? summarizeExpenseAnomaly({
  required Iterable<Expense> expenses,
  required DateTime now,
  required CurrencyConverter converter,
  required String baseCurrency,
  double threshold = kExpenseAnomalyThreshold,
}) {
  final monthStart = DateTime.utc(now.toUtc().year, now.toUtc().month);
  final nextMonth = DateTime.utc(monthStart.year, monthStart.month + 1);
  final elapsedDays = now.toUtc().difference(monthStart).inDays + 1;
  final monthDays = nextMonth.difference(monthStart).inDays;
  final progress = elapsedDays / monthDays;
  if (progress <= 0) return null;

  var current = Decimal.zero;
  final previous = <String, Decimal>{};
  for (var i = 1; i <= 3; i++) {
    final m = DateTime.utc(monthStart.year, monthStart.month - i);
    previous[_monthKey(m)] = Decimal.zero;
  }

  for (final expense in expenses) {
    final date = expense.tradeDate.toUtc();
    final amount = _convertExpense(
      expense,
      converter: converter,
      baseCurrency: baseCurrency,
    );
    if (amount == null) continue;

    if (!date.isBefore(monthStart) && date.isBefore(nextMonth)) {
      current += amount;
      continue;
    }
    final key = _monthKey(DateTime.utc(date.year, date.month));
    if (previous.containsKey(key)) {
      previous[key] = previous[key]! + amount;
    }
  }

  final previousAverage =
      previous.values.fold<Decimal>(Decimal.zero, (sum, value) => sum + value) /
      Decimal.fromInt(previous.length);
  if (previousAverage.toDouble() <= 0) return null;

  final projected = current / Decimal.parse(progress.toString());
  final delta = (projected - previousAverage) / previousAverage;
  final ratio = delta.toDouble();
  if (ratio.abs() < threshold) return null;
  return ExpenseAnomalySummary(deltaRatio: ratio);
}

Decimal? _convertExpense(
  Expense expense, {
  required CurrencyConverter converter,
  required String baseCurrency,
}) {
  try {
    return converter
        .convert(
          Money(expense.amount, expense.currency),
          baseCurrency,
          on: expense.tradeDate,
        )
        .amount;
  } on FxRateNotFoundError {
    return null;
  }
}

String _monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

final expenseAnomalyInsightProvider = Provider<ExpenseAnomalySummary?>((ref) {
  final expenses = ref.watch(journalExpensesStreamProvider).value;
  if (expenses == null) return null;
  return summarizeExpenseAnomaly(
    expenses: expenses,
    now: DateTime.now(),
    converter: ref.watch(dashboardCurrencyConverterProvider),
    baseCurrency: ref.watch(dashboardBaseCurrencyProvider),
  );
});
