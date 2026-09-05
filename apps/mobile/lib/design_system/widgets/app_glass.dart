import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../theme/component_specs.dart';
import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';

/// The single source for the app's "glass" chrome tone (blueprint §6.3).
///
/// The fill derives from the resolved card surface, so OLED and high-contrast
/// surface styles carry through automatically. Use [AppGlassSurface] for
/// actual frosted chrome; this helper remains useful when callers only need
/// the shared material decoration without owning the blur layer.
BoxDecoration appGlassDecoration(
  BuildContext context, {
  AppGlassRole role = AppGlassRole.chrome,
  BorderRadius? borderRadius,
  List<BoxShadow>? boxShadow,
  bool frosted = true,
}) {
  final colors = context.theme.colors;
  final isDark = colors.brightness == Brightness.dark;
  final surfaces = context.appTheme.surfaces;
  final material = context.appTheme.glass.resolve(role);
  final base = switch (role) {
    AppGlassRole.chrome ||
    AppGlassRole.sticky => isDark ? surfaces.card : ColorPalette.neutral0,
    AppGlassRole.sheet || AppGlassRole.overlay => surfaces.raised,
  };
  final glassColor = base.withValues(
    alpha: frosted ? material.fillOpacity : AppOpacity.opaque,
  );
  final borderColor = isDark
      ? colors.border.withValues(alpha: material.borderOpacity)
      : ColorPalette.navySoftBorder.withValues(alpha: material.borderOpacity);
  return BoxDecoration(
    color: glassColor,
    borderRadius: borderRadius,
    gradient:
        frosted && (role == AppGlassRole.chrome || role == AppGlassRole.sticky)
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                ColorPalette.neutral0.withValues(alpha: AppOpacity.whisper),
                glassColor,
              ),
              glassColor,
            ],
          )
        : null,
    border: Border.all(color: borderColor, width: AppStroke.hairline),
    boxShadow: boxShadow,
  );
}

/// Canonical live glass surface for floating and pinned application chrome.
///
/// Blur is intentionally centralized here so navigation, sticky summaries,
/// sheets, and pinned actions share one compositing strategy. Content cards
/// should continue to use [SoftCard]-style opaque surfaces; glass is reserved
/// for layers that sit above moving content.
class AppGlassSurface extends StatelessWidget {
  const AppGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.role = AppGlassRole.chrome,
    this.frosted = true,
    this.boxShadow,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final AppGlassRole role;

  /// Allows rendering-heavy callers to keep the same material hierarchy
  /// while replacing live blur with an opaque surface.
  final bool frosted;
  final List<BoxShadow>? boxShadow;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final material = context.appTheme.glass.resolve(role);
    final platformHighContrast =
        MediaQuery.maybeOf(context)?.highContrast ?? false;
    final liveBlur = frosted && material.liveBlur && !platformHighContrast;
    final decoration = appGlassDecoration(
      context,
      role: role,
      borderRadius: borderRadius,
      frosted: liveBlur,
    );
    final contents = DecoratedBox(
      decoration: decoration,
      child: Padding(padding: padding, child: child),
    );
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: boxShadow,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: liveBlur
              ? BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: material.blurSigma,
                    sigmaY: material.blurSigma,
                  ),
                  child: contents,
                )
              : contents,
        ),
      ),
    );
  }
}
