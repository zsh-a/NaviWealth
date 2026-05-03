import 'package:flutter/material.dart';

import '../theme/app_elevations.dart';
import '../tokens/color_palette.dart';
import '../tokens/glass_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/radius_tokens.dart';
import '../tokens/spacing_tokens.dart';
import 'glass_surface.dart';
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

/// Modern floating pill-shaped bottom navigation bar with a central
/// [SuperFab] that consolidates all creation actions.
///
/// Layout: `[nav0] [nav1]  [FAB]  [nav2] [nav3]`
///
/// Design principles:
/// - **Floating**: 16dp horizontal margin, 12dp bottom, fully rounded pill
/// - **Glass**: frosted glass surface (sigma=24, 1px hairline border)
/// - **Hide text**: unselected = icon only; selected = icon + label with
///   micro-animation (scale 1.0→1.08, fade+slide label)
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

  static const double _barHeight = 64;
  static const double _horizontalMargin = Spacing.s16;
  static const double _bottomMargin = 12;
  static const double _fabGap = 68;

  /// Space reserved at the bottom of the body so content is not hidden
  /// behind the floating pill bar. = bar height + bottom margin.
  static const double bottomReservedHeight = _barHeight + _bottomMargin;

  @override
  Widget build(BuildContext context) {
    final tokens = GlassTokens.of(context);
    final elevations = AppElevations.of(context);

    // Split destinations: first half left of FAB, second half right.
    final mid = destinations.length ~/ 2;
    final leftDests = destinations.sublist(0, mid);
    final rightDests = destinations.sublist(mid);

    // The FAB overlaps half above the pill bar top edge.
    const fabOverflow = SuperFab.fabSize / 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _horizontalMargin,
        0,
        _horizontalMargin,
        _bottomMargin,
      ),
      child: SizedBox(
        height: _barHeight + fabOverflow,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The pill bar — positioned at the bottom of the stack.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: _barHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.full),
                  boxShadow: elevations.level3,
                ),
                child: GlassSurface(
                  sigma: tokens.blurSigma,
                  borderRadius: BorderRadius.circular(Radii.full),
                  border: Border.all(
                    color: tokens.hairlineColor,
                    width: 1,
                  ),
                  child: Row(
                    children: [
                      // Left nav items.
                      for (int i = 0; i < leftDests.length; i++)
                        Expanded(
                          child: _PillNavItem(
                            destination: leftDests[i],
                            isSelected: selectedIndex == i,
                            onTap: () => onDestinationSelected(i),
                          ),
                        ),
                      // Center gap for the FAB.
                      const SizedBox(width: _fabGap),
                      // Right nav items.
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
              ),
            ),
            // The Super FAB — centered horizontally, overlapping the top
            // edge of the pill bar by half the FAB diameter.
            Positioned(
              left: 0,
              right: 0,
              bottom: _barHeight - fabOverflow,
              child: Center(
                child: SuperFab(
                  actions: superFabActions,
                  enablePulse: enableSuperFabPulse,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single navigation item inside the pill bar.
///
/// Unselected: icon only (neutral color).
/// Selected: icon scales up + label fades in with slide animation.
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
        child: AnimatedContainer(
          duration: Motion.medium,
          curve: Motion.emphasizedDecelerate,
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: isSelected ? 1.08 : 1.0,
                  duration: Motion.medium,
                  curve: Motion.emphasizedDecelerate,
                  child: Icon(
                    isSelected ? destination.selectedIcon : destination.icon,
                    size: 24,
                    color: isSelected ? selectedColor : unselectedColor,
                  ),
                ),
                // Label: visible only when selected.
                AnimatedSize(
                  duration: Motion.medium,
                  curve: Motion.emphasizedDecelerate,
                  alignment: Alignment.centerLeft,
                  child: isSelected
                      ? Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: AnimatedOpacity(
                            opacity: isSelected ? 1 : 0,
                            duration: Motion.fast,
                            child: Text(
                              destination.label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: selectedColor,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
