import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/color_palette.dart';
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
    this.borderRadius = AppRadius.card,
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
      duration: AppMotionPolicy.duration(context, Motion.fast),
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

    // Reference style: flat rows stay white; elevated surfaces pick up a
    // barely-blue wash so dashboard cards read like soft app panels.
    final lightSurface = switch (widget.level) {
      SoftCardLevel.flat => ColorPalette.neutral0,
      SoftCardLevel.raised => ColorPalette.neutralCardRaised,
      SoftCardLevel.hero => ColorPalette.neutralCardHero,
    };
    final baseTint = widget.tinted
        ? (isDark ? colors.card : lightSurface)
        : Colors.transparent;
    final hoverBoost = isDark ? AppOpacity.hoverTintDark : AppOpacity.hoverTint;
    final tint = !widget.onPress.isNull && (hovered || pressed)
        ? (widget.tinted
              ? (isDark
                    ? colors.card.withValues(
                        alpha: AppOpacity.opaque - hoverBoost,
                      )
                    : lightSurface.withValues(
                        alpha: AppOpacity.opaque - hoverBoost,
                      ))
              : colors.foreground.withValues(alpha: hoverBoost))
        : baseTint;

    final borderAlpha = switch (widget.level) {
      SoftCardLevel.flat => AppOpacity.transparent,
      SoftCardLevel.raised => AppOpacity.faint,
      SoftCardLevel.hero => AppOpacity.subtle,
    };
    final borderColor =
        widget.borderless || borderAlpha == AppOpacity.transparent
        ? Colors.transparent
        : (isDark
              ? colors.border.withValues(alpha: borderAlpha)
              : ColorPalette.navySoftBorder.withValues(alpha: borderAlpha));

    return BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(widget.borderRadius),
      border: widget.borderless || borderAlpha == AppOpacity.transparent
          ? null
          : Border.all(color: borderColor, width: AppStroke.hairline),
      boxShadow: _shadows(
        colors,
        isDark: isDark,
        hovered: hovered,
        pressed: pressed,
      ),
    );
  }

  List<BoxShadow>? _shadows(
    FColors colors, {
    required bool isDark,
    required bool hovered,
    required bool pressed,
  }) {
    final level = pressed && widget.onPress != null
        ? SoftCardLevel.flat
        : widget.level;
    return switch (level) {
      SoftCardLevel.flat => null,
      SoftCardLevel.raised =>
        hovered && widget.onPress != null
            ? AppShadow.cardHover
            : AppShadow.card,
      SoftCardLevel.hero => [
        ...AppShadow.card,
        BoxShadow(
          color:
              (isDark ? ColorPalette.cyanBrand400 : ColorPalette.cyanBrand500)
                  .withValues(alpha: AppOpacity.whisper),
          blurRadius: 32,
          offset: const Offset(0, 12),
        ),
      ],
    };
  }
}

extension on VoidCallback? {
  bool get isNull => this == null;
}
