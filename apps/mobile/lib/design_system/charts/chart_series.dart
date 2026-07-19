import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'chart_palette.dart';

/// A single (x, y) sample on a continuous chart (line / area).
@immutable
class ChartPoint {
  const ChartPoint({required this.x, required this.y, this.meta});

  /// Time axis: prefer ms-since-epoch (`DateTime.millisecondsSinceEpoch`).
  /// Category axis: 0-based integer index of the category.
  final double x;
  final double y;

  /// Opaque value forwarded to the tooltip / drill-down callback. Use it to
  /// carry the original domain object (a `Decimal`, a `Lot`, a `BenchmarkRow`)
  /// without forcing the chart layer to know about it.
  final Object? meta;
}

/// One series on a line / area / stacked-area chart.
@immutable
class ChartSeries {
  const ChartSeries({
    required this.name,
    required this.points,
    this.intent = SeriesIntent.primary,
    this.emphasis = SeriesEmphasis.solid,
    this.colorOverride,
    this.fillOpacity,
    this.strokeWidth,
  });

  final String name;
  final List<ChartPoint> points;
  final SeriesIntent intent;
  final SeriesEmphasis emphasis;

  /// Escape hatch for the rare case where intent + ordinal don't suffice
  /// (e.g. matching an existing brand color in a screenshot). Prefer
  /// [intent] for everything else.
  final Color? colorOverride;

  /// Fill opacity for area / stacked-area. `null` → renderer picks a
  /// reasonable default (12% for primary, 18% for dark mode).
  final double? fillOpacity;

  /// Stroke width override. `null` → renderer picks based on intent.
  final double? strokeWidth;
}

/// One sample on a discrete category chart (single bar / one slice).
@immutable
class CategoryDatum {
  const CategoryDatum({
    required this.label,
    required this.value,
    this.tooltipLabel,
    this.colorOverride,
    this.meta,
  });

  final String label;
  final double value;
  final String? tooltipLabel;
  final Color? colorOverride;
  final Object? meta;
}

/// One series on a bar chart. Multiple series → grouped or stacked bars.
@immutable
class CategorySeries {
  const CategorySeries({
    required this.name,
    required this.data,
    this.intent = SeriesIntent.primary,
    this.colorOverride,
  });

  final String name;
  final List<CategoryDatum> data;
  final SeriesIntent intent;
  final Color? colorOverride;
}

/// One slice of a pie / donut chart.
@immutable
class Slice {
  const Slice({
    required this.label,
    required this.value,
    this.colorOverride,
    this.meta,
  });

  final String label;
  final double value;
  final Color? colorOverride;
  final Object? meta;
}
