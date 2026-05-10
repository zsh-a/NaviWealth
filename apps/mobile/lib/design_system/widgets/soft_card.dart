import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/motion_tokens.dart';

/// A calmer container than `FCard.raw` — replaces 1px crisp outlines
/// with a 6%-alpha border + a 2%-alpha tint pulled from the foreground.
/// The result reads as a "surface" rather than a "component", giving
/// the wealth cockpit Apple Stocks / Arc-style breathing room instead
/// of the legacy "outlined card grid" look.
///
/// When [interactive] is true (the default for tappable rows), the card
/// also runs a 1.5% soft-fill micro-press animation so the surface
/// feels alive without a heavy ripple.
///
/// Use this everywhere except where contrast is critical (modals,
/// banners, the AI proposal cards which still need a hard edge).
class SoftCard extends StatefulWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.onPress,
    this.borderRadius = 14,
    this.tinted = true,
    this.borderless = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onPress;
  final double borderRadius;

  /// Apply the 2%-alpha foreground tint as background. Disable when the
  /// card is meant to dissolve into the page surface (e.g. nested rows
  /// inside an already-tinted section block).
  final bool tinted;

  /// Drop the border entirely. Useful for inline rows in inset grouped
  /// lists where the outer section already provides the boundary.
  final bool borderless;

  @override
  State<SoftCard> createState() => _SoftCardState();
}

class _SoftCardState extends State<SoftCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;

    final baseTint = widget.tinted
        ? (isDark
              ? colors.foreground.withValues(alpha: 0.04)
              : colors.foreground.withValues(alpha: 0.02))
        : Colors.transparent;
    final hoverBoost = isDark ? 0.025 : 0.015;
    final tint = !widget.onPress.isNull && (_hovered || _pressed)
        ? colors.foreground.withValues(
            alpha:
                (widget.tinted ? (isDark ? 0.04 : 0.02) : 0) + hoverBoost,
          )
        : baseTint;

    final borderColor = widget.borderless
        ? Colors.transparent
        : colors.foreground.withValues(alpha: isDark ? 0.08 : 0.06);

    final card = AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.standardDecelerate,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: widget.borderless
            ? null
            : Border.all(color: borderColor, width: 1),
      ),
      padding: widget.padding,
      child: widget.child,
    );

    if (widget.onPress == null) return card;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPress,
        child: card,
      ),
    );
  }
}

extension on VoidCallback? {
  bool get isNull => this == null;
}
