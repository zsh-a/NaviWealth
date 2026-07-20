import 'package:flutter/foundation.dart';

/// Two adjacent twelve-month windows with explicit boundary semantics.
@immutable
class DividendComparisonWindow {
  const DividendComparisonWindow({
    required this.priorStart,
    required this.currentStart,
    required this.endExclusive,
  });

  /// Rolling windows ending immediately after [now].
  factory DividendComparisonWindow.trailing(DateTime now) {
    final utc = now.toUtc();
    return DividendComparisonWindow(
      priorStart: _sameCalendarDay(utc, utc.year - 2),
      currentStart: _sameCalendarDay(utc, utc.year - 1),
      endExclusive: utc.add(const Duration(microseconds: 1)),
    );
  }

  /// Stable reporting windows ending at the first day of the current month.
  factory DividendComparisonWindow.completedMonths(DateTime now) {
    final utc = now.toUtc();
    final end = DateTime.utc(utc.year, utc.month);
    return DividendComparisonWindow(
      priorStart: _addMonths(end, -24),
      currentStart: _addMonths(end, -12),
      endExclusive: end,
    );
  }

  final DateTime priorStart;
  final DateTime currentStart;
  final DateTime endExclusive;

  bool containsPrior(DateTime value) {
    final utc = value.toUtc();
    return !utc.isBefore(priorStart) && utc.isBefore(currentStart);
  }

  bool containsCurrent(DateTime value) {
    final utc = value.toUtc();
    return !utc.isBefore(currentStart) && utc.isBefore(endExclusive);
  }
}

DateTime _sameCalendarDay(DateTime value, int year) {
  final lastDay = DateTime.utc(year, value.month + 1, 0).day;
  final day = value.day > lastDay ? lastDay : value.day;
  return DateTime.utc(
    year,
    value.month,
    day,
    value.hour,
    value.minute,
    value.second,
    value.millisecond,
    value.microsecond,
  );
}

DateTime _addMonths(DateTime value, int delta) =>
    DateTime.utc(value.year, value.month + delta);
