import 'package:flutter/material.dart';

import '../tokens/glass_tokens.dart';
import 'app_ink_well.dart';

/// Layer hint retained from the glass era. After the Forui migration the
/// three values render the same flat card; the enum is kept so existing
/// call sites compile without per-file edits. Future feature PRs can drop
/// the parameter and inline `FCard` directly.
enum GlassLayer { primary, secondary, tertiary }

/// Flat surface card with a 1-px hairline border, replacing the previous
/// liquid-glass implementation. Keeps the original constructor surface so
/// the 46+ callers continue to compile; visual is now Forui-aligned (zinc
/// surface + hairline border + 12-px radius).
class LiquidGlassCard extends StatelessWidget {
  const LiquidGlassCard({
    super.key,
    required this.child,
    this.layer = GlassLayer.secondary,
    this.padding,
    this.margin,
    this.borderRadius,
    this.onTap,
    this.useOwnLayer = false,
  });

  final Widget child;
  final GlassLayer layer;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final VoidCallback? onTap;

  /// Retained for binary compatibility with the glass-era API. No-op.
  final bool useOwnLayer;

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTokens.of(context);
    final radius = borderRadius ?? tokens.borderRadius;
    final shape = BorderRadius.circular(radius);

    Widget card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: tokens.surfaceColor,
        borderRadius: shape,
        border: Border.all(color: tokens.hairlineColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    if (onTap != null) {
      card = AppInkWell(
        onTap: onTap,
        borderRadius: shape,
        child: card,
      );
    }
    return card;
  }
}
