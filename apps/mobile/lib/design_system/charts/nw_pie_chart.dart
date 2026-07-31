import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';
import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';
import '../widgets/app_tappable.dart';
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
  )?
  legendBuilder;

  @override
  State<NwPieChart> createState() => _NwPieChartState();
}

class _NwPieChartState extends State<NwPieChart> {
  int _highlightedIndex = -1;

  // Cache NumberFormat — constructing it is expensive and unnecessary
  // on every frame during touch drag.
  static final NumberFormat _compactFormat = NumberFormat.compact();

  @override
  Widget build(BuildContext context) {
    if (widget.slices.isEmpty) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: const EmptyChartPlaceholder(icon: FLucideIcons.chartPie),
      );
    }
    final palette = ChartPalette.of(context);
    final total = widget.slices.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: const EmptyChartPlaceholder(icon: FLucideIcons.chartPie),
      );
    }

    final colors = <Color>[
      for (var i = 0; i < widget.slices.length; i++)
        widget.slices[i].colorOverride ?? palette.accentAt(i),
    ];

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < widget.slices.length; i++) {
      final s = widget.slices[i];
      final clampedValue = s.value < 0 ? 0.0 : s.value;
      final pct = (clampedValue / total) * 100;
      final color = colors[i];
      final isHighlighted = _highlightedIndex == i;
      sections.add(
        PieChartSectionData(
          value: clampedValue,
          color: color,
          radius: isHighlighted ? 64 : 56,
          title: pct >= widget.minLabelPercent
              ? '${pct.toStringAsFixed(0)}%'
              : '',
          titleStyle: TypographyTokens.numericCaption.copyWith(
            color: _onColor(color),
          ),
        ),
      );
    }

    final centerRadius = widget.hole * 80;

    final pieChart = RepaintBoundary(
      child: PieChart(
        PieChartData(
          sections: sections,
          centerSpaceRadius: centerRadius,
          sectionsSpace: 3,
          pieTouchData: _buildTouchData(),
        ),
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

    final legend = widget.legendBuilder?.call(
      context,
      widget.slices,
      colors,
      total,
    );
    final content = AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: legend == null
          ? chartWidget
          : Row(
              children: [
                Expanded(child: chartWidget),
                legend,
              ],
            ),
    );
    return Semantics(
      label: _resolvedSemanticLabel(total),
      container: true,
      onIncrease: () => _moveHighlight(1),
      onDecrease: () => _moveHighlight(-1),
      child: Focus(onKeyEvent: _handleKeyEvent, child: content),
    );
  }

  void _moveHighlight(int delta) {
    if (widget.slices.isEmpty) return;
    final base = _highlightedIndex < 0
        ? (delta < 0 ? widget.slices.length - 1 : 0)
        : _highlightedIndex;
    setState(() {
      _highlightedIndex = (base + delta).clamp(0, widget.slices.length - 1);
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _highlightedIndex = -1);
      return KeyEventResult.handled;
    }
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) &&
        _highlightedIndex >= 0 &&
        widget.drillDown is SliceDrillDown) {
      (widget.drillDown! as SliceDrillDown).onTap(
        widget.slices[_highlightedIndex],
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _resolvedSemanticLabel(double total) {
    final supplied = widget.semanticLabel?.trim();
    if (supplied != null && supplied.isNotEmpty) return supplied;
    return widget.slices
        .map((slice) {
          final percent = total <= 0 ? 0 : (slice.value / total) * 100;
          return '${slice.label}: ${percent.toStringAsFixed(1)}%';
        })
        .join(', ');
  }

  Widget _buildCenterSlot(
    double total,
    List<Color> colors,
    ChartPalette palette,
  ) {
    final onSurface = context.theme.colors.foreground;

    if (_highlightedIndex >= 0 && _highlightedIndex < widget.slices.length) {
      final s = widget.slices[_highlightedIndex];
      final pct = (s.value / total) * 100;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatCompact(s.value),
            style: TypographyTokens.numericTitle.copyWith(color: onSurface),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            s.label,
            style: TypographyTokens.numericCaption.copyWith(
              color: onSurface.withValues(alpha: AppOpacity.strong),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${pct.toStringAsFixed(1)}%',
            style: TypographyTokens.chartCaption.copyWith(
              color: onSurface.withValues(alpha: AppOpacity.scrim),
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
          style: TypographyTokens.displaySmall.copyWith(color: onSurface),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          AppLocalizations.of(context).chartTotalLabel,
          style: TypographyTokens.numericCaption.copyWith(
            color: onSurface.withValues(alpha: AppOpacity.scrim),
          ),
        ),
      ],
    );
  }

  String _formatCompact(double value) => _compactFormat.format(value);

  PieTouchData _buildTouchData() {
    return PieTouchData(
      enabled: true,
      touchCallback: (event, response) {
        if (event is FlTapUpEvent) {
          final dd = widget.drillDown;
          final idx = response?.touchedSection?.touchedSectionIndex ?? -1;
          if (idx < 0 || idx >= widget.slices.length) {
            setState(() => _highlightedIndex = -1);
            return;
          }
          if (dd is SliceDrillDown) {
            if (dd.haptic) HapticFeedback.selectionClick();
            dd.onTap(widget.slices[idx]);
          }
        }
        if (response?.touchedSection != null && event is FlPanUpdateEvent) {
          setState(() {
            _highlightedIndex = response!.touchedSection!.touchedSectionIndex;
          });
        } else if (event is FlTapUpEvent || event is FlPanEndEvent) {
          setState(() => _highlightedIndex = -1);
        }
      },
    );
  }

  Color _onColor(Color background) {
    final luminance = background.computeLuminance();
    return luminance > 0.5 ? ColorPalette.neutral900 : ColorPalette.neutral0;
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
    final onSurface = context.theme.colors.foreground;
    return AppTappable(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.accentBar),
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
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                const SizedBox(width: AppSpacing.s6),
                Flexible(
                  child: Text(
                    label,
                    style: TypographyTokens.numericCaption.copyWith(
                      color: onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.s4),
                Text(
                  '${percent.toStringAsFixed(1)}%',
                  style: TypographyTokens.chartCaption.copyWith(
                    color: onSurface.withValues(alpha: AppOpacity.prominent),
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: AppSpacing.s4),
                  Text(
                    value!,
                    style: TypographyTokens.chartCaption.copyWith(
                      color: onSurface.withValues(alpha: AppOpacity.emphasis),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.s2),
            Container(
              height: AppStroke.branch,
              width: double.infinity,
              decoration: BoxDecoration(
                color: color.withValues(alpha: AppOpacity.disabled),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
