import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../design_system/design_system.dart';
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
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    this.isAccent = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// True for the AI tab; rendered with a teal accent disc so the assistant
  /// stands out as the primary action layer in the sidebar too.
  final bool isAccent;
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
    final isAccent = destination.isAccent;
    // Accent (AI) tab gets the inverse treatment so it pops: a filled
    // teal disc behind the icon when active, a soft teal tint otherwise.
    final iconColor = isAccent
        ? (selected ? colors.primaryForeground : colors.primary)
        : (selected ? colors.primary : colors.mutedForeground);
    final labelStyle = context.theme.typography.sm.copyWith(
      color: isAccent && selected
          ? colors.primaryForeground
          : (selected ? colors.primary : colors.foreground),
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

    final Color background;
    if (isAccent) {
      background = colors.primary.withValues(alpha: selected ? 1.0 : 0.12);
    } else if (selected) {
      background = colors.primary.withValues(alpha: 0.10);
    } else {
      background = const Color(0x00000000);
    }

    final content = Stack(
      children: [
        if (selected && !isAccent)
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
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
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

class _CollapseToggle extends StatelessWidget {
  const _CollapseToggle({required this.collapsed, required this.onToggle});

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: FTooltip(
        tipBuilder: (_, _) =>
            Text(collapsed ? 'Expand sidebar  (⌘B)' : 'Collapse sidebar  (⌘B)'),
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
                      ? Icons.chevron_right_rounded
                      : Icons.chevron_left_rounded,
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
