import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../tokens/glass_tokens.dart';

/// A card with liquid glass treatment: translucent backdrop blur, specular
/// highlight on the top edge, and a subtle inner glow that defines the
/// glass boundary.
///
/// Use for hero cards, feature cards, and surfaces where the "floating glass"
/// aesthetic should be prominent. For standard list rows, use the regular
/// [Card] theme instead.
class LiquidGlassCard extends StatelessWidget {
  const LiquidGlassCard({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.margin,
    this.elevation = 0,
    this.onTap,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double elevation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTokens.of(context);
    final effectiveRadius = borderRadius ?? BorderRadius.circular(tokens.borderRadius);
    final useBlur = GlassTokens.isSupported();

    Widget card = _LiquidGlassDecoration(
      tokens: tokens,
      borderRadius: effectiveRadius,
      child: padding != null
          ? Padding(padding: padding!, child: child)
          : child,
    );

    if (useBlur) {
      card = ClipRRect(
        borderRadius: effectiveRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: tokens.blurSigma,
            sigmaY: tokens.blurSigma,
          ),
          child: card,
        ),
      );
    } else {
      card = ClipRRect(borderRadius: effectiveRadius, child: card);
    }

    if (elevation > 0) {
      card = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: effectiveRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08 * elevation),
              blurRadius: 4.0 * elevation,
              offset: Offset(0, 2.0 * elevation),
            ),
          ],
        ),
        child: card,
      );
    }

    if (onTap != null) {
      card = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      );
    }

    if (margin != null) {
      return Padding(padding: margin!, child: card);
    }
    return card;
  }
}

/// Renders the liquid glass decoration layers: base tint, specular highlight
/// gradient, inner glow border.
class _LiquidGlassDecoration extends StatelessWidget {
  const _LiquidGlassDecoration({
    required this.tokens,
    required this.borderRadius,
    required this.child,
  });

  final GlassTokens tokens;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceColor,
        borderRadius: borderRadius,
        border: Border.all(
          color: tokens.hairlineColor,
          width: 0.5,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              tokens.specularColor,
              Colors.transparent,
            ],
            stops: const [0.0, 0.35],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: tokens.innerGlowColor,
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
