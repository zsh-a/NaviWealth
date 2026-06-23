import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/motion_utils.dart';
import '../tokens/typography_tokens.dart';

const double kFloatingGlassNavBarHeight = AppSpacing.s64;

/// A floating glass-morphism bottom navigation bar.
///
/// Renders as a compact, translucent dock that floats above the content
/// with a backdrop blur effect. The optional center action sits inside the
/// same height as the tab destinations so the dock does not cover page-level
/// floating actions.
///
/// The bar splits tabs evenly around the optional center button:
///   [tab₀] [tab₁] ··· [centerAction] ··· [tab₂] [tab₃]
///
/// When [onCenterAction] is null, no center button is rendered and tabs
/// fill the full width evenly.
class FloatingGlassNavBar extends StatelessWidget {
  const FloatingGlassNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onIndexChanged,
    this.onCenterAction,
    this.centerIcon = FLucideIcons.sparkles,
    this.centerLabel,
  });

  /// Navigation destinations.
  final List<FloatingNavTab> items;

  /// Currently selected tab index (0-based, among [items]).
  final int selectedIndex;

  /// Called when a tab is tapped.
  final ValueChanged<int> onIndexChanged;

  /// Called when the center action button is tapped. When `null`, no center
  /// button is rendered.
  final VoidCallback? onCenterAction;

  /// Icon for the center action button.
  final IconData centerIcon;

  /// Optional label beneath the center button.
  final String? centerLabel;

  @override
  Widget build(BuildContext context) {
    final theme = FTheme.of(context);
    final colors = theme.colors;
    final isDark = colors.brightness == Brightness.dark;

    // Unified frosted glass surface. Both themes use the same blur and a
    // semi-transparent tint; only the tint colour changes with brightness.
    final glassColor = isDark
        ? ColorPalette.navyGlass.withValues(alpha: AppOpacity.emphasis)
        : ColorPalette.neutral0.withValues(alpha: AppOpacity.strong);
    final borderColor = isDark
        ? ColorPalette.neutral0.withValues(alpha: AppOpacity.faint)
        : ColorPalette.neutral0.withValues(alpha: AppOpacity.emphasis);

    // Top-edge highlight gradient simulates light refracting through the
    // frosted surface.
    final highlightColor = isDark
        ? ColorPalette.neutral0.withValues(alpha: AppOpacity.faint)
        : ColorPalette.neutral0.withValues(alpha: AppOpacity.medium);
    final highlightColorTransparent = highlightColor.withValues(
      alpha: AppOpacity.transparent,
    );

    return RepaintBoundary(
      child: Container(
        height: kFloatingGlassNavBarHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.nav),
          border: Border.all(color: borderColor, width: AppStroke.hairline),
          boxShadow: AppShadow.nav,
        ),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: AppBlur.nav, sigmaY: AppBlur.nav),
          child: Stack(
            children: [
              // Base frosted fill.
              Positioned.fill(child: ColoredBox(color: glassColor)),
              // Top-edge highlight band — refracted light simulation.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [highlightColor, highlightColorTransparent],
                      stops: const [0.0, 0.35],
                    ),
                  ),
                ),
              ),
              // Navigation content.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s8,
                  vertical: AppSpacing.s6,
                ),
                child: Row(
                  children: [
                    // Left tabs.
                    for (var i = 0; i < _leftCount; i++)
                      Expanded(
                        child: _NavTabButton(
                          tab: items[i],
                          selected: i == selectedIndex,
                          onTap: () => onIndexChanged(i),
                          isDark: isDark,
                        ),
                      ),
                    // Center action button (optional).
                    if (onCenterAction != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s4,
                        ),
                        child: _CenterActionButton(
                          icon: centerIcon,
                          label: centerLabel,
                          onTap: onCenterAction!,
                          isDark: isDark,
                        ),
                      ),
                    // Right tabs.
                    for (var i = _leftCount; i < items.length; i++)
                      Expanded(
                        child: _NavTabButton(
                          tab: items[i],
                          selected: i == selectedIndex,
                          onTap: () => onIndexChanged(i),
                          isDark: isDark,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Number of tabs placed to the left of the center button.
  int get _leftCount => onCenterAction != null ? items.length ~/ 2 : 0;
}

/// A single tab destination for [FloatingGlassNavBar].
class FloatingNavTab {
  const FloatingNavTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

// ── Private widgets ───────────────────────────────────────────────────────

class _NavTabButton extends StatelessWidget {
  const _NavTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  final FloatingNavTab tab;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final iconColor = selected
        ? (isDark ? ColorPalette.navy950 : ColorPalette.neutral0)
        : (isDark ? ColorPalette.navy400 : ColorPalette.navy300);
    final labelColor = selected
        ? (isDark ? ColorPalette.navy50 : ColorPalette.navy900)
        : (isDark ? ColorPalette.navy400 : ColorPalette.navy300);
    final badgeColor = selected
        ? (isDark ? ColorPalette.cyanBrand400 : ColorPalette.navy950)
        : Colors.transparent;

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: FTappable(
        onPress: onTap,
        child: AnimatedContainer(
          duration: motionDuration(context, Motion.fast),
          curve: Motion.standardDecelerate,
          height: 52,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s6,
            vertical: AppSpacing.s4,
          ),
          decoration: BoxDecoration(
            color: selected
                ? (isDark
                      ? ColorPalette.cyanBrand400.withValues(
                          alpha: AppOpacity.light,
                        )
                      : ColorPalette.navy950.withValues(
                          alpha: AppOpacity.faint,
                        ))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: motionDuration(context, Motion.fast),
                curve: Motion.standardDecelerate,
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color:
                                (isDark
                                        ? ColorPalette.cyanBrand400
                                        : ColorPalette.navy950)
                                    .withValues(alpha: AppOpacity.light),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Icon(
                  selected ? tab.selectedIcon : tab.icon,
                  color: iconColor,
                  size: AppIconSizes.h18,
                ),
              ),
              Text(
                tab.label,
                style:
                    (selected
                            ? TypographyTokens.labelSmall
                            : TypographyTokens.labelSmallMedium)
                        .copyWith(color: labelColor, height: 1.2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenterActionButton extends StatefulWidget {
  const _CenterActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool isDark;

  @override
  State<_CenterActionButton> createState() => _CenterActionButtonState();
}

class _CenterActionButtonState extends State<_CenterActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Motion.fast,
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.94,
    ).animate(CurvedAnimation(parent: _controller, curve: Motion.standard));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final buttonColor = widget.isDark
        ? ColorPalette.cyanBrand500
        : ColorPalette.cyanBrand600;
    final iconColor = widget.isDark
        ? ColorPalette.navy950
        : ColorPalette.navy950;

    return Semantics(
      button: true,
      label: widget.label ?? 'AI',
      child: GestureDetector(
        onTapDown: reduceMotion ? null : (_) => _controller.forward(),
        onTapUp: (_) {
          if (!reduceMotion) _controller.reverse();
          widget.onTap();
        },
        onTapCancel: reduceMotion ? null : () => _controller.reverse(),
        child: reduceMotion
            ? _CenterActionButtonSurface(
                icon: widget.icon,
                label: widget.label,
                buttonColor: buttonColor,
                iconColor: iconColor,
              )
            : ScaleTransition(
                scale: _scale,
                child: _CenterActionButtonSurface(
                  icon: widget.icon,
                  label: widget.label,
                  buttonColor: buttonColor,
                  iconColor: iconColor,
                ),
              ),
      ),
    );
  }
}

class _CenterActionButtonSurface extends StatelessWidget {
  const _CenterActionButtonSurface({
    required this.icon,
    required this.label,
    required this.buttonColor,
    required this.iconColor,
  });

  final IconData icon;
  final String? label;
  final Color buttonColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.s56,
      height: 52,
      decoration: BoxDecoration(
        color: buttonColor,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: buttonColor.withValues(alpha: AppOpacity.muted),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: AppIconSizes.lg),
          if (label != null) ...[
            const SizedBox(height: AppSpacing.hairline),
            Text(
              label!,
              style: TypographyTokens.labelTiny.copyWith(
                color: iconColor,
                height: 1.0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
