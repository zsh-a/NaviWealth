import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tokens/glass_tokens.dart';

/// Low-level glassmorphism surface used by [GlassAppBar],
/// [GlassNavigationBar], and modal sheets.
///
/// Rendering is two-pass:
///
/// 1. A `ClipRect` clamps the blur to the surface bounds — without it,
///    [BackdropFilter] bleeds beyond its layout box and tints sibling
///    widgets that happen to share a layer.
/// 2. A [BackdropFilter] (sigma from [GlassTokens]) blurs whatever is
///    drawn below us; a [ColoredBox] then paints the tint.
///
/// On platforms where [GlassTokens.isSupported] is false (web, build-time
/// opt-out) the [BackdropFilter] is skipped entirely — we render only the
/// tint, whose alpha is tuned to still read as a deliberate surface when
/// flat. That keeps the shell looking intentional on Safari ≤14 and older
/// Android without paying the per-frame blur cost.
///
/// Callers pass [sigma] when they want a different blur than the active
/// theme default — we use 18 for AppBar, 24 for BottomNav, 20 for sheets,
/// 16 for desktop top surfaces. The token's own [GlassTokens.blurSigma] is
/// the fallback if [sigma] is null.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.sigma,
    this.alpha,
    this.borderRadius,
    this.border,
  });

  /// Content rendered on top of the blurred backdrop.
  final Widget child;

  /// Blur sigma override. When null, falls back to [GlassTokens.blurSigma].
  final double? sigma;

  /// Optional alpha override for the surface tint, in 0..1. Used by
  /// [GlassAppBar] to ramp opacity on scroll. When null we keep the tint's
  /// own alpha from [GlassTokens.surfaceColor].
  final double? alpha;

  /// Optional clipping/border radius. AppBar / NavigationBar surfaces are
  /// usually rectangular; sheets and pills supply this.
  final BorderRadius? borderRadius;

  /// Optional 1-px hairline border. Pass `Border(top: ...)` for AppBar /
  /// `Border(top: ..., left: ..., right: ...)` for sheets, etc.
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTokens.of(context);
    final tint = alpha == null
        ? tokens.surfaceColor
        : tokens.surfaceColor.withValues(alpha: alpha);
    // Skip the BackdropFilter when the platform reports it cannot or
    // should not render glass:
    //   * GlassTokens.isSupported() — build-time / web opt-out.
    //   * highContrast — the closest Flutter signal for iOS Reduce
    //     Transparency / Android High-Contrast Text.
    //   * disableAnimations — users who disable motion typically also
    //     prefer flatter surfaces; mirrors the package's accessibility
    //     fallback for `liquid_glass_widgets`.
    final mq = MediaQuery.maybeOf(context);
    final highContrast = mq?.highContrast ?? false;
    final disableAnimations = mq?.disableAnimations ?? false;
    final useBlur =
        GlassTokens.isSupported() && !highContrast && !disableAnimations;
    final effectiveSigma = sigma ?? tokens.blurSigma;

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(color: tint, border: border),
      child: child,
    );

    if (useBlur) {
      surface = BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: effectiveSigma,
          sigmaY: effectiveSigma,
        ),
        child: surface,
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: surface);
    }
    return ClipRect(child: surface);
  }
}
