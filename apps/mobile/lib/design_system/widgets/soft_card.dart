import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

enum SoftCardLevel { flat, raised, hero }

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
    this.borderRadius = AppRadius.sm,
    this.tinted = true,
    this.borderless = false,
    this.level = SoftCardLevel.flat,
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

  /// Visual depth. Defaults to [SoftCardLevel.flat] for dense repeated
  /// rows. Use [SoftCardLevel.raised] for primary dashboard cards and
  /// [SoftCardLevel.hero] for the one most important card on a surface.
  final SoftCardLevel level;

  @override
  State<SoftCard> createState() => _SoftCardState();
}

class _SoftCardState extends State<SoftCard> {
  final ValueNotifier<bool> _hovered = ValueNotifier(false);
  final ValueNotifier<bool> _pressed = ValueNotifier(false);

  @override
  void dispose() {
    _hovered.dispose();
    _pressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onPress == null) {
      return _buildStaticCard(context);
    }

    return Semantics(
      button: true,
      child: MouseRegion(
        onEnter: (_) => _hovered.value = true,
        onExit: (_) => _hovered.value = false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _pressed.value = true,
          onTapUp: (_) => _pressed.value = false,
          onTapCancel: () => _pressed.value = false,
          onTap: widget.onPress,
          child: ValueListenableBuilder<bool>(
            valueListenable: _hovered,
            builder: (context, hovered, _) => ValueListenableBuilder<bool>(
              valueListenable: _pressed,
              builder: (context, pressed, _) =>
                  _buildCard(context, hovered: hovered, pressed: pressed),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStaticCard(BuildContext context) {
    final decoration = _decoration(context, hovered: false, pressed: false);
    return DecoratedBox(
      decoration: decoration,
      child: Padding(padding: widget.padding, child: widget.child),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required bool hovered,
    required bool pressed,
  }) {
    final decoration = _decoration(context, hovered: hovered, pressed: pressed);
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.standardDecelerate,
      decoration: decoration,
      padding: widget.padding,
      child: widget.child,
    );
  }

  BoxDecoration _decoration(
    BuildContext context, {
    required bool hovered,
    required bool pressed,
  }) {
    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;

    final baseTint = widget.tinted
        ? (isDark
              ? colors.foreground.withValues(alpha: AppOpacity.faint)
              : Colors.white.withValues(alpha: AppOpacity.overlay))
        : Colors.transparent;
    final hoverBoost = isDark ? 0.03 : AppOpacity.faint;
    final tint = !widget.onPress.isNull && (hovered || pressed)
        ? (widget.tinted
              ? (isDark
                    ? colors.foreground.withValues(
                        alpha: AppOpacity.faint + hoverBoost,
                      )
                    : Colors.white.withValues(alpha: AppOpacity.nearOpaque))
              : colors.foreground.withValues(alpha: hoverBoost))
        : baseTint;

    final borderColor = widget.borderless
        ? Colors.transparent
        : colors.foreground.withValues(
            alpha: isDark ? AppOpacity.faint : AppOpacity.whisper,
          );

    return BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(widget.borderRadius),
      border: widget.borderless
          ? null
          : Border.all(color: borderColor, width: 1),
      boxShadow: _shadows(
        colors,
        shadowColor: Theme.of(context).shadowColor,
        isDark: isDark,
        hovered: hovered,
        pressed: pressed,
      ),
    );
  }

  List<BoxShadow>? _shadows(
    FColors colors, {
    required Color shadowColor,
    required bool isDark,
    required bool hovered,
    required bool pressed,
  }) {
    final level = pressed && widget.onPress != null
        ? SoftCardLevel.flat
        : widget.level;
    final alphaBoost = hovered && widget.onPress != null ? 0.02 : 0.0;
    final keyColor = shadowColor.withValues(
      alpha: isDark
          ? AppOpacity.muted + alphaBoost
          : AppOpacity.whisper + alphaBoost,
    );
    final ambientColor = colors.foreground.withValues(
      alpha: isDark ? 0.04 : 0.03,
    );
    return switch (level) {
      SoftCardLevel.flat => null,
      SoftCardLevel.raised => [
        BoxShadow(color: keyColor, blurRadius: 18, offset: const Offset(0, 8)),
      ],
      SoftCardLevel.hero => [
        BoxShadow(
          color: shadowColor,
          blurRadius: 26,
          offset: const Offset(0, 14),
        ),
        BoxShadow(color: ambientColor, blurRadius: 2),
      ],
    };
  }
}

extension on VoidCallback? {
  bool get isNull => this == null;
}
