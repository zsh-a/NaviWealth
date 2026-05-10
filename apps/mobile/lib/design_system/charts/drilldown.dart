import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter/widgets.dart';

import 'chart_series.dart';

/// Drill-down callback handlers passed to [NwLineChart], [NwAreaChart],
/// [NwBarChart], [NwPieChart].
///
/// Use the named constructors that match the chart's interaction model:
/// `point` for line / area, `bar` for bar, `slice` for pie. `range` is
/// available on continuous charts for span-selection (long-press + drag on
/// mobile, click-drag on desktop).
@immutable
sealed class ChartDrillDown {
  const ChartDrillDown();

  const factory ChartDrillDown.point(ValueChanged<ChartPoint> onTap) =
      PointDrillDown;
  const factory ChartDrillDown.range(
    ValueChanged<ChartRangeSelection> onRange,
  ) = RangeDrillDown;
  const factory ChartDrillDown.slice(ValueChanged<Slice> onTap) =
      SliceDrillDown;
  const factory ChartDrillDown.bar(ValueChanged<CategoryDatum> onTap) =
      BarDrillDown;

  /// Whether to fire haptic feedback on selection. Mobile only.
  bool get haptic;
}

@immutable
class PointDrillDown extends ChartDrillDown {
  const PointDrillDown(this.onTap, {this.haptic = true});
  final ValueChanged<ChartPoint> onTap;
  @override
  final bool haptic;
}

@immutable
class RangeDrillDown extends ChartDrillDown {
  const RangeDrillDown(this.onRange, {this.haptic = false});
  final ValueChanged<ChartRangeSelection> onRange;
  @override
  final bool haptic;
}

@immutable
class SliceDrillDown extends ChartDrillDown {
  const SliceDrillDown(this.onTap, {this.haptic = true});
  final ValueChanged<Slice> onTap;
  @override
  final bool haptic;
}

@immutable
class BarDrillDown extends ChartDrillDown {
  const BarDrillDown(this.onTap, {this.haptic = true});
  final ValueChanged<CategoryDatum> onTap;
  @override
  final bool haptic;
}

/// Result of a range gesture on a continuous chart.
///
/// `start` / `end` are in the same units as `ChartPoint.x` (ms-since-epoch
/// for time axes, integer indices for category axes). For time axes a
/// convenience [asDateRange] returns a [DateTimeRange].
@immutable
class ChartRangeSelection {
  const ChartRangeSelection({
    required this.start,
    required this.end,
    required this.points,
  });

  final double start;
  final double end;

  /// Points whose `x` falls within `[start, end]`. Pre-filtered by the
  /// chart layer so callers don't need to re-walk the series.
  final List<ChartPoint> points;

  DateTimeRange get asDateRange => DateTimeRange(
    start: DateTime.fromMillisecondsSinceEpoch(start.round()),
    end: DateTime.fromMillisecondsSinceEpoch(end.round()),
  );
}
