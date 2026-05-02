import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/typography_tokens.dart';
import 'chart_palette.dart';
import 'chart_series.dart';
import 'drilldown.dart';
import 'empty_chart_placeholder.dart';

/// Theme-aware pie / donut chart.
///
/// Pass [hole] = 0.62 for a donut; 0 for a solid pie. Slices smaller than
/// `<minLabelPercent>` of the total are not annotated to avoid label
/// collisions; their value still appears in the tooltip on tap.
///
/// The center slot displays total value by default; when a slice is
/// highlighted (via tap-and-hold), it switches to that slice's amount,
/// name, and percentage.
class NwPieChart extends StatefulWidget {
  const NwPieChart({
    super.key,
    required this.slices,
    this.hole = 0.62,
    this.aspectRatio = 1,
    this.drillDown,
    this.minLabelPercent = 5,
    this.semanticLabel,
    this.legendBuilder,
  });

  final List<Slice> slices;
  final double hole;
  final double aspectRatio;
  final ChartDrillDown? drillDown;

  /// Slices with a percentage below this threshold render without a label
  /// inside the slice (their value still shows in the tooltip on tap).
  final double minLabelPercent;

  final String? semanticLabel;

  /// Optional builder for a legend widget. Receives the slices, the
  /// resolved colors, and the total. Return null to hide the legend.
  /// Typically renders a column of [LegendRow] widgets to the right of
  /// the chart.
  final Widget Function(
    BuildContext context,
    List<Slice> slices,
    List<Color> colors,
    double total,
  )? legendBuilder;

  @override
  State<NwPieChart> createState() => _NwPieChartState();
}

class _NwPieChartState extends State<NwPieChart> {
  int _highlightedIndex = -1;

  @override
  Widget build(BuildContext context) {
    if (widget.slices.isEmpty) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: const EmptyChartPlaceholder(icon: Icons.donut_large),
      );
    }
    final palette = ChartPalette.of(context);
    final total = widget.slices.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: const EmptyChartPlaceholder(icon: Icons.donut_large),
      );
    }

    final colors = <Color>[
      for (var i = 0; i < widget.slices.length; i++)
        widget.slices[i].colorOverride ?? palette.accentAt(i),
    ];

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < widget.slices.length; i++) {
      final s = widget.slices[i];
      final pct = (s.value / total) * 100;
      final color = colors[i];
      final isHighlighted = _highlightedIndex == i;
      sections.add(PieChartSectionData(
        value: s.value,
        color: color,
        radius: isHighlighted ? 64 : 56,
        title: pct >= widget.minLabelPercent
            ? '${pct.toStringAsFixed(0)}%'
            : '',
        titleStyle: TypographyTokens.numericCaption.copyWith(
          color: _onColor(color),
        ),
      ));
    }

    final centerRadius = widget.hole * 80;

    final pieChart = PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: centerRadius,
        sectionsSpace: 3,
        pieTouchData: _buildTouchData(),
      ),
    );

    final chartWidget = Stack(
      alignment: Alignment.center,
      children: [
        pieChart,
        SizedBox(
          width: centerRadius * 1.6,
          child: _buildCenterSlot(total, colors, palette),
        ),
      ],
    );

    if (widget.legendBuilder == null) {
      return Semantics(
        label: widget.semanticLabel,
        container: true,
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: chartWidget,
        ),
      );
    }

    final legend =
        widget.legendBuilder!(context, widget.slices, colors, total);

    return Semantics(
      label: widget.semanticLabel,
      container: true,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Row(
          children: [
            Expanded(child: chartWidget),
            legend,
          ],
        ),
      ),
    );
  }

  Widget _buildCenterSlot(
    double total,
    List<Color> colors,
    ChartPalette palette,
  ) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    if (_highlightedIndex >= 0 &&
        _highlightedIndex < widget.slices.length) {
      final s = widget.slices[_highlightedIndex];
      final pct = (s.value / total) * 100;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatCompact(s.value),
            style: TypographyTokens.numericTitle.copyWith(
              color: onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            s.label,
            style: TypographyTokens.numericCaption.copyWith(
              color: onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${pct.toStringAsFixed(1)}%',
            style: TypographyTokens.numericCaption.copyWith(
              color: onSurface.withValues(alpha: 0.5),
              fontSize: 10,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatCompact(total),
          style: TypographyTokens.displaySmall.copyWith(
            color: onSurface,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          'Total',
          style: TypographyTokens.numericCaption.copyWith(
            color: onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  String _formatCompact(double value) {
    if (value >= 1e12) return '${(value / 1e12).toStringAsFixed(1)}T';
    if (value >= 1e9) return '${(value / 1e9).toStringAsFixed(1)}B';
    if (value >= 1e6) return '${(value / 1e6).toStringAsFixed(1)}M';
    if (value >= 1e3) return '${(value / 1e3).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }

  PieTouchData _buildTouchData() {
    return PieTouchData(
      enabled: true,
      touchCallback: (event, response) {
        if (event is FlTapUpEvent) {
          final dd = widget.drillDown;
          final idx =
              response?.touchedSection?.touchedSectionIndex ?? -1;
          if (idx < 0 || idx >= widget.slices.length) {
            setState(() => _highlightedIndex = -1);
            return;
          }
          if (dd is SliceDrillDown) {
            if (dd.haptic) HapticFeedback.selectionClick();
            dd.onTap(widget.slices[idx]);
          }
        }
        if (response?.touchedSection != null &&
            event is FlPanUpdateEvent) {
          setState(() {
            _highlightedIndex =
                response!.touchedSection!.touchedSectionIndex;
          });
        } else if (event is FlTapUpEvent || event is FlPanEndEvent) {
          setState(() => _highlightedIndex = -1);
        }
      },
    );
  }

  Color _onColor(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.5
        ? const Color(0xFF111827)
        : const Color(0xFFFFFFFF);
  }
}

/// A single row in the pie chart legend: color swatch + label + percentage
/// + colored underline accent.
class LegendRow extends StatelessWidget {
  const LegendRow({
    super.key,
    required this.color,
    required this.label,
    required this.percent,
    this.value,
    this.onTap,
  });

  final Color color;
  final String label;
  final double percent;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TypographyTokens.numericCaption.copyWith(
                      color: onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${percent.toStringAsFixed(1)}%',
                  style: TypographyTokens.numericCaption.copyWith(
                    color: onSurface.withValues(alpha: 0.6),
                    fontSize: 10,
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    value!,
                    style: TypographyTokens.numericCaption.copyWith(
                      color: onSurface.withValues(alpha: 0.8),
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Container(
              height: 2,
              width: double.infinity,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
