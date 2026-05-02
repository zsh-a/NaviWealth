import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_system/design_system.dart';
import 'shell_preferences.dart';

/// Collapsible left sidebar for the desktop shell (FIR-106).
///
/// Two visual states:
///
///  * Expanded (240dp) — icon + label per destination, selected row gets a
///    primary-tinted pill background and 2dp leading indicator.
///  * Collapsed (72dp) — icons only, label travels into the [Tooltip] so a
///    pointer hover surfaces the destination name without re-flowing the
///    layout.
///
/// The collapse toggle at the bottom (`«` / `»`) drives the same
/// [SidebarCollapsedController] as the `Cmd/Ctrl+B` global shortcut, so
/// mouse and keyboard stay in sync without either path knowing about the
/// other.
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
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: collapsed ? kSidebarCollapsedWidth : kSidebarExpandedWidth,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: theme.dividerTheme.color ?? theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Spacing.s12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.s8,
                  vertical: Spacing.s4,
                ),
                itemCount: destinations.length,
                itemBuilder: (_, i) => _SidebarItem(
                  destination: destinations[i],
                  selected: i == selectedIndex,
                  collapsed: collapsed,
                  onTap: () => onDestinationSelected(i),
                ),
              ),
            ),
            Divider(
              height: 1,
              color: theme.dividerTheme.color,
            ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final iconColor = selected ? cs.primary : cs.onSurfaceVariant;
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: selected ? cs.primary : cs.onSurface,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    );
    final row = Row(
      children: [
        SizedBox(
          width: kSidebarCollapsedWidth - Spacing.s16,
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
                color: cs.primary,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(2),
                ),
              ),
            ),
          ),
        Container(
          height: 48,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.s8),
          decoration: BoxDecoration(
            color: selected
                ? cs.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.centerLeft,
          child: row,
        ),
      ],
    );

    final tap = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: content,
      ),
    );

    if (collapsed) {
      return Tooltip(
        message: destination.label,
        waitDuration: const Duration(milliseconds: 250),
        preferBelow: false,
        child: tap,
      );
    }
    return tap;
  }
}

class _CollapseToggle extends StatelessWidget {
  const _CollapseToggle({required this.collapsed, required this.onToggle});

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s8,
        vertical: Spacing.s8,
      ),
      child: Tooltip(
        message: collapsed ? 'Expand sidebar  (⌘B)' : 'Collapse sidebar  (⌘B)',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle,
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.end,
              children: [
                Icon(
                  collapsed
                      ? Icons.chevron_right_rounded
                      : Icons.chevron_left_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
