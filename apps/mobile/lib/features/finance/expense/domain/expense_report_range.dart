import 'package:flutter/foundation.dart';

/// Preset windows surfaced by spending analysis.
///
/// `monthToDate` is the "本月" chip (1st of the current month → today).
/// `m3` / `m6` are rolling windows ending today (used by both the report
/// and the FIRE auto-derivation default of "最近 3 个月平均"). `m12` keeps
/// the 12-month trend bar chart populated even when the user picked a
/// shorter chip for the pie. `custom` accepts an arbitrary `[from, to]`.
enum ExpenseReportRangePreset { monthToDate, m3, m6, m12, custom }

/// Resolved `[from, to)` window for the report. Both bounds are floored to
/// midnight UTC; `to` is exclusive so date filters that use
/// `tradeDate < to` behave consistently with how the repository indexes.
@immutable
class ExpenseReportRange {
  const ExpenseReportRange({
    required this.preset,
    required this.from,
    required this.to,
  });

  /// Build the range for [preset] anchored at [now] (defaults to
  /// `DateTime.now()`). For [ExpenseReportRangePreset.custom] callers must
  /// pass [customFrom] / [customTo]; both are floored to UTC midnight.
  factory ExpenseReportRange.resolve({
    required ExpenseReportRangePreset preset,
    DateTime? now,
    DateTime? customFrom,
    DateTime? customTo,
  }) {
    final today = _floorToDay(now ?? DateTime.now());
    // The report's `to` is exclusive — the day *after* the last day we want
    // to include. That keeps month-to-date showing today's spend.
    final tomorrow = today.add(const Duration(days: 1));
    DateTime from;
    DateTime to = tomorrow;

    switch (preset) {
      case ExpenseReportRangePreset.monthToDate:
        from = DateTime.utc(today.year, today.month, 1);
      case ExpenseReportRangePreset.m3:
        from = _firstOfMonthBefore(today, 2);
      case ExpenseReportRangePreset.m6:
        from = _firstOfMonthBefore(today, 5);
      case ExpenseReportRangePreset.m12:
        from = _firstOfMonthBefore(today, 11);
      case ExpenseReportRangePreset.custom:
        if (customFrom == null || customTo == null) {
          throw ArgumentError(
            'ExpenseReportRangePreset.custom requires customFrom / customTo.',
          );
        }
        from = _floorToDay(customFrom);
        to = _floorToDay(customTo).add(const Duration(days: 1));
        if (!to.isAfter(from)) {
          throw ArgumentError('customTo must be on or after customFrom.');
        }
    }
    return ExpenseReportRange(preset: preset, from: from, to: to);
  }

  final ExpenseReportRangePreset preset;
  final DateTime from;

  /// Exclusive upper bound: `tradeDate < to` is the inclusion test.
  final DateTime to;

  /// Number of included UTC calendar days. Unlike a calendar-month count,
  /// this remains meaningful for month-to-date and arbitrary custom ranges.
  int get daySpan => to.difference(from).inDays;

  /// Number of distinct calendar months touched by the window. The pie
  /// chart and category list need this to print "近 N 月" headers without
  /// the caller re-deriving it. A range that starts and ends in the same
  /// month returns 1.
  int get monthSpan {
    final fromMonth = from.year * 12 + (from.month - 1);
    // `to` is exclusive — the last *included* day is `to - 1`.
    final lastIncluded = to.subtract(const Duration(days: 1));
    final toMonth = lastIncluded.year * 12 + (lastIncluded.month - 1);
    return toMonth - fromMonth + 1;
  }

  static DateTime _firstOfMonthBefore(DateTime today, int monthsBack) {
    var year = today.year;
    var month = today.month - monthsBack;
    while (month <= 0) {
      month += 12;
      year -= 1;
    }
    return DateTime.utc(year, month, 1);
  }

  static DateTime _floorToDay(DateTime d) {
    final u = d.toUtc();
    return DateTime.utc(u.year, u.month, u.day);
  }

  @override
  bool operator ==(Object other) =>
      other is ExpenseReportRange &&
      other.preset == preset &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(preset, from, to);
}
