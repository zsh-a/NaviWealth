import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';

/// The single source for the app's "glass" chrome tone (blueprint §6.3).
///
/// Deliberately NOT a `BackdropFilter`: a live backdrop blur must resample
/// the routed page while it changes and was a major raster cost during tab
/// navigation. A translucent tonal fill + soft border reads as glass at a
/// fraction of the cost. Consumed by the floating nav dock, the sticky
/// collapsed-summary bar and the desktop sidebar so the same navigation
/// material appears at every width.
///
/// The fill derives from the resolved card surface, so OLED / high-contrast
/// surface styles carry through automatically.
BoxDecoration appGlassDecoration(
  BuildContext context, {
  BorderRadius? borderRadius,
  List<BoxShadow>? boxShadow,
}) {
  final colors = context.theme.colors;
  final isDark = colors.brightness == Brightness.dark;
  final surfaces = context.appTheme.surfaces;
  final glassColor = isDark
      ? surfaces.card.withValues(alpha: AppOpacity.emphasis)
      : ColorPalette.neutral0.withValues(alpha: AppOpacity.nearOpaque);
  final borderColor = isDark
      ? colors.border.withValues(alpha: AppOpacity.emphasis)
      : ColorPalette.navySoftBorder.withValues(alpha: AppOpacity.strong);
  return BoxDecoration(
    color: glassColor,
    borderRadius: borderRadius,
    border: Border.all(color: borderColor, width: AppStroke.hairline),
    boxShadow: boxShadow,
  );
}

/// Opaque variant for full-height panels (desktop sidebar): the glass tone
/// pre-blended onto the canvas, avoiding translucent overdraw on a surface
/// that never has content behind it.
Color appGlassPanelColor(BuildContext context) {
  final colors = context.theme.colors;
  final isDark = colors.brightness == Brightness.dark;
  final surfaces = context.appTheme.surfaces;
  return isDark
      ? Color.alphaBlend(
          surfaces.card.withValues(alpha: AppOpacity.emphasis),
          surfaces.canvas,
        )
      : Color.alphaBlend(
          ColorPalette.neutral0.withValues(alpha: AppOpacity.nearOpaque),
          surfaces.canvas,
        );
}
