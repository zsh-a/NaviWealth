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
/// Pass [hole] = 0.6 for a donut; 0 for a solid pie. Slices smaller than
/// `<minLabelPercent>` of the total are not annotated to avoid label
/// collisions; their value still appears in the tooltip.
class NwPieChart extends StatefulWidget {
  const NwPieChart({
    super.key,
    required this.slices,
    this.hole = 0.6,
    this.aspectRatio = 1,
    this.drillDown,
    this.minLabelPercent = 5,
    this.semanticLabel,
  });

  final List<Slice> slices;
  final double hole;
  final double aspectRatio;
  final ChartDrillDown? drillDown;

  /// Slices with a percentage below this threshold render without a label
  /// inside the slice (their value still shows in the tooltip on tap).
  final double minLabelPercent;

  final String? semanticLabel;

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

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < widget.slices.length; i++) {
      final s = widget.slices[i];
      final pct = (s.value / total) * 100;
      final color = s.colorOverride ?? palette.accentAt(i);
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

    return Semantics(
      label: widget.semanticLabel,
      container: true,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: PieChart(
          PieChartData(
            sections: sections,
            centerSpaceRadius: widget.hole * 80,
            sectionsSpace: 2,
            pieTouchData: _buildTouchData(),
          ),
        ),
      ),
    );
  }

  PieTouchData _buildTouchData() {
    return PieTouchData(
      enabled: true,
      touchCallback: (event, response) {
        if (event is FlTapUpEvent) {
          final dd = widget.drillDown;
          final idx = response?.touchedSection?.touchedSectionIndex ?? -1;
          if (idx < 0 || idx >= widget.slices.length) return;
          if (dd is SliceDrillDown) {
            if (dd.haptic) HapticFeedback.selectionClick();
            dd.onTap(widget.slices[idx]);
          }
        }
        if (response?.touchedSection != null && event is FlPanUpdateEvent) {
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
    return luminance > 0.5 ? const Color(0xFF111827) : const Color(0xFFFFFFFF);
  }
}
