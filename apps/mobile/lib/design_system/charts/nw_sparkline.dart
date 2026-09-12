import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/dimens_tokens.dart';

/// A bare trend line for dense list rows.
///
/// Unlike `NwLineChart` this draws no axes, labels, grid, or touch targets. It
/// exists so one row can answer "which way has this been going lately" in about
/// fifty logical pixels. Colour follows the same market tone as `DeltaText`, so
/// a user who flipped to the colorblind palette gets the same mapping here.
///
/// The dashed hairline sits at the window's opening value: the line's position
/// relative to it *is* the story, which is why no y-axis is needed.
class NwSparkline extends StatelessWidget {
  const NwSparkline({
    super.key,
    required this.values,
    this.width = 52,
    this.height = 26,
    this.showBaseline = true,
  });

  /// Closing prices, oldest first. Fewer than two points renders nothing.
  final List<double> values;

  final double width;
  final double height;
  final bool showBaseline;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox.shrink();
    final market = context.appTheme.market;
    final colors = context.theme.colors;
    final delta = values.last - values.first;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          color: delta == 0 ? colors.mutedForeground : market.roleForDelta(delta).fg,
          baselineColor: colors.border,
          showBaseline: showBaseline,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.values,
    required this.color,
    required this.baselineColor,
    required this.showBaseline,
  });

  final List<double> values;
  final Color color;
  final Color baselineColor;
  final bool showBaseline;

  /// Keeps the extremes off the exact top/bottom edge so the stroke is never
  /// clipped in half.
  static const double _verticalInset = 2;

  @override
  void paint(Canvas canvas, Size size) {
    var low = values.first;
    var high = values.first;
    for (final value in values) {
      low = math.min(low, value);
      high = math.max(high, value);
    }
    final range = high - low;
    final usableHeight = math.max(size.height - _verticalInset * 2, 1);
    double yOf(double value) => range == 0
        ? size.height / 2
        : _verticalInset + usableHeight * (1 - (value - low) / range);
    double xOf(int index) => size.width * index / (values.length - 1);

    if (showBaseline && range != 0) {
      _paintDashedBaseline(canvas, size, yOf(values.first));
    }

    final path = Path()..moveTo(xOf(0), yOf(values.first));
    for (var index = 1; index < values.length; index++) {
      path.lineTo(xOf(index), yOf(values[index]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppStroke.sparkline
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintDashedBaseline(Canvas canvas, Size size, double y) {
    final paint = Paint()
      ..color = baselineColor.withValues(alpha: AppOpacity.highlight)
      ..strokeWidth = AppStroke.hairline;
    const dash = 2.0;
    const gap = 3.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dash, size.width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.baselineColor != baselineColor ||
      oldDelegate.showBaseline != showBaseline ||
      !listEquals(oldDelegate.values, values);
}
