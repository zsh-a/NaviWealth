import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../core/ai/write/persistent_undo_banner.dart';
import '../core/shell/domain_shell.dart';
import '../design_system/design_system.dart';
import '../features/ai_chat/ui/ask_ai.dart';
import '../l10n/gen/app_localizations.dart';
import 'desktop_sidebar.dart';
import 'domain_switcher.dart';
import 'route_paths.dart';

const double _kMobileDockHorizontalPadding = AppSpacing.s28;
const double _kMobileDockTopPadding = AppSpacing.s4;
const double _kMobileDockBottomPadding = AppSpacing.s10;

/// Per-domain shell builder. One [DomainTabsShell] per LifeOS domain;
/// each lives at `features/<domain>/composition/<domain>_routes.dart`
/// inside that domain's `StatefulShellRoute.indexedStack(builder: ...)`.
///
/// Renders the domain's tabs (mobile bottom nav / tablet rail / desktop
/// sidebar) plus the [StatefulNavigationShell] content. The cross-domain
/// dock chrome is rendered by the *outer* `AppDockShell` (see
/// `app_dock_shell.dart`) — this widget is dock-agnostic.
class DomainTabsShell extends ConsumerStatefulWidget {
  const DomainTabsShell({super.key, required this.shell, required this.spec});

  final StatefulNavigationShell shell;
  final DomainShellSpec spec;

  // Breakpoints from design_system/tokens/breakpoints.dart
  static const double _tabletBreakpoint = Breakpoints.mobile;
  static const double _desktopBreakpoint = Breakpoints.desktop;

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
    widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex);
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

  double _dockReserve(BuildContext context) =>
      kFloatingGlassNavBarHeight +
      _kMobileDockTopPadding +
      _kMobileDockBottomPadding +
      MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Long-press still opens the cross-domain switcher as a power-user
    // shortcut; the discoverable entry is now the header domain chip.
    final specs = ref.watch(activeDomainShellsProvider);
    final hasSwitcher = specs.length >= 2;

    // Convert domain tabs to FloatingNavTab items.
    final navTabs = [
      for (final tab in tabs)
        FloatingNavTab(
          icon: tab.icon,
          selectedIcon: tab.selectedIcon,
          label: tab.label,
        ),
    ];

    final router = GoRouter.of(context);
    final routeListenable = router.routeInformationProvider;
    return ValueListenableBuilder(
      valueListenable: routeListenable,
      builder: (context, _, _) {
        final path = routeListenable.value.uri.path;
        final onTabRoot = tabs.any((tab) => tab.routePath == path);

        return ValueListenableBuilder<int>(
          valueListenable: appSheetOverlayDepthListenable,
          builder: (context, sheetDepth, _) {
            final sheetOpen = sheetDepth > 0;
            final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
            final showNav = onTabRoot && !sheetOpen && !keyboardOpen;
            final dockReserve = showNav ? _dockReserve(context) : 0.0;

            return FScaffold(
              childPad: false,
              // The shell must NOT resize for the keyboard: every routed page builds
              // its own keyboard-aware scaffold (DomainTabScaffold / ObjectDetailScaffold
              // resize themselves; form pages own avoidance via AppFormScaffoldBody).
              // If the shell also resized, the inset would be counted twice, lifting
              // form action bars a keyboard-height above the IME with a blank band
              // between (see app_form_scaffold_body_keyboard_test.dart).
              resizeToAvoidBottomInset: false,
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: Motion.medium,
                    curve: Motion.standard,
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: dockReserve,
                    child: child,
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: sheetOpen
                        ? const SizedBox.shrink()
                        : showNav
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Persistent undo banner sits between content and
                              // the bottom nav. Hidden when the stack is empty.
                              const PersistentUndoBanner(),
                              // Floating glass nav bar with center AI button.
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  _kMobileDockHorizontalPadding,
                                  _kMobileDockTopPadding,
                                  _kMobileDockHorizontalPadding,
                                  _kMobileDockBottomPadding +
                                      MediaQuery.paddingOf(context).bottom,
                                ),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.deferToChild,
                                  onLongPress: hasSwitcher
                                      ? () => showDomainSwitcherSheet(
                                          context,
                                          specs,
                                        )
                                      : null,
                                  child: FloatingGlassNavBar(
                                    items: navTabs,
                                    selectedIndex: selectedIndex,
                                    onIndexChanged: onDestinationSelected,
                                    onCenterAction: () => askAi(context, ref),
                                    centerLabel: 'AI',
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const PersistentUndoBanner(),
                  ),
                ],
              ),
            );
          },
        );
      },
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
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s4,
        ),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FLucideIcons.settings,
              color: colors.mutedForeground,
              size: AppIconSizes.mlg,
            ),
            const SizedBox(height: AppSpacing.s4),
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
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s4,
        ),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? tab.selectedIcon : tab.icon,
              color: iconColor,
              size: AppIconSizes.mlg,
            ),
            const SizedBox(height: AppSpacing.s4),
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
