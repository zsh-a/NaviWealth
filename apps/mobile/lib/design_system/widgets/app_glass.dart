import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
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
  BorderRadius? borderRadius,
  List<BoxShadow>? boxShadow,
}) {
  final colors = context.theme.colors;
  final isDark = colors.brightness == Brightness.dark;
  final surfaces = context.appTheme.surfaces;
  final glassColor = isDark
      ? surfaces.card.withValues(alpha: AppOpacity.overlay)
      : ColorPalette.neutral0.withValues(alpha: AppOpacity.overlay);
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
    this.blurSigma = AppBlur.chrome,
    this.boxShadow,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final List<BoxShadow>? boxShadow;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final decoration = appGlassDecoration(context, borderRadius: borderRadius);
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: boxShadow,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: DecoratedBox(
              decoration: decoration,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
