import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import 'app_ink_well.dart';
import 'scroll_state.dart';

/// Glass hierarchy levels mapping to package quality tiers.
enum GlassLayer {
  /// Nav bars, modals — full shader pipeline.
  primary,

  /// Dashboard cards — blur + refraction.
  secondary,

  /// Inline chips, badges — blur only, no shader.
  tertiary,
}

/// A card with iOS 26 Liquid Glass rendering.
///
/// Replaces Material [Card] for surfaces that should show content beneath
/// them through a frosted glass effect. Falls back to the package's
/// adaptive quality system automatically.
///
/// Use [GlassLayer] to control the rendering quality:
/// - [GlassLayer.primary] for nav bars and modals (premium quality)
/// - [GlassLayer.secondary] for dashboard cards (standard quality)
/// - [GlassLayer.tertiary] for chips and badges (minimal quality)
///
/// During active scrolling the card automatically downgrades to
/// [GlassLayer.tertiary] to avoid per-frame BackdropFilter cost, then
/// restores the requested quality once scrolling stops.
class LiquidGlassCard extends StatelessWidget {
  const LiquidGlassCard({
    super.key,
    required this.child,
    this.layer = GlassLayer.secondary,
    this.padding,
    this.margin,
    this.borderRadius,
    this.onTap,
  });

  final Widget child;
  final GlassLayer layer;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final VoidCallback? onTap;

  lgw.GlassQuality _quality({required bool isScrolling}) {
    // During scroll, always use minimal quality to avoid GPU blur cost.
    if (isScrolling && layer != GlassLayer.tertiary) {
      return lgw.GlassQuality.minimal;
    }
    return switch (layer) {
      GlassLayer.primary => lgw.GlassQuality.premium,
      GlassLayer.secondary => lgw.GlassQuality.standard,
      GlassLayer.tertiary => lgw.GlassQuality.minimal,
    };
  }

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? 16;
    Widget card = ValueListenableBuilder<bool>(
      valueListenable: isScrollingNotifier,
      builder: (context, isScrolling, _) {
        return RepaintBoundary(
          child: lgw.GlassContainer(
            useOwnLayer: true,
            quality: _quality(isScrolling: isScrolling),
            padding: padding,
            margin: margin,
            shape: lgw.LiquidRoundedSuperellipse(borderRadius: radius),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        );
      },
    );

    if (onTap != null) {
      card = AppInkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: card,
      );
    }
    return card;
  }
}
