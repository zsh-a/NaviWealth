import 'dart:ui' as ui show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

/// A restrained success celebration: a checkmark that draws itself in while
/// the mark settles with a gentle spring.
///
/// Built as a self-painted replacement for a Lottie-style success asset so
/// the app keeps zero animation dependencies. Both the draw-in
/// ([Motion.slow] + [Motion.standardDecelerate]) and the scale-in
/// ([Motion.springGentle]) are decorative-role motion: under reduce-motion
/// the check renders fully drawn at rest, matching AppMotionPolicy.
///
/// Use [AppSuccessCelebration.static] in tests (or anywhere a ticker is
/// undesirable) to always render the finished check.
class AppSuccessCelebration extends StatefulWidget {
  const AppSuccessCelebration({
    super.key,
    this.size = AppIconSizes.lg,
    this.color,
  }) : _animated = true;

  /// Static variant — always renders the fully drawn check with no tickers.
  const AppSuccessCelebration.static({
    super.key,
    this.size = AppIconSizes.lg,
    this.color,
  }) : _animated = false;

  /// Edge length of the square the check is drawn in.
  final double size;

  /// Check stroke color. Defaults to the theme success foreground.
  final Color? color;

  final bool _animated;

  @override
  State<AppSuccessCelebration> createState() => _AppSuccessCelebrationState();
}

class _AppSuccessCelebrationState extends State<AppSuccessCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    duration: Motion.slow,
    vsync: this,
  );

  // Unbounded so the entrance spring can overshoot 1 without clamping.
  late final AnimationController _scale = AnimationController.unbounded(
    value: 0.8,
    vsync: this,
  );

  bool _started = false;
  late final Animation<double> _drawProgress = CurvedAnimation(
    parent: _draw,
    curve: Motion.standardDecelerate,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled =
        widget._animated &&
        AppMotionPolicy.isEnabled(context, role: AppMotionRole.decorative);
    if (enabled && !_started) {
      _started = true;
      _draw.forward();
      _scale.animateWithSpring(Motion.springGentle, 1, velocity: 0);
    } else if (!enabled) {
      _snapToFinal();
    }
  }

  void _snapToFinal() {
    _draw
      ..stop()
      ..value = 1;
    _scale
      ..stop()
      ..value = 1;
  }

  @override
  void dispose() {
    _draw.dispose();
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.appTheme.status.success.fg;
    return AnimatedBuilder(
      animation: Listenable.merge([_draw, _scale]),
      builder: (context, child) {
        return Transform.scale(
          scale: _scale.value,
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _CheckmarkPainter(
              progress: _drawProgress.value,
              color: color,
              strokeWidth: widget.size * 0.12,
            ),
          ),
        );
      },
    );
  }
}

class _CheckmarkPainter extends CustomPainter {
  const _CheckmarkPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  /// 0 → nothing drawn, 1 → full check.
  final double progress;
  final Color color;
  final double strokeWidth;

  // Short leg draws over the first 45% of progress; the long leg overlaps
  // slightly (from 40%) so the corner never visibly pauses.
  static const double _firstLegEnd = 0.45;
  static const double _secondLegStart = 0.4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final start = Offset(size.width * 0.22, size.height * 0.54);
    final corner = Offset(size.width * 0.44, size.height * 0.74);
    final end = Offset(size.width * 0.78, size.height * 0.3);

    final firstLeg = (progress / _firstLegEnd).clamp(0.0, 1.0);
    final secondLeg = ((progress - _secondLegStart) / (1 - _secondLegStart))
        .clamp(0.0, 1.0);

    final path = Path();
    if (firstLeg > 0) {
      path
        ..moveTo(start.dx, start.dy)
        ..lineTo(
          ui.lerpDouble(start.dx, corner.dx, firstLeg)!,
          ui.lerpDouble(start.dy, corner.dy, firstLeg)!,
        );
    }
    if (secondLeg > 0) {
      path
        ..moveTo(corner.dx, corner.dy)
        ..lineTo(
          ui.lerpDouble(corner.dx, end.dx, secondLeg)!,
          ui.lerpDouble(corner.dy, end.dy, secondLeg)!,
        );
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckmarkPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
