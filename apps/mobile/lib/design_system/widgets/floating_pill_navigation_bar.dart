import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lgw;

import '../tokens/color_palette.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/radius_tokens.dart';
import '../tokens/spacing_tokens.dart';
import 'super_fab.dart';

/// A navigation destination for the [FloatingPillNavigationBar].
class PillNavDestination {
  const PillNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Modern floating bottom navigation bar with a central [SuperFab] that
/// consolidates all creation actions.
///
/// Layout: `[nav0] [nav1]  [FAB]  [nav2] [nav3]`
///
/// Design: Apple-style frosted glass — high blur, minimal tint, no hard
/// shadows. Labels are always visible below icons. Content scrolls behind
/// the bar for an immersive feel.
class FloatingPillNavigationBar extends StatelessWidget {
  const FloatingPillNavigationBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.superFabActions,
    this.enableSuperFabPulse = true,
  });

  final List<PillNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<SuperFabAction> superFabActions;

  /// Whether the SuperFab resting-state pulse animation plays.
  final bool enableSuperFabPulse;

  static const double _barHeight = 68;
  static const double _horizontalMargin = Spacing.s12;
  static const double _bottomMargin = 8;

  /// Bottom inset injected into MediaQuery so child scroll views can
  /// scroll past the floating bar. = bar height + bottom margin.
  static const double overlayBottomInset = _barHeight + _bottomMargin;

  @override
  Widget build(BuildContext context) {

    // Split destinations: first half left of FAB, second half right.
    final mid = destinations.length ~/ 2;
    final leftDests = destinations.sublist(0, mid);
    final rightDests = destinations.sublist(mid);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _horizontalMargin,
        0,
        _horizontalMargin,
        _bottomMargin,
      ),
      child: lgw.GlassContainer(
        useOwnLayer: true,
        quality: lgw.GlassQuality.premium,
        height: _barHeight,
        shape: const lgw.LiquidRoundedSuperellipse(borderRadius: Radii.xxl),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            for (int i = 0; i < leftDests.length; i++)
              Expanded(
                child: _PillNavItem(
                  destination: leftDests[i],
                  isSelected: selectedIndex == i,
                  onTap: () => onDestinationSelected(i),
                ),
              ),
            // Center FAB — flush with the bar, no overflow.
            SuperFab(
              actions: superFabActions,
              enablePulse: enableSuperFabPulse,
            ),
            for (int i = 0; i < rightDests.length; i++)
              Expanded(
                child: _PillNavItem(
                  destination: rightDests[i],
                  isSelected: selectedIndex == mid + i,
                  onTap: () => onDestinationSelected(mid + i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single navigation item: icon above label, always visible.
///
/// Selected: brand color + subtle scale bump.
/// Unselected: muted color.
class _PillNavItem extends StatelessWidget {
  const _PillNavItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final PillNavDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const selectedColor = ColorPalette.brand500;
    final unselectedColor = theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: FloatingPillNavigationBar._barHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: isSelected ? 1.1 : 1.0,
              duration: Motion.medium,
              curve: Motion.emphasizedDecelerate,
              child: Icon(
                isSelected ? destination.selectedIcon : destination.icon,
                size: 24,
                color: isSelected ? selectedColor : unselectedColor,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: Motion.medium,
              curve: Motion.emphasizedDecelerate,
              style: theme.textTheme.labelSmall!.copyWith(
                color: isSelected ? selectedColor : unselectedColor,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 10,
              ),
              child: Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
