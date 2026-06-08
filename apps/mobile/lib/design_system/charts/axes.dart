import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../core/format/formatters.dart';

/// Minimum horizontal space (logical pixels) between two axis labels.
///
/// Derived from the approximate width of a medium-length label
/// (e.g. "Mar 2025" / "2025年3月" ≈ 55 px) plus a breathing gap.
const double kMinAxisLabelSpacing = 56;

/// Decide whether an axis label at [value] should be rendered, based on
/// the actual chart width and the data range.
///
/// Call this inside `getTitlesWidget` of [SideTitles].  When the label
/// would overlap its neighbour (i.e. the chart is too narrow for the
/// requested [maxLabels]), the function returns `false` and the caller
/// should return `const SizedBox.shrink()`.
///
/// [value] and [meta] come from the `getTitlesWidget` callback.
/// [range] is the data-axis span (max − min).
/// [maxLabels] is the caller's desired upper bound.
bool shouldRenderAxisLabel({
  required double value,
  required TitleMeta meta,
  required double range,
  required int maxLabels,
}) {
  if (range <= 0 || maxLabels <= 0) return true;
  final chartWidth = meta.parentAxisSize;
  if (chartWidth <= 0) return true;

  // How many labels the chart width can hold without overlap.
  final maxByWidth = (chartWidth / kMinAxisLabelSpacing).floor();
  // Use the tighter of the two constraints.
  final effectiveMax = maxLabels < maxByWidth ? maxLabels : maxByWidth;
  if (effectiveMax <= 0) return false;

  final interval = range / effectiveMax;
  if (interval <= 0) return true;

  // Render the label only if its position is "close enough" to an
  // interval grid.  The small epsilon absorbs floating-point drift.
  final epsilon = interval * 0.01;
  return (value - epsilon) % interval < epsilon * 2;
}

/// Date-axis label format presets. Picked to match the time-window buttons
/// across analytics / FIRE pages (1M / 3M / YTD / 1Y / 3Y / ALL).
enum AxisDateFormat {
  /// `Mar 12`
  dayMonth,

  /// `Mar 25` (year omitted unless it differs from now)
  monthYear,

  /// `2025` (used in ALL / 5y views)
  yearOnly,
}

/// Axis configuration for a continuous time-based X axis.
@immutable
class TimeAxis {
  const TimeAxis({
    this.format = AxisDateFormat.monthYear,
    this.locale,
    this.maxLabels = 6,
    this.showGrid = false,
  });

  final AxisDateFormat format;
  final String? locale;

  /// Upper bound on the number of labels rendered on this axis. fl_chart
  /// will auto-pick an interval that produces at most this many ticks.
  final int maxLabels;

  final bool showGrid;

  String formatTimestamp(double msSinceEpoch) {
    final dt = DateTime.fromMillisecondsSinceEpoch(msSinceEpoch.round());
    final pattern = switch (format) {
      AxisDateFormat.dayMonth => DateFormat.MMMd(locale),
      AxisDateFormat.monthYear => DateFormat.yMMM(locale),
      AxisDateFormat.yearOnly => DateFormat.y(locale),
    };
    return pattern.format(dt);
  }

  /// Full, day-resolution label for the **focused** sample (crosshair
  /// tooltip / touch bubble).
  ///
  /// The resting axis ticks stay coarse via [formatTimestamp] (year /
  /// month-year) so they don't collide, but once the user inspects a
  /// single point they want the exact date — `2025` or `2025年3月` is
  /// not actionable, `2025年3月31日` is.
  String formatPrecise(double msSinceEpoch) {
    final dt = DateTime.fromMillisecondsSinceEpoch(msSinceEpoch.round());
    return DateFormat.yMMMd(locale).format(dt);
  }
}

/// Axis configuration for a Y axis displaying numeric values.
@immutable
class ValueAxis {
  const ValueAxis({
    this.format = ValueAxisFormat.auto,
    this.currencyCode,
    this.fractionDigits,
    this.maxLabels = 5,
    this.showGrid = false,
    this.locale,
  });

  /// Money-formatted Y axis. Symbol resolves from [currencyCode].
  factory ValueAxis.currency({
    String currencyCode = 'CNY',
    int? fractionDigits,
    int maxLabels = 5,
    bool showGrid = false,
    String? locale,
  }) {
    return ValueAxis(
      format: ValueAxisFormat.currency,
      currencyCode: currencyCode,
      fractionDigits: fractionDigits,
      maxLabels: maxLabels,
      showGrid: showGrid,
      locale: locale,
    );
  }

  /// Percentage Y axis. Values are expected in percentage points (`1.5` →
  /// `1.5%`); pass through `*100` if you have a 0..1 ratio.
  factory ValueAxis.percent({
    int? fractionDigits = 0,
    int maxLabels = 5,
    bool showGrid = false,
    String? locale,
  }) {
    return ValueAxis(
      format: ValueAxisFormat.percent,
      fractionDigits: fractionDigits,
      maxLabels: maxLabels,
      showGrid: showGrid,
      locale: locale,
    );
  }

  final ValueAxisFormat format;
  final String? currencyCode;
  final int? fractionDigits;
  final int maxLabels;
  final bool showGrid;
  final String? locale;

  String formatValue(double value) {
    switch (format) {
      case ValueAxisFormat.auto:
        return NumberFormat.compact(locale: locale).format(value);
      case ValueAxisFormat.currency:
        return NumberFormat.compactCurrency(
          locale: locale,
          name: currencyCode ?? 'CNY',
          symbol: _glyph(currencyCode ?? 'CNY'),
        ).format(value);
      case ValueAxisFormat.percent:
        final digits = fractionDigits ?? 0;
        final formatter = NumberFormat.decimalPatternDigits(
          locale: locale,
          decimalDigits: digits,
        );
        return '${formatter.format(value)}%';
      case ValueAxisFormat.decimal:
        final digits = fractionDigits ?? 2;
        return NumberFormat.decimalPatternDigits(
          locale: locale,
          decimalDigits: digits,
        ).format(value);
    }
  }

  static String _glyph(String code) => AppFormatters.currencyGlyph(code);
}

enum ValueAxisFormat { auto, currency, percent, decimal }
