import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

/// A floating glass-morphism bottom navigation bar.
///
/// Renders as a pill-shaped, translucent bar that floats above the content
/// with a backdrop blur effect. Matches the fintech UI spec: soft cyan-white
/// fill, large radius, subtle shadow, and an optional elevated center action
/// button (e.g. Ask AI).
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

    // Glass surface: translucent white/navy with backdrop blur.
    final glassColor = isDark
        ? const Color(0xFF0F2A35).withValues(alpha: AppOpacity.strong)
        : Colors.white.withValues(alpha: AppOpacity.strong);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: AppOpacity.faint)
        : const Color(0xFFEAF0F6).withValues(alpha: AppOpacity.strong);

    return Container(
      decoration: BoxDecoration(
        color: glassColor,
        borderRadius: BorderRadius.circular(AppRadius.nav),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: AppShadow.nav,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.nav),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppBlur.nav.toDouble(),
            sigmaY: AppBlur.nav.toDouble(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s6,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Left tabs.
                for (var i = 0; i < _leftCount; i++)
                  _NavTabButton(
                    tab: items[i],
                    selected: i == selectedIndex,
                    onTap: () => onIndexChanged(i),
                    isDark: isDark,
                  ),
                // Center action button (optional).
                if (onCenterAction != null)
                  _CenterActionButton(
                    icon: centerIcon,
                    label: centerLabel,
                    onTap: onCenterAction!,
                    isDark: isDark,
                  ),
                // Right tabs.
                for (var i = _leftCount; i < items.length; i++)
                  _NavTabButton(
                    tab: items[i],
                    selected: i == selectedIndex,
                    onTap: () => onIndexChanged(i),
                    isDark: isDark,
                  ),
              ],
            ),
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
    // Selected: dark navy circle bg + cyan icon + bold label.
    // Unselected: transparent bg + muted icon + label.
    final iconColor = selected
        ? (isDark
            ? ColorPalette.cyanBrand400
            : ColorPalette.cyanBrand500)
        : (isDark ? ColorPalette.navy400 : ColorPalette.navy300);
    final labelColor = selected
        ? (isDark ? ColorPalette.navy50 : ColorPalette.navy900)
        : (isDark ? ColorPalette.navy400 : ColorPalette.navy300);
    final bgColor = selected
        ? (isDark
            ? ColorPalette.navy800
            : ColorPalette.cyanBrand50)
        : Colors.transparent;

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: FTappable(
        onPress: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standardDecelerate,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s10,
            vertical: AppSpacing.s6,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? tab.selectedIcon : tab.icon,
                color: iconColor,
                size: AppIconSizes.lg,
              ),
              const SizedBox(height: 2),
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: labelColor,
                  height: 1.2,
                ),
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
    _scale = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _controller, curve: Motion.standard),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buttonColor = widget.isDark
        ? ColorPalette.cyanBrand400
        : ColorPalette.cyanBrand500;
    final iconColor = widget.isDark
        ? ColorPalette.navy950
        : ColorPalette.navy950;

    return Semantics(
      button: true,
      label: widget.label ?? 'AI',
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) {
          _controller.reverse();
          widget.onTap();
        },
        onTapCancel: () => _controller.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: AppSpacing.s56,
            height: AppSpacing.s56,
            decoration: BoxDecoration(
              color: buttonColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: buttonColor.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: iconColor, size: AppIconSizes.lg),
                if (widget.label != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    widget.label!,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: iconColor,
                      height: 1.0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
