import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import '../tokens/typography_tokens.dart';
import '../widgets/app_interaction.dart';
import 'axes.dart';
import 'chart_series.dart';
import 'nw_line_chart.dart';

/// Living data stage: full-width scrubbable chart with a live value readout
/// (Phase C).
///
/// While the user scrubs, [valueBuilder] / [labelBuilder] receive the active
/// sample; on release they return to the latest point.
class StageChart extends StatefulWidget {
  const StageChart({
    super.key,
    required this.series,
    required this.valueBuilder,
    this.labelBuilder,
    this.height = AppChartHeights.full,
    this.semanticLabel,
    this.filled = true,
    this.heroDots = true,
  });

  final List<ChartSeries> series;
  final Widget Function(BuildContext context, ChartPoint? active) valueBuilder;
  final Widget Function(BuildContext context, ChartPoint? active)? labelBuilder;
  final double height;
  final String? semanticLabel;
  final bool filled;
  final bool heroDots;

  @override
  State<StageChart> createState() => _StageChartState();
}

class _StageChartState extends State<StageChart> {
  ChartPoint? _scrub;

  ChartPoint? get _latest {
    for (final s in widget.series) {
      if (s.points.isNotEmpty) return s.points.last;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final active = _scrub ?? _latest;
    final colors = context.theme.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.valueBuilder(context, active),
        if (widget.labelBuilder != null) ...[
          const SizedBox(height: AppSpacing.s4),
          widget.labelBuilder!(context, active),
        ],
        const SizedBox(height: AppSpacing.s12),
        SizedBox(
          height: widget.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: colors.border.withValues(alpha: AppOpacity.faint),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: NwLineChart(
                series: widget.series,
                filled: widget.filled,
                heroDots: widget.heroDots,
                showXAxis: true,
                showYAxis: false,
                minimal: true,
                semanticLabel: widget.semanticLabel,
                xAxis: const TimeAxis(),
                yAxis: const ValueAxis(),
                onScrub: (point) {
                  final next = point;
                  if (next != null && _scrub?.x != next.x) {
                    AppInteraction.signal(AppInteractionIntent.select);
                  }
                  setState(() => _scrub = next);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact money-style stage value using design-system display type.
class StageDisplayValue extends StatelessWidget {
  const StageDisplayValue({super.key, required this.child, this.caption});

  final Widget child;
  final Widget? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DefaultTextStyle.merge(
          style: TypographyTokens.displayLarge,
          child: child,
        ),
        if (caption != null) ...[
          const SizedBox(height: AppSpacing.s4),
          DefaultTextStyle.merge(style: context.captionStyle, child: caption!),
        ],
      ],
    );
  }
}
