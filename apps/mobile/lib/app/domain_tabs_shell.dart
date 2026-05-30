import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../core/ai/write/persistent_undo_banner.dart';
import '../core/shell/domain_shell.dart';
import '../design_system/design_system.dart';
import '../l10n/gen/app_localizations.dart';
import 'desktop_sidebar.dart';
import 'domain_switcher.dart';
import 'route_paths.dart';

/// Per-domain shell builder. One [DomainTabsShell] per LifeOS domain;
/// each lives at `features/<domain>/composition/<domain>_routes.dart`
/// inside that domain's `StatefulShellRoute.indexedStack(builder: ...)`.
///
/// Renders the domain's tabs (mobile bottom nav / tablet rail / desktop
/// sidebar) plus the [StatefulNavigationShell] content. The cross-domain
/// dock chrome is rendered by the *outer* `AppDockShell` (see
/// `app_dock_shell.dart`) — this widget is dock-agnostic.
class DomainTabsShell extends ConsumerStatefulWidget {
  const DomainTabsShell({
    super.key,
    required this.shell,
    required this.spec,
  });

  final StatefulNavigationShell shell;
  final DomainShellSpec spec;

  static const double _tabletBreakpoint = 600;
  static const double _desktopBreakpoint = 1240;

  @override
  ConsumerState<DomainTabsShell> createState() => _DomainTabsShellState();
}

class _DomainTabsShellState extends ConsumerState<DomainTabsShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.medium);
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Motion.emphasizedDecelerate,
    );
    _controller.value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DomainTabsShell old) {
    super.didUpdateWidget(old);
    if (widget.shell.currentIndex != old.shell.currentIndex) {
      _controller.forward(from: 0);
    }
  }

  void _onSelected(int i) {
    widget.shell.goBranch(
      i,
      initialLocation: i == widget.shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.spec.tabs;
    final index = widget.shell.currentIndex;
    final animatedChild = FadeTransition(opacity: _fade, child: widget.shell);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= DomainTabsShell._desktopBreakpoint) {
          return _DesktopLayout(
            tabs: tabs,
            selectedIndex: index,
            onDestinationSelected: _onSelected,
            child: animatedChild,
          );
        }
        if (width >= DomainTabsShell._tabletBreakpoint) {
          return _TabletLayout(
            tabs: tabs,
            selectedIndex: index,
            onDestinationSelected: _onSelected,
            child: animatedChild,
          );
        }
        return _MobileLayout(
          tabs: tabs,
          selectedIndex: index,
          onDestinationSelected: _onSelected,
          child: animatedChild,
        );
      },
    );
  }
}

class _MobileLayout extends ConsumerWidget {
  const _MobileLayout({
    required this.tabs,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  final List<DomainShellTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pure tab nav — Search no longer steals a slot here. The global
    // Search / Settings actions live in each page's header
    // (`app/shell_chrome.dart`); Finance is back to its 4 tabs, matching
    // every other domain's bottom-nav shape.
    final children = <FBottomNavigationBarItem>[
      for (var i = 0; i < tabs.length; i++)
        FBottomNavigationBarItem(
          icon: Icon(i == selectedIndex ? tabs[i].selectedIcon : tabs[i].icon),
          label: Text(tabs[i].label),
        ),
    ];

    // Long-press still opens the cross-domain switcher as a power-user
    // shortcut; the discoverable entry is now the header domain chip.
    // GestureDetector only intercepts long-press — taps pass through to
    // the inner FBottomNavigationBar via the default hit-test behaviour.
    final specs = ref.watch(activeDomainShellsProvider);
    final hasSwitcher = specs.length >= 2;

    return FScaffold(
      childPad: false,
      // The shell must NOT resize for the keyboard: every routed page builds
      // its own keyboard-aware scaffold (DomainTabScaffold / ObjectDetailScaffold
      // resize themselves; form pages own avoidance via AppFormScaffoldBody).
      // If the shell also resized, the inset would be counted twice, lifting
      // form action bars a keyboard-height above the IME with a blank band
      // between (see app_form_scaffold_body_keyboard_test.dart).
      resizeToAvoidBottomInset: false,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Wave 35 — persistent undo banner sits between content and
          // the bottom nav. Hidden when the stack is empty.
          const PersistentUndoBanner(),
          GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onLongPress: hasSwitcher
                ? () => showDomainSwitcherSheet(context, specs)
                : null,
            child: FBottomNavigationBar(
              index: selectedIndex,
              onChange: onDestinationSelected,
              safeAreaBottom: true,
              children: children,
            ),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TabletLayout extends StatelessWidget {
  const _TabletLayout({
    required this.tabs,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  final List<DomainShellTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FScaffold(
      childPad: false,
      // See _MobileLayout: the routed page owns keyboard avoidance; the shell
      // must not double-count the inset.
      resizeToAvoidBottomInset: false,
      sidebar: SizedBox(
        width: 80,
        child: Column(
          children: [
            Expanded(
              child: FSidebar(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    _TabletRailItem(
                      tab: tabs[i],
                      selected: i == selectedIndex,
                      onTap: () => onDestinationSelected(i),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: _TabletRailSettings(label: l10n.navSettings),
            ),
          ],
        ),
      ),
      child: child,
    );
  }
}

class _TabletRailSettings extends StatelessWidget {
  const _TabletRailSettings({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTappable(
      onPress: () => GoRouter.of(context).push(AppRoutes.settings),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.settings_outlined,
              color: colors.mutedForeground,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: context.theme.typography.xs.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.foreground,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletRailItem extends StatelessWidget {
  const _TabletRailItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final DomainShellTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final iconColor = selected ? colors.primary : colors.mutedForeground;
    final fill = selected ? colors.muted : Colors.transparent;
    return FTappable(
      onPress: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? tab.selectedIcon : tab.icon,
              color: iconColor,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: context.theme.typography.xs.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? colors.primary : colors.foreground,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.tabs,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  final List<DomainShellTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      childPad: false,
      // See _MobileLayout: the routed page owns keyboard avoidance; the shell
      // must not double-count the inset.
      resizeToAvoidBottomInset: false,
      sidebar: DesktopSidebar(
        destinations: [
          for (final t in tabs)
            DesktopSidebarDestination(
              icon: t.icon,
              selectedIcon: t.selectedIcon,
              label: t.label,
            ),
        ],
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
      ),
      child: child,
    );
  }
}
