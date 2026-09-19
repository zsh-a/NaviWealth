import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../theme/component_specs.dart';
import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import 'app_soft_glass_light.dart';

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
  bool softLight = false,
}) {
  final colors = context.theme.colors;
  final isDark = colors.brightness == Brightness.dark;
  final surfaces = context.appTheme.surfaces;
  final material = context.appTheme.glass.resolve(role);
  final useSoftLight =
      softLight &&
      material.liveBlur &&
      !(MediaQuery.maybeOf(context)?.highContrast ?? false);
  final base = switch (role) {
    AppGlassRole.chrome ||
    AppGlassRole.sticky => isDark ? surfaces.card : ColorPalette.neutral0,
    AppGlassRole.sheet || AppGlassRole.overlay => surfaces.raised,
  };
  final glassColor = base.withValues(
    alpha: !frosted
        ? AppOpacity.opaque
        : useSoftLight && role == AppGlassRole.chrome
        ? kAppSoftGlassSpec.chromeFillOpacity(colors.brightness)
        : material.fillOpacity,
  );
  final borderColor = isDark
      ? colors.border.withValues(alpha: material.borderOpacity)
      : ColorPalette.navySoftBorder.withValues(alpha: material.borderOpacity);
  return BoxDecoration(
    color: glassColor,
    borderRadius: borderRadius,
    gradient:
        !useSoftLight &&
            frosted &&
            (role == AppGlassRole.chrome || role == AppGlassRole.sticky)
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
    this.softLight = false,
    this.status = AppGlassStatus.idle,
    this.trackPointer = true,
    this.boxShadow,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final AppGlassRole role;

  /// Allows rendering-heavy callers to keep the same material hierarchy
  /// while replacing live blur with an opaque surface.
  final bool frosted;

  /// Adds a quiet directional wash and pointer-following light beneath the
  /// content. Opt-in independently of live blur: the navigation dock keeps its
  /// opaque scroll-performance fallback. High contrast and OLED disable both.
  final bool softLight;
  final AppGlassStatus status;

  /// Disable when descendants supply their own local feedback (e.g. dock tabs).
  final bool trackPointer;
  final List<BoxShadow>? boxShadow;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final material = context.appTheme.glass.resolve(role);
    final platformHighContrast =
        MediaQuery.maybeOf(context)?.highContrast ?? false;
    final liveBlur = frosted && material.liveBlur && !platformHighContrast;
    final useSoftLight =
        softLight && material.liveBlur && !platformHighContrast;
    final decoration = appGlassDecoration(
      context,
      role: role,
      borderRadius: borderRadius,
      frosted: liveBlur,
      softLight: useSoftLight,
    );
    final content = Padding(padding: padding, child: child);
    final contents = DecoratedBox(
      decoration: decoration,
      child: useSoftLight
          ? AppSoftGlassLight(
              borderRadius: borderRadius,
              status: status,
              trackPointer: trackPointer,
              child: content,
            )
          : content,
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

/// Paint-only local feedback for controls inside a glass surface. Feed the
/// existing FTappable variants; this adds no focus node or gesture recognizer.
/// Keep the control's focus outline, selected indicator and disabled semantics.
class AppGlassFeedback extends StatelessWidget {
  const AppGlassFeedback({
    super.key,
    required this.variants,
    required this.child,
    this.accentColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.full)),
  });

  final Set<FTappableVariant> variants;
  final Widget child;
  final Color? accentColor;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    if (!context.appTheme.glass.resolve(AppGlassRole.chrome).liveBlur ||
        (MediaQuery.maybeOf(context)?.highContrast ?? false)) {
      return child;
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: AppSoftGlassLight(
        borderRadius: borderRadius,
        variants: variants,
        accentColor: accentColor,
        ambient: false,
        trackPointer: false,
        child: child,
      ),
    );
  }
}
