/// Public API for the NaviWealth chart wrappers.
///
/// All business code should depend on this barrel rather than importing
/// `package:fl_chart/fl_chart.dart` directly. The wrappers handle theme,
/// downsampling, drill-down, and the empty state. See
/// `docs/design/14-charts.md` for design rationale.
library;

export 'axes.dart';
export 'chart_layout.dart';
export 'chart_palette.dart'
    show ChartPalette, SeriesIntent, SeriesEmphasis, resolveSeriesColor;
export 'chart_series.dart';
export 'downsample.dart';
export 'drilldown.dart';
export 'empty_chart_placeholder.dart';
export 'nw_area_chart.dart';
export 'nw_bar_chart.dart';
export 'nw_line_chart.dart';
export 'nw_pie_chart.dart';
export 'stage_chart.dart';
