import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

enum SoftCardLevel { flat, raised, hero }

/// Calm surface container for dense financial UIs.
///
/// Levels form a deliberate elevation ladder:
/// - [SoftCardLevel.flat] — quiet list rows, dissolves into the page
/// - [SoftCardLevel.raised] — primary dashboard modules
/// - [SoftCardLevel.hero] — the single visual anchor on a surface
///
/// Interactive cards get a soft press scale + tonal shift (no Material ripple).
class SoftCard extends StatefulWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.onPress,
    this.borderRadius,
    this.tinted = true,
    this.borderless = false,
    this.level = SoftCardLevel.flat,
  });

  /// Dense list row / nested surface — no elevation.
  const SoftCard.flat({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    VoidCallback? onPress,
    double? borderRadius,
    bool tinted = true,
    bool borderless = false,
  }) : this(
         key: key,
         child: child,
         padding: padding,
         onPress: onPress,
         borderRadius: borderRadius,
         tinted: tinted,
         borderless: borderless,
         level: SoftCardLevel.flat,
       );

  /// Primary dashboard module.
  ///
  /// Padding defaults to zero so existing call sites that nest their own
  /// [Padding] do not double-inset. Prefer [AppPageRhythm.cardPadding] at
  /// call sites for new modules.
  const SoftCard.raised({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    VoidCallback? onPress,
    double? borderRadius,
    bool tinted = true,
    bool borderless = false,
  }) : this(
         key: key,
         child: child,
         padding: padding,
         onPress: onPress,
         borderRadius: borderRadius,
         tinted: tinted,
         borderless: borderless,
         level: SoftCardLevel.raised,
       );

  /// Single page-level visual anchor.
  ///
  /// Prefer [AppPageRhythm.heroPadding] when the card owns its content inset.
  const SoftCard.hero({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    VoidCallback? onPress,
    double? borderRadius,
    bool tinted = true,
    bool borderless = false,
  }) : this(
         key: key,
         child: child,
         padding: padding,
         onPress: onPress,
         borderRadius: borderRadius,
         tinted: tinted,
         borderless: borderless,
         level: SoftCardLevel.hero,
       );

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onPress;

  /// Override corner radius. When null, resolves from [level]:
  /// flat/raised → [AppRadius.lg], hero → [AppRadius.xl].
  final double? borderRadius;

  /// Apply the level's surface fill. Disable for nested rows that sit
  /// inside an already-tinted parent.
  final bool tinted;

  /// Drop the border entirely (grouped inset lists).
  final bool borderless;

  /// Visual depth. Prefer one [SoftCardLevel.hero] per screen.
  final SoftCardLevel level;

  double get resolvedRadius =>
      borderRadius ??
      (level == SoftCardLevel.hero ? AppRadius.xl : AppRadius.lg);

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
    return DecoratedBox(
      decoration: _decoration(context, hovered: false, pressed: false),
      child: Padding(padding: widget.padding, child: widget.child),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required bool hovered,
    required bool pressed,
  }) {
    final duration = AppMotionPolicy.duration(context, Motion.fast);
    return AnimatedScale(
      scale: pressed ? 0.985 : 1,
      duration: duration,
      curve: Motion.standardDecelerate,
      child: AnimatedContainer(
        duration: duration,
        curve: Motion.standardDecelerate,
        decoration: _decoration(context, hovered: hovered, pressed: pressed),
        padding: widget.padding,
        child: widget.child,
      ),
    );
  }

  BoxDecoration _decoration(
    BuildContext context, {
    required bool hovered,
    required bool pressed,
  }) {
    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;
    final radius = BorderRadius.circular(widget.resolvedRadius);

    final baseFill = widget.tinted
        ? _surfaceFill(
            card: colors.card,
            foreground: colors.foreground,
            primary: colors.primary,
            isDark: isDark,
          )
        : Colors.transparent;

    final hoverBoost = isDark ? AppOpacity.hoverTintDark : AppOpacity.hoverTint;
    final interactive = widget.onPress != null && (hovered || pressed);
    final fill = interactive && widget.tinted
        ? Color.alphaBlend(
            colors.foreground.withValues(
              alpha: pressed ? AppOpacity.faint : hoverBoost,
            ),
            baseFill,
          )
        : interactive && !widget.tinted
        ? colors.foreground.withValues(alpha: hoverBoost)
        : baseFill;

    final borderAlpha = widget.borderless
        ? AppOpacity.transparent
        : switch (widget.level) {
            SoftCardLevel.flat =>
              isDark ? AppOpacity.whisper : AppOpacity.transparent,
            SoftCardLevel.raised =>
              isDark ? AppOpacity.medium : AppOpacity.faint,
            SoftCardLevel.hero =>
              isDark ? AppOpacity.disabled : AppOpacity.subtle,
          };

    final borderColor = borderAlpha == AppOpacity.transparent
        ? Colors.transparent
        : (isDark
              ? colors.border.withValues(alpha: borderAlpha)
              : ColorPalette.navySoftBorder.withValues(alpha: borderAlpha));

    final gradient = widget.level == SoftCardLevel.hero && widget.tinted
        ? _heroGradient(primary: colors.primary, isDark: isDark, base: fill)
        : null;

    return BoxDecoration(
      color: gradient == null ? fill : null,
      gradient: gradient,
      borderRadius: radius,
      border: borderAlpha == AppOpacity.transparent
          ? null
          : Border.all(color: borderColor, width: AppStroke.hairline),
      boxShadow: _shadows(isDark: isDark, hovered: hovered, pressed: pressed),
    );
  }

  Color _surfaceFill({
    required Color card,
    required Color foreground,
    required Color primary,
    required bool isDark,
  }) {
    if (!isDark) {
      // Cool page canvas + pure white modules = modern fintech depth.
      return ColorPalette.surface;
    }
    return switch (widget.level) {
      SoftCardLevel.flat => card,
      SoftCardLevel.raised => Color.alphaBlend(
        foreground.withValues(alpha: AppOpacity.faint),
        card,
      ),
      SoftCardLevel.hero => Color.alphaBlend(
        primary.withValues(alpha: AppOpacity.subtle),
        Color.alphaBlend(foreground.withValues(alpha: AppOpacity.faint), card),
      ),
    };
  }

  LinearGradient _heroGradient({
    required Color primary,
    required bool isDark,
    required Color base,
  }) {
    final wash = isDark
        ? primary.withValues(alpha: AppOpacity.light)
        : primary.withValues(alpha: AppOpacity.faint);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color.alphaBlend(wash, base), base],
      stops: const [0, 0.55],
    );
  }

  List<BoxShadow>? _shadows({
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
        isDark
            ? AppShadow.cardDark
            : hovered && widget.onPress != null
            ? AppShadow.cardHover
            : AppShadow.card,
      SoftCardLevel.hero => isDark ? AppShadow.heroDark : AppShadow.hero,
    };
  }
}
