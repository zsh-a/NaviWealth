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
    this.role = AppGlassRole.chrome,
    this.status = AppGlassStatus.idle,
    this.variants = const {},
    this.accentColor,
    this.ambient = true,
    this.trackPointer = true,
  });

  final BorderRadius borderRadius;
  final Widget child;
  final AppGlassRole role;
  final AppGlassStatus status;
  final Set<FTappableVariant> variants;
  final Color? accentColor;
  final bool ambient;
  final bool trackPointer;

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

  bool get _inactive =>
      widget.status == AppGlassStatus.busy ||
      widget.status == AppGlassStatus.disabled ||
      widget.variants.contains(FTappableVariant.disabled);

  @override
  void didUpdateWidget(AppSoftGlassLight oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePointerPolicy();
  }

  void _updatePointerPolicy() {
    _enabled =
        widget.trackPointer &&
        !_inactive &&
        AppMotionPolicy.isEnabled(context, role: AppMotionRole.decorative) &&
        TickerMode.valuesOf(context).enabled;
    if (!_enabled) {
      _pointer = null;
      _intensity.value = 0;
      _position.value = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updatePointerPolicy();
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
    const spec = kAppSoftGlassSpec;
    final disabled =
        widget.status == AppGlassStatus.disabled ||
        widget.variants.contains(FTappableVariant.disabled);
    final emphasis = disabled
        ? 0.0
        : widget.status == AppGlassStatus.busy
        ? spec.busyEmphasis
        : widget.status == AppGlassStatus.error
        ? spec.errorEmphasis
        : widget.variants.contains(FTappableVariant.pressed)
        ? spec.pressedEmphasis
        : widget.variants.contains(FTappableVariant.focused)
        ? spec.focusEmphasis
        : widget.variants.contains(FTappableVariant.selected)
        ? spec.selectedEmphasis +
              (widget.variants.contains(FTappableVariant.hovered)
                  ? spec.hoverEmphasis / 2
                  : 0)
        : widget.variants.contains(FTappableVariant.hovered)
        ? spec.hoverEmphasis
        : 0.0;
    return Listener(
      onPointerDown: _enabled ? _down : null,
      onPointerMove: _enabled ? _move : null,
      onPointerUp: _enabled ? _end : null,
      onPointerCancel: _enabled ? _end : null,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: emphasis),
        duration: TickerMode.valuesOf(context).enabled
            ? AppMotionPolicy.duration(
                context,
                Motion.tapFeedback,
                role: AppMotionRole.decorative,
              )
            : Duration.zero,
        curve: Motion.standardDecelerate,
        builder: (context, value, child) => CustomPaint(
          painter: SoftGlassLightPainter(
            borderRadius: widget.borderRadius,
            role: widget.role,
            brightness: colors.brightness,
            // Subtle neutral/brand mixture, never a market gain/loss color.
            lightColor: Color.lerp(
              ColorPalette.neutral0,
              colors.primary,
              AppOpacity.muted,
            )!,
            shadeColor: colors.foreground,
            stateColor: widget.status == AppGlassStatus.error
                ? colors.destructive
                : widget.accentColor ?? colors.primary,
            emphasis: value,
            ambient: widget.ambient ? (disabled ? spec.disabledWash : 1) : 0,
            intensity: _intensity,
            position: _position,
            repaint: _repaint,
          ),
          child: child,
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
    required this.role,
    required this.brightness,
    required this.lightColor,
    required this.shadeColor,
    required this.stateColor,
    required this.emphasis,
    required this.ambient,
    required this.intensity,
    required this.position,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final BorderRadius borderRadius;
  final AppGlassRole role;
  final Brightness brightness;
  final Color lightColor;
  final Color shadeColor;
  final Color stateColor;
  final double emphasis;
  final double ambient;
  final Animation<double> intensity;
  final ValueListenable<Offset?> position;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty ||
        (ambient == 0 && emphasis == 0 && intensity.value == 0)) {
      return;
    }
    final rect = Offset.zero & size;
    final shape = borderRadius.toRRect(rect).scaleRadii();
    const spec = kAppSoftGlassSpec;
    final transparent = lightColor.withValues(alpha: AppOpacity.transparent);

    canvas.drawRRect(
      shape,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.7, -1),
          radius: 1.5,
          colors: [
            lightColor.withValues(
              alpha: spec.washOpacity(brightness) * ambient,
            ),
            transparent,
          ],
        ).createShader(rect),
    );
    // A broad top-facing reflection makes the surface read as a thin
    // translucent material rather than a flat translucent fill.
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: const Alignment(-0.9, -1),
          end: const Alignment(0.9, 0.65),
          colors: [
            lightColor.withValues(
              alpha: spec.specularOpacity(brightness, role) * ambient,
            ),
            transparent,
            shadeColor.withValues(
              alpha: spec.occlusionOpacity(brightness, role) * ambient,
            ),
          ],
          stops: const [0, 0.42, 1],
        ).createShader(rect),
    );
    if (emphasis > 0) {
      canvas.drawRRect(
        shape,
        Paint()
          ..shader = RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            colors: [
              stateColor.withValues(
                alpha: spec.stateOpacity(brightness) * emphasis,
              ),
              stateColor.withValues(alpha: AppOpacity.transparent),
            ],
          ).createShader(rect),
      );
      canvas.drawRRect(
        shape.deflate(AppStroke.hairline / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = AppStroke.hairline
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              stateColor.withValues(alpha: spec.stateRimOpacity * emphasis),
              stateColor.withValues(alpha: AppOpacity.transparent),
            ],
          ).createShader(rect),
      );
    }
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
            lightColor.withValues(alpha: spec.rimOpacity(brightness) * ambient),
            transparent,
            shadeColor.withValues(
              alpha: spec.edgeShadeOpacity(brightness, role) * ambient,
            ),
          ],
          stops: const [0, 0.6, 1],
        ).createShader(rect),
    );
    // The second, inset rim is deliberately weaker and offset in the
    // opposite direction: this is the thin edge refraction cue used by
    // modern spatial glass surfaces.
    canvas.drawRRect(
      shape.deflate(AppStroke.hairline),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppStroke.hairline
        ..shader = LinearGradient(
          begin: Alignment.bottomRight,
          end: Alignment.topLeft,
          colors: [
            shadeColor.withValues(
              alpha: spec.edgeShadeOpacity(brightness, role) * 0.55 * ambient,
            ),
            transparent,
            lightColor.withValues(
              alpha: spec.edgeHighlightOpacity(brightness, role) * ambient,
            ),
          ],
          stops: const [0, 0.56, 1],
        ).createShader(rect),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(SoftGlassLightPainter oldDelegate) =>
      borderRadius != oldDelegate.borderRadius ||
      role != oldDelegate.role ||
      brightness != oldDelegate.brightness ||
      lightColor != oldDelegate.lightColor ||
      shadeColor != oldDelegate.shadeColor ||
      stateColor != oldDelegate.stateColor ||
      emphasis != oldDelegate.emphasis ||
      ambient != oldDelegate.ambient ||
      intensity != oldDelegate.intensity ||
      position != oldDelegate.position;
}
