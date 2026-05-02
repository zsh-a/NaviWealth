import 'package:flutter/widgets.dart';

import '../tokens/breakpoints.dart';

/// Width-aware aspect ratios for line / bar / area charts (FIR-106).
///
/// Wide desktop windows can host a more cinematic 2.4:1 frame; mobile and
/// tablet keep a tighter 1.6:1 so the chart still has vertical breathing
/// room next to summary cards. Pie / donut charts ignore this helper —
/// they want a 1:1 slot regardless of viewport.
const double kChartAspectDesktop = 2.4;
const double kChartAspectMobile = 1.6;

/// Returns the aspect ratio a time-series chart should adopt for the
/// supplied width. The exact threshold matches the desktop breakpoint
/// used by the responsive shell, so charts flip to the wider ratio on
/// the same window edge that the sidebar shell does.
double chartAspectFor(double width) {
  return width >= Breakpoints.desktop
      ? kChartAspectDesktop
      : kChartAspectMobile;
}

/// `LayoutBuilder`-flavored convenience: pass through the maxWidth that
/// the chart will actually paint into and pick the right ratio. Use
/// inside a `LayoutBuilder` (or `MediaQuery`) so charts remain reactive
/// to container resize and not just to first-frame width.
double chartAspectForContext(BuildContext context, {double? maxWidth}) {
  final width = maxWidth ?? MediaQuery.sizeOf(context).width;
  return chartAspectFor(width);
}
