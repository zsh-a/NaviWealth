import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/component_specs.dart';
import '../tokens/dimens_tokens.dart';
import 'app_glass_environment.dart';

/// Static material lighting beneath glass chrome. The owning surface handles
/// clipping and accessibility fallback; controls own their normal feedback.
class AppSoftGlassLight extends StatelessWidget {
  const AppSoftGlassLight({
    super.key,
    required this.borderRadius,
    required this.child,
    this.role = AppGlassRole.chrome,
  });

  final BorderRadius borderRadius;
  final Widget child;
  final AppGlassRole role;

  @override
  Widget build(BuildContext context) {
    final field = AppGlassEnvironment.of(context);
    return CustomPaint(
      painter: SoftGlassLightPainter(
        borderRadius: borderRadius,
        role: role,
        brightness: context.theme.colors.brightness,
        lightColor: field.lightColor,
        shadeColor: field.shadeColor,
        lightOrigin: field.origin,
        energy: field.energy,
      ),
      child: RepaintBoundary(child: child),
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
  });

  final BorderRadius borderRadius;
  final AppGlassRole role;
  final Brightness brightness;
  final Color lightColor;
  final Color shadeColor;
  final Alignment lightOrigin;
  final double energy;

  @override
  void paint(Canvas canvas, Size size) {
    final materialEnergy = energy.clamp(0.0, 1.0);
    if (size.isEmpty || materialEnergy == 0) {
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
      energy != oldDelegate.energy;
}
