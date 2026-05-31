import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../design_system/design_system.dart';
import '../l10n/gen/app_localizations.dart';
import 'route_paths.dart';
import 'shell_preferences.dart';

/// Collapsible left sidebar for the desktop shell.
///
/// Two visual states:
///
///  * Expanded (240dp) — icon + label per destination, selected row gets a
///    primary-tinted pill background and 2dp leading indicator.
///  * Collapsed (72dp) — icons only, label travels into the [FTooltip] so a
///    pointer hover surfaces the destination name without re-flowing the
///    layout.
class DesktopSidebar extends ConsumerWidget {
  const DesktopSidebar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<DesktopSidebarDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final colors = context.theme.colors;
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.standardDecelerate,
      width: collapsed ? kSidebarCollapsedWidth : kSidebarExpandedWidth,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(right: BorderSide(color: colors.border, width: 1)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.s12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
                itemCount: destinations.length,
                itemBuilder: (_, i) => _SidebarItem(
                  destination: destinations[i],
                  selected: i == selectedIndex,
                  collapsed: collapsed,
                  onTap: () => onDestinationSelected(i),
                ),
              ),
            ),
            const FDivider(),
            // Pinned bottom row — Settings is off-nav (IA contract §1)
            // but the desktop shell has the room to surface it as a
            // discoverable entry, mirroring the Today-header avatar on
            // mobile. Not a destination, so [selectedIndex] semantics
            // are unaffected.
            _SettingsPinnedRow(collapsed: collapsed),
            _CollapseToggle(
              collapsed: collapsed,
              onToggle: () =>
                  ref.read(sidebarCollapsedProvider.notifier).toggle(),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the sidebar.
class DesktopSidebarDestination {
  const DesktopSidebarDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final DesktopSidebarDestination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final iconColor = selected ? colors.primary : colors.mutedForeground;
    final labelStyle = context.theme.typography.sm.copyWith(
      color: selected ? colors.primary : colors.foreground,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    );
    final row = Row(
      children: [
        SizedBox(
          width: kSidebarCollapsedWidth - 16,
          child: Icon(
            selected ? destination.selectedIcon : destination.icon,
            color: iconColor,
          ),
        ),
        if (!collapsed)
          Expanded(
            child: Text(
              destination.label,
              style: labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );

    final Color background = selected
        ? colors.primary.withValues(alpha: AppOpacity.subtle)
        : const Color(0x00000000);

    final content = Stack(
      children: [
        if (selected)
          Positioned(
            left: 0,
            top: 4,
            bottom: 4,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(2),
                ),
              ),
            ),
          ),
        Container(
          height: 48,
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          alignment: Alignment.centerLeft,
          child: row,
        ),
      ],
    );

    final tap = FTappable(onPress: onTap, child: content);

    if (collapsed) {
      return FTooltip(
        tipBuilder: (_, _) => Text(destination.label),
        child: tap,
      );
    }
    return tap;
  }
}

/// Pinned bottom row that pushes /settings.
///
/// Renders as a small icon-only square when [collapsed], or as a full
/// row with an outlined gear + label when expanded. Mirrors the visual
/// language of [_SidebarItem] minus the "selected" affordance — Settings
/// is never the active tab.
class _SettingsPinnedRow extends StatelessWidget {
  const _SettingsPinnedRow({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final label = l10n.navSettings;
    final iconColor = colors.mutedForeground;
    final row = Row(
      children: [
        SizedBox(
          width: kSidebarCollapsedWidth - 16,
          child: Icon(FLucideIcons.settings, color: iconColor),
        ),
        if (!collapsed)
          Expanded(
            child: Text(
              label,
              style: context.theme.typography.sm.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
    final tile = Container(
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      alignment: Alignment.centerLeft,
      child: row,
    );
    final tap = FTappable(
      onPress: () => context.push(AppRoutes.settings),
      child: tile,
    );
    if (collapsed) {
      return FTooltip(tipBuilder: (_, _) => Text(label), child: tap);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      child: tap,
    );
  }
}

class _CollapseToggle extends StatelessWidget {
  const _CollapseToggle({required this.collapsed, required this.onToggle});

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8, vertical: AppSpacing.s8),
      child: FTooltip(
        tipBuilder: (_, _) => Text(
          collapsed
              ? l10n.shellExpandSidebarShortcut
              : l10n.shellCollapseSidebarShortcut,
        ),
        child: FTappable(
          onPress: onToggle,
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.end,
              children: [
                Icon(
                  collapsed
                      ? FLucideIcons.chevronRight
                      : FLucideIcons.chevronLeft,
                  color: colors.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
