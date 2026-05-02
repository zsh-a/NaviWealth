import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design_system/tokens/typography_tokens.dart';

/// Half-donut progress gauge: 270° arc with the active sweep starting at
/// the bottom-left, traveling clockwise. Renders the percentage in the
/// centre and an optional caption underneath.
///
/// Pure paint — no Riverpod / l10n inside, so callers can drive it from
/// either the live dashboard view or a fixed value in widget tests.
class FireProgressGauge extends StatelessWidget {
  const FireProgressGauge({
    super.key,
    required this.progress,
    required this.centerLabel,
    this.caption,
    this.diameter = 200,
    this.strokeWidth = 16,
  });

  /// `0.0` … `1.0`. Values outside the range are clamped — passing `1.2`
  /// renders a full sweep (no overshoot ring).
  final double progress;

  /// Text rendered in the gauge centre, e.g. `"42%"`.
  final String centerLabel;

  /// Subtitle below the percentage, e.g. `"of FIRE target"`. Optional —
  /// when omitted only the percentage shows.
  final String? caption;

  final double diameter;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = progress.clamp(0.0, 1.0);
    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(diameter, diameter),
            painter: _GaugePainter(
              progress: clamped,
              strokeWidth: strokeWidth,
              trackColor: theme.colorScheme.surfaceContainerHigh,
              progressColor: theme.colorScheme.primary,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            // Cap text scaling inside the fixed-size gauge so 200% system
            // font doesn't overflow the donut hole.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      centerLabel,
                      style: TypographyTokens.numericTitle.copyWith(
                        fontSize: diameter * 0.18,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      caption!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.progress,
    required this.strokeWidth,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final double strokeWidth;
  final Color trackColor;
  final Color progressColor;

  // Sweep covers the bottom 270° — looks more like a "fuel gauge" than a
  // full ring and leaves room for the percent / caption block centred at
  // the bottom of the arc.
  static const double _startAngle = 0.75 * math.pi;
  static const double _sweepAngle = 1.5 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = trackColor;

    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = progressColor;

    canvas.drawArc(rect, _startAngle, _sweepAngle, false, track);
    if (progress > 0) {
      canvas.drawArc(rect, _startAngle, _sweepAngle * progress, false, fill);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor;
}
