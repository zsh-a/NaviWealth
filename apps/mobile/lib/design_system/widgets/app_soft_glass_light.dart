import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/component_specs.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

/// Paint-only enhancement used internally by [AppGlassSurface]. No gesture
/// recognizer, focus node, haptics, backdrop capture, or continuous ticker.
/// The surrounding glass surface owns clipping and accessibility fallback.
class AppSoftGlassLight extends StatefulWidget {
  const AppSoftGlassLight({
    super.key,
    required this.borderRadius,
    required this.child,
  });

  final BorderRadius borderRadius;
  final Widget child;

  @override
  State<AppSoftGlassLight> createState() => _AppSoftGlassLightState();
}

class _AppSoftGlassLightState extends State<AppSoftGlassLight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intensity = AnimationController(vsync: this);
  final ValueNotifier<Offset?> _position = ValueNotifier(null);
  late final Listenable _repaint = Listenable.merge([_intensity, _position]);
  int? _pointer;
  bool _enabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled =
        AppMotionPolicy.isEnabled(context, role: AppMotionRole.decorative) &&
        TickerMode.valuesOf(context).enabled;
    _intensity.duration = AppMotionPolicy.duration(
      context,
      Motion.tapFeedback,
      role: AppMotionRole.decorative,
    );
    _intensity.reverseDuration = AppMotionPolicy.duration(
      context,
      Motion.componentChange,
      role: AppMotionRole.decorative,
    );
    if (!_enabled) {
      _pointer = null;
      _intensity.value = 0;
      _position.value = null;
    }
  }

  void _down(PointerDownEvent event) {
    if (!mounted ||
        !_enabled ||
        _pointer != null ||
        event.buttons != kPrimaryButton) {
      return;
    }
    _pointer = event.pointer;
    _position.value = event.localPosition;
    _intensity.animateTo(1, curve: Motion.standardDecelerate);
  }

  void _move(PointerMoveEvent event) {
    if (!mounted || event.pointer != _pointer) return;
    final size = context.size;
    if (size == null || !(Offset.zero & size).contains(event.localPosition)) {
      if (_intensity.status != AnimationStatus.reverse &&
          _intensity.value != 0) {
        _intensity.animateBack(0, curve: Motion.standardAccelerate);
      }
      return;
    }
    _position.value = event.localPosition;
    if (_intensity.status != AnimationStatus.forward && _intensity.value != 1) {
      _intensity.animateTo(1, curve: Motion.standardDecelerate);
    }
  }

  void _end(PointerEvent event) {
    if (!mounted || event.pointer != _pointer) return;
    _pointer = null;
    _intensity.animateBack(0, curve: Motion.standardAccelerate);
  }

  @override
  void dispose() {
    // Flutter may still deliver the terminal event from a cached hit-test path
    // after a pointer-down action removes this route/surface.
    _pointer = null;
    _intensity.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Listener(
      onPointerDown: _enabled ? _down : null,
      onPointerMove: _enabled ? _move : null,
      onPointerUp: _enabled ? _end : null,
      onPointerCancel: _enabled ? _end : null,
      child: CustomPaint(
        painter: SoftGlassLightPainter(
          borderRadius: widget.borderRadius,
          brightness: colors.brightness,
          // Subtle neutral/brand mixture, never a market gain/loss color.
          lightColor: Color.lerp(
            ColorPalette.neutral0,
            colors.primary,
            AppOpacity.muted,
          )!,
          shadeColor: colors.foreground,
          intensity: _intensity,
          position: _position,
          repaint: _repaint,
        ),
        // Pointer updates invalidate only the light paint, not foreground UI.
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}

/// A background painter: foreground text/icons never pass through the light.
/// Exposed within this implementation file for focused paint-state tests.
class SoftGlassLightPainter extends CustomPainter {
  SoftGlassLightPainter({
    required this.borderRadius,
    required this.brightness,
    required this.lightColor,
    required this.shadeColor,
    required this.intensity,
    required this.position,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final BorderRadius borderRadius;
  final Brightness brightness;
  final Color lightColor;
  final Color shadeColor;
  final Animation<double> intensity;
  final ValueListenable<Offset?> position;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final shape = borderRadius.toRRect(rect).scaleRadii();
    const spec = kAppSoftGlassSpec;
    final transparent = lightColor.withValues(alpha: 0);

    canvas.drawRRect(
      shape,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.7, -1),
          radius: 1.5,
          colors: [
            lightColor.withValues(alpha: spec.washOpacity(brightness)),
            transparent,
          ],
        ).createShader(rect),
    );
    final point = position.value;
    if (point != null && intensity.value > 0) {
      final radius = math.min(spec.touchRadius, size.longestSide);
      canvas.drawRRect(
        shape,
        Paint()
          ..shader = RadialGradient(
            colors: [
              lightColor.withValues(
                alpha: spec.touchOpacity(brightness) * intensity.value,
              ),
              transparent,
            ],
          ).createShader(Rect.fromCircle(center: point, radius: radius)),
      );
    }
    canvas.drawRRect(
      shape.deflate(AppStroke.hairline / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppStroke.hairline
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            lightColor.withValues(alpha: spec.rimOpacity(brightness)),
            transparent,
            shadeColor.withValues(alpha: AppOpacity.faint),
          ],
          stops: const [0, 0.6, 1],
        ).createShader(rect),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(SoftGlassLightPainter oldDelegate) =>
      borderRadius != oldDelegate.borderRadius ||
      brightness != oldDelegate.brightness ||
      lightColor != oldDelegate.lightColor ||
      shadeColor != oldDelegate.shadeColor ||
      intensity != oldDelegate.intensity ||
      position != oldDelegate.position;
}
