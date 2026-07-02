import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:naviwealth/domain/services/currency_converter.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';

/// Auto-derived monthly expense average that the FIRE dashboard consumes for
/// its "月支出" field.
///
/// The derivation is deliberately simple: average the last [windowMonths]
/// *complete* calendar months ending the month before [asOf]. The current
/// in-progress month is excluded so the figure doesn't lurch downward at
/// the start of every month — once the user is a few days into May, the
/// FIRE projection should still be using April's spend, not "May so far".
///
/// Expenses whose currency can't be converted to [baseCurrency] are
/// counted in [MonthlyExpenseAverage.skippedFxCount] rather than silently
/// dropped, mirroring [ExpenseReport]'s contract.
class MonthlyExpenseDerivation {
  const MonthlyExpenseDerivation({
    required this.converter,
    required this.baseCurrency,
  });

  final CurrencyConverter converter;
  final String baseCurrency;

  /// Compute the rolling average across the last [windowMonths] complete
  /// months ending immediately before [asOf]. Returns a zero-amount
  /// [MonthlyExpenseAverage] when the window contains no expenses (so the
  /// FIRE dashboard renders "auto · ¥0" instead of crashing on an empty
  /// snapshot).
  MonthlyExpenseAverage compute({
    required Iterable<Expense> expenses,
    required int windowMonths,
    DateTime? asOf,
  }) {
    if (windowMonths <= 0) {
      throw ArgumentError.value(
        windowMonths,
        'windowMonths',
        'must be positive',
      );
    }
    final now = (asOf ?? DateTime.now()).toUtc();
    // Window: [start, currentMonthStart). Always excludes the in-progress
    // month — that's the whole point of "rolling average of complete months".
    final currentMonthStart = DateTime.utc(now.year, now.month, 1);
    final start = _firstOfMonthBefore(currentMonthStart, windowMonths);

    var total = Decimal.zero;
    var skipped = 0;
    for (final expense in expenses) {
      final t = expense.tradeDate.toUtc();
      if (t.isBefore(start)) continue;
      if (!t.isBefore(currentMonthStart)) continue;
      try {
        final converted = converter.convert(
          Money(expense.amount, expense.currency),
          baseCurrency,
          on: expense.tradeDate,
        );
        total += converted.amount;
      } on FxRateNotFoundError {
        skipped++;
      }
    }

    final divisor = Decimal.fromInt(windowMonths);
    final avg = (total / divisor).toDecimal(scaleOnInfinitePrecision: 2);
    return MonthlyExpenseAverage(
      average: Money(avg, baseCurrency),
      windowMonths: windowMonths,
      windowStart: start,
      windowEnd: currentMonthStart,
      skippedFxCount: skipped,
    );
  }

  static DateTime _firstOfMonthBefore(DateTime ref, int monthsBack) {
    var year = ref.year;
    var month = ref.month - monthsBack;
    while (month <= 0) {
      month += 12;
      year -= 1;
    }
    return DateTime.utc(year, month, 1);
  }
}

/// Derived rolling-average snapshot. Pure data — the FIRE dashboard /
/// override layer can hold one of these per recompute and decide whether
/// to display it directly or fall back to a manual override.
@immutable
class MonthlyExpenseAverage {
  const MonthlyExpenseAverage({
    required this.average,
    required this.windowMonths,
    required this.windowStart,
    required this.windowEnd,
    required this.skippedFxCount,
  });

  final Money average;
  final int windowMonths;

  /// Inclusive UTC start of the rolling window.
  final DateTime windowStart;

  /// Exclusive UTC end of the rolling window — always the first day of
  /// the calendar month that contains `asOf`. Surfacing it lets the FIRE
  /// UI render "based on Jan–Mar 2026 (3 完整月)" without re-deriving the
  /// dates.
  final DateTime windowEnd;

  final int skippedFxCount;
}

/// Whether the current FIRE "月支出" reading is the auto-derivation or a
/// user-supplied override. Surface the value to users so they can tell
/// when the projection has been hand-tuned.
enum MonthlyExpenseSource { auto, manual }

/// Resolved monthly expense ready for the FIRE dashboard. [auto] is the
/// rolling average, kept around even when [source] is `manual` so the UI
/// can render a "current auto value would be …" hint next to the override.
@immutable
class EffectiveMonthlyExpense {
  const EffectiveMonthlyExpense({
    required this.source,
    required this.value,
    required this.auto,
  });

  final MonthlyExpenseSource source;
  final Money value;
  final MonthlyExpenseAverage auto;

  bool get isManual => source == MonthlyExpenseSource.manual;
}
