import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/component_specs.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import 'app_glass_environment.dart';

/// Paint-only enhancement used internally by [AppGlassSurface]. It does not
/// own a gesture recognizer, focus node, haptics, or backdrop capture. The
/// surface samples the pointer only to place a small, reversible light flow;
/// the surrounding glass surface owns clipping and accessibility fallback.
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
  final ValueNotifier<Offset> _velocity = ValueNotifier(Offset.zero);
  late final Listenable _repaint = Listenable.merge([
    _intensity,
    _position,
    _velocity,
  ]);
  int? _pointer;
  Duration? _lastPointerTime;
  bool _pointerInside = false;
  bool _hovering = false;
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
      _lastPointerTime = null;
      _pointerInside = false;
      _hovering = false;
      _intensity.value = 0;
      _position.value = null;
      _velocity.value = Offset.zero;
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
    if (!mounted || !_enabled || _pointer != null) {
      return;
    }
    if (event.buttons != kPrimaryButton) {
      _pointerInside = false;
      _hovering = false;
      _velocity.value = Offset.zero;
      _intensity.animateBack(0, curve: Motion.standardAccelerate);
      return;
    }
    _pointer = event.pointer;
    _lastPointerTime = event.timeStamp;
    _pointerInside = _isInside(event.localPosition);
    _position.value = event.localPosition;
    _velocity.value = Offset.zero;
    _intensity.animateTo(1, curve: Motion.standardDecelerate);
  }

  void _setHover(Offset position) {
    if (!mounted || !_enabled) return;
    _pointerInside = true;
    _hovering = true;
    _position.value = position;
    _velocity.value = Offset.zero;
    // While a primary pointer is held, the drag path owns intensity. The
    // hover callback still records re-entry so release can settle to the
    // quieter hover level instead of extinguishing unexpectedly.
    if (_pointer != null) return;
    if (_intensity.status != AnimationStatus.forward &&
        _intensity.value < kAppSoftGlassSpec.pointerHoverIntensity) {
      _intensity.animateTo(
        kAppSoftGlassSpec.pointerHoverIntensity,
        duration: _intensity.duration,
        curve: Motion.standardDecelerate,
      );
    }
  }

  void _enter(PointerEnterEvent event) => _setHover(event.localPosition);

  void _hover(PointerHoverEvent event) => _setHover(event.localPosition);

  void _exit(PointerExitEvent event) {
    if (!mounted || !_enabled) return;
    _pointerInside = false;
    _hovering = false;
    if (_pointer == null) {
      _intensity.animateBack(0, curve: Motion.standardAccelerate);
    }
  }

  void _move(PointerMoveEvent event) {
    if (!mounted || event.pointer != _pointer) return;
    _updateVelocity(event);
    _pointerInside = _isInside(event.localPosition);
    if (!_pointerInside) {
      _hovering = false;
      if (_intensity.status != AnimationStatus.reverse &&
          _intensity.value != 0) {
        _intensity.animateBack(0, curve: Motion.standardAccelerate);
      }
      return;
    }
    if (_intensity.status != AnimationStatus.forward && _intensity.value != 1) {
      _intensity.animateTo(1, curve: Motion.standardDecelerate);
    }
  }

  void _end(PointerEvent event) {
    if (!mounted || event.pointer != _pointer) return;
    _pointer = null;
    _lastPointerTime = null;
    if (_hovering && _pointerInside) {
      _velocity.value = Offset.zero;
      _intensity.animateTo(
        kAppSoftGlassSpec.pointerHoverIntensity,
        curve: Motion.standardDecelerate,
      );
    } else {
      _intensity.animateBack(0, curve: Motion.standardAccelerate);
    }
  }

  bool _isInside(Offset position) {
    final size = context.size;
    return size != null && (Offset.zero & size).contains(position);
  }

  void _updateVelocity(PointerMoveEvent event) {
    final previous = _position.value;
    final previousTime = _lastPointerTime;
    final elapsed = previousTime == null
        ? Duration.zero
        : event.timeStamp - previousTime;
    final delta = previous == null
        ? event.delta
        : event.localPosition - previous;
    if (delta.distanceSquared > 0) {
      // Test bindings and a few platform pointer sources can coalesce moves
      // with the same timestamp. Keep the flow responsive with a one-frame
      // fallback instead of dropping the directional signal entirely.
      final seconds = elapsed > Duration.zero
          ? elapsed.inMicroseconds / Duration.microsecondsPerSecond
          : 1 / 60;
      final instantaneous = Offset(delta.dx / seconds, delta.dy / seconds);
      _velocity.value =
          Offset.lerp(
            _velocity.value,
            instantaneous,
            instantaneous.distance == 0 ? 0.18 : 0.34,
          ) ??
          instantaneous;
    }
    _position.value = event.localPosition;
    _lastPointerTime = event.timeStamp;
  }

  @override
  void dispose() {
    // Flutter may still deliver the terminal event from a cached hit-test path
    // after a pointer-down action removes this route/surface.
    _pointer = null;
    _lastPointerTime = null;
    _pointerInside = false;
    _hovering = false;
    _intensity.dispose();
    _position.dispose();
    _velocity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    const spec = kAppSoftGlassSpec;
    final field = AppGlassEnvironment.of(context);
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
    final listener = Listener(
      behavior: HitTestBehavior.translucent,
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
            lightColor: field.lightColor,
            shadeColor: field.shadeColor,
            lightOrigin: field.origin,
            energy: field.energy,
            stateColor: widget.status == AppGlassStatus.error
                ? colors.destructive
                : widget.accentColor ?? colors.primary,
            emphasis: value,
            ambient: widget.ambient ? (disabled ? spec.disabledWash : 1) : 0,
            intensity: _intensity,
            position: _position,
            velocity: _velocity,
            repaint: _repaint,
          ),
          child: child,
        ),
        // Pointer updates invalidate only the light paint, not foreground UI.
        child: RepaintBoundary(child: widget.child),
      ),
    );
    if (!_enabled) return listener;
    return MouseRegion(
      onEnter: _enter,
      onHover: _hover,
      onExit: _exit,
      child: listener,
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
    required this.lightOrigin,
    required this.energy,
    required this.stateColor,
    required this.emphasis,
    required this.ambient,
    required this.intensity,
    required this.position,
    required this.velocity,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final BorderRadius borderRadius;
  final AppGlassRole role;
  final Brightness brightness;
  final Color lightColor;
  final Color shadeColor;
  final Alignment lightOrigin;
  final double energy;
  final Color stateColor;
  final double emphasis;
  final double ambient;
  final Animation<double> intensity;
  final ValueListenable<Offset?> position;
  final ValueListenable<Offset> velocity;

  @override
  void paint(Canvas canvas, Size size) {
    final fieldEnergy = energy.clamp(0.0, 1.0);
    final materialEnergy = ambient * fieldEnergy;
    if (size.isEmpty ||
        (materialEnergy == 0 && emphasis == 0 && intensity.value == 0)) {
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
          center: lightOrigin,
          radius: 1.5,
          colors: [
            lightColor.withValues(
              alpha: spec.washOpacity(brightness) * materialEnergy,
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
          begin: lightOrigin,
          end: const Alignment(0.9, 0.65),
          colors: [
            lightColor.withValues(
              alpha: spec.specularOpacity(brightness, role) * materialEnergy,
            ),
            transparent,
            shadeColor.withValues(
              alpha: spec.occlusionOpacity(brightness, role) * materialEnergy,
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
            center: lightOrigin,
            radius: 1.2,
            colors: [
              stateColor.withValues(
                alpha: spec.stateOpacity(brightness) * emphasis,
              ),
              stateColor.withValues(alpha: AppOpacity.transparent),
            ],
          ).createShader(rect),
      );
    }
    final point = position.value;
    if (point != null && intensity.value > 0) {
      final pointerVelocity = velocity.value;
      final speed = pointerVelocity.distance;
      final speedRatio = (speed / spec.pointerSpeedForMax).clamp(0.0, 1.0);
      final flowColor = Color.lerp(
        lightColor,
        stateColor,
        spec.pointerColorMix(brightness),
      )!;
      final flowTransparent = flowColor.withValues(
        alpha: AppOpacity.transparent,
      );
      final radius = math.min(
        spec.touchRadius * (1 + speedRatio * 0.18),
        role == AppGlassRole.chrome
            ? size.shortestSide * 0.92
            : size.shortestSide * 1.18,
      );

      canvas.save();
      canvas.clipRRect(shape);
      if (speed > 0.01) {
        final direction = Offset(
          pointerVelocity.dx / speed,
          pointerVelocity.dy / speed,
        );
        final trailLength = math.min(
          spec.pointerTrailLength,
          spec.touchRadius * (0.5 + speedRatio * 0.875),
        );
        final trailWidth = math.min(
          spec.pointerTrailWidth * (0.72 + speedRatio * 0.28),
          size.shortestSide * 0.62,
        );
        final trailCenter = point - direction * (trailLength * 0.30);
        final angle = math.atan2(direction.dy, direction.dx);
        canvas.save();
        canvas.translate(trailCenter.dx, trailCenter.dy);
        canvas.rotate(angle);
        final localTrailRect = Rect.fromCenter(
          center: Offset.zero,
          width: trailLength,
          height: trailWidth,
        );
        canvas.drawOval(
          localTrailRect,
          Paint()
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
            ..shader = RadialGradient(
              center: const Alignment(0.42, 0),
              radius: 1,
              colors: [
                flowColor.withValues(
                  alpha:
                      spec.pointerTrailOpacity(brightness) *
                      intensity.value *
                      speedRatio,
                ),
                flowColor.withValues(
                  alpha:
                      spec.pointerTrailOpacity(brightness) *
                      intensity.value *
                      speedRatio *
                      0.38,
                ),
                flowTransparent,
              ],
              stops: const [0, 0.48, 1],
            ).createShader(localTrailRect),
        );
        canvas.restore();

        final glintCenter = point + direction * (radius * 0.18);
        canvas.drawCircle(
          glintCenter,
          radius * 0.16,
          Paint()
            ..shader =
                RadialGradient(
                  colors: [
                    flowColor.withValues(
                      alpha:
                          spec.pointerSpecularOpacity(brightness) *
                          intensity.value *
                          speedRatio,
                    ),
                    flowTransparent,
                  ],
                ).createShader(
                  Rect.fromCircle(center: glintCenter, radius: radius * 0.16),
                ),
        );
      }

      canvas.drawRRect(
        shape,
        Paint()
          ..shader = RadialGradient(
            colors: [
              flowColor.withValues(
                alpha: spec.touchOpacity(brightness) * intensity.value,
              ),
              flowColor.withValues(
                alpha: spec.touchOpacity(brightness) * intensity.value * 0.34,
              ),
              flowTransparent,
            ],
            stops: const [0, 0.5, 1],
          ).createShader(Rect.fromCircle(center: point, radius: radius)),
      );
      canvas.restore();
    }
    canvas.drawRRect(
      shape.deflate(AppStroke.hairline / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AppStroke.hairline
        ..shader = LinearGradient(
          begin: lightOrigin,
          end: Alignment.bottomRight,
          colors: [
            lightColor.withValues(
              alpha: spec.rimOpacity(brightness) * materialEnergy,
            ),
            transparent,
            shadeColor.withValues(
              alpha: spec.edgeShadeOpacity(brightness, role) * materialEnergy,
            ),
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
      role != oldDelegate.role ||
      brightness != oldDelegate.brightness ||
      lightColor != oldDelegate.lightColor ||
      shadeColor != oldDelegate.shadeColor ||
      lightOrigin != oldDelegate.lightOrigin ||
      energy != oldDelegate.energy ||
      stateColor != oldDelegate.stateColor ||
      emphasis != oldDelegate.emphasis ||
      ambient != oldDelegate.ambient ||
      intensity != oldDelegate.intensity ||
      position != oldDelegate.position ||
      velocity != oldDelegate.velocity;
}
