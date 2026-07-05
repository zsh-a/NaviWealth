import 'package:flutter/foundation.dart';

import 'dashboard_granularity.dart';

/// Preset time windows surfaced by the dashboard's net-worth trend chart.
/// `custom` is filled in by the user via a date-range picker; the others are
/// computed from `now` at the moment the user picks the chip.
enum DashboardRangePreset { m1, m3, m6, y1, y3, all, custom }

/// Resolved `[from, to]` window for the trend chart, plus the
/// [NetWorthGranularity] the chart should sample at. The granularity is
/// derived deterministically from the window length so a 1-month chart
/// never tries to render 90 daily ticks and the "全部" (`all`) chart never
/// blows past the chart wrapper's downsample budget.
@immutable
class DashboardTimeRange {
  const DashboardTimeRange({
    required this.preset,
    required this.from,
    required this.to,
    required this.granularity,
  });

  /// Build the resolved range for [preset] anchored at [now]. `now` is
  /// usually `DateTime.now()` but is injectable for tests / golden runs.
  ///
  /// `custom` resolves with the caller-provided [customFrom] / [customTo]
  /// (which must be non-null and ordered); for the preset-driven cases
  /// those parameters are ignored.
  ///
  /// `all` resolves to `[earliestDataDate, now]` when the caller knows
  /// when the user's data starts; otherwise it falls back to a 5-year
  /// window (long enough for a FIRE chart, short enough for the daily
  /// granularity to stay within the downsample target).
  factory DashboardTimeRange.resolve({
    required DashboardRangePreset preset,
    required DateTime now,
    DateTime? earliestDataDate,
    DateTime? customFrom,
    DateTime? customTo,
  }) {
    final today = _floorToDay(now);
    DateTime from;
    DateTime to = today;
    switch (preset) {
      case DashboardRangePreset.m1:
        from = today.subtract(const Duration(days: 30));
      case DashboardRangePreset.m3:
        from = today.subtract(const Duration(days: 90));
      case DashboardRangePreset.m6:
        from = today.subtract(const Duration(days: 182));
      case DashboardRangePreset.y1:
        from = today.subtract(const Duration(days: 365));
      case DashboardRangePreset.y3:
        from = today.subtract(const Duration(days: 365 * 3));
      case DashboardRangePreset.all:
        final candidate =
            earliestDataDate ?? today.subtract(const Duration(days: 365 * 5));
        from = _floorToDay(candidate);
        if (!from.isBefore(today)) {
          from = today.subtract(const Duration(days: 30));
        }
      case DashboardRangePreset.custom:
        if (customFrom == null || customTo == null) {
          throw ArgumentError(
            'DashboardRangePreset.custom requires customFrom and customTo.',
          );
        }
        from = _floorToDay(customFrom);
        to = _floorToDay(customTo);
        if (to.isBefore(from)) {
          throw ArgumentError('customTo must not be before customFrom.');
        }
    }
    return DashboardTimeRange(
      preset: preset,
      from: from,
      to: to,
      granularity: _granularityFor(from, to),
    );
  }

  final DashboardRangePreset preset;
  final DateTime from;
  final DateTime to;
  final NetWorthGranularity granularity;

  /// Length of the window in whole days (always >= 0).
  int get spanDays => to.difference(from).inDays;

  static NetWorthGranularity _granularityFor(DateTime from, DateTime to) {
    final days = to.difference(from).inDays;
    if (days <= 120) return NetWorthGranularity.day;
    if (days <= 730) return NetWorthGranularity.week;
    return NetWorthGranularity.month;
  }

  static DateTime _floorToDay(DateTime d) {
    final u = d.toUtc();
    return DateTime.utc(u.year, u.month, u.day);
  }

  @override
  bool operator ==(Object other) =>
      other is DashboardTimeRange &&
      other.preset == preset &&
      other.from == from &&
      other.to == to &&
      other.granularity == granularity;

  @override
  int get hashCode => Object.hash(preset, from, to, granularity);
}
