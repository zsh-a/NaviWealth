import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../ai/write/persistent_undo_banner.dart';
import 'desktop_sidebar.dart';
import 'domain_shell.dart';
import 'domain_switcher.dart';

const double _kMobileDockHorizontalPadding = AppSpacing.s16;
const double _kMobileDockTopPadding = AppSpacing.s4;
const double _kMobileDockBottomPadding = AppSpacing.s10;

typedef DomainTabsAssistantAction =
    void Function(BuildContext context, WidgetRef ref);

final domainTabsAssistantActionProvider = Provider<DomainTabsAssistantAction?>(
  (ref) => null,
);

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
  static const double _desktopBreakpoint = Breakpoints.shellDesktop;

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
    _controller = AnimationController(vsync: this);
    _fade = CurvedAnimation(
      parent: _controller,
      curve: Motion.emphasizedDecelerate,
    );
    _controller.value = 1.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = AppMotionPolicy.duration(context, Motion.medium);
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
      if (!AppMotionPolicy.isEnabled(context, role: AppMotionRole.transition)) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  void _onSelected(int i) {
    widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.spec.tabs;
    final index = widget.shell.currentIndex;
    // StatefulNavigationShell owns a GlobalKey and must stay mounted exactly
    // once. Animate its presentation in place instead of cross-fading two
    // keyed snapshots, which would retain the same shell in both subtrees.
    final animatedChild = FadeTransition(opacity: _fade, child: widget.shell);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Navigation chrome is a window-level decision. The outer domain dock
        // and the inner tab rail both consume horizontal space, so using this
        // widget's reduced constraints would make the desktop threshold drift.
        final width = MediaQuery.sizeOf(context).width;
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

  /// Total visual height reserved for the floating dock:
  /// nav bar + top/bottom spacing + device safe-area inset.
  double _dockTotalHeight(double safeAreaBottom) =>
      kFloatingGlassNavBarHeight +
      _kMobileDockTopPadding +
      _kMobileDockBottomPadding +
      safeAreaBottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Long-press still opens the cross-domain switcher as a power-user
    // shortcut; the discoverable entry is now the header domain chip.
    final specs = ref.watch(activeDomainShellsProvider);
    final hasSwitcher = specs.length >= 2;
    final assistantAction = ref.watch(domainTabsAssistantActionProvider);
    final l10n = AppLocalizations.of(context);

    // Convert domain tabs to FloatingNavTab items.
    final navTabs = [
      for (final tab in tabs)
        FloatingNavTab(
          icon: tab.icon,
          selectedIcon: tab.selectedIcon,
          label: tab.label,
        ),
    ];

    // Read MediaQuery OUTSIDE the ValueListenableBuilder so keyboard
    // changes don't trigger nav-bar rebuilds, and vice versa.
    final safeAreaBottom = MediaQuery.paddingOf(context).bottom;

    final router = GoRouter.of(context);

    // The router delegate sees imperative `push()` routes inside a branch;
    // routeInformationProvider can remain at the tab root for those pages.
    // Keep sheet depth as its own listener so overlays don't rebuild routing.
    return AnimatedBuilder(
      animation: router.routerDelegate,
      builder: (context, _) {
        final path = _activePath(router);
        final onTabRoot = tabs.any((tab) => tab.routePath == path);

        // Keep the routed page's viewport stable while overlays open. The
        // sheet only needs to hide the floating dock; changing MediaQuery
        // padding here would relayout the entire page during the sheet's
        // entrance animation (particularly expensive for chart dashboards).
        final dockHeight = onTabRoot ? _dockTotalHeight(safeAreaBottom) : 0.0;
        final content = Positioned.fill(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: MediaQuery.of(
                context,
              ).padding.copyWith(bottom: dockHeight),
            ),
            child: child,
          ),
        );

        return ValueListenableBuilder<int>(
          valueListenable: appSheetOverlayDepthListenable,
          child: content,
          builder: (context, sheetDepth, content) {
            final sheetOpen = sheetDepth > 0;
            final showNav = onTabRoot && !sheetOpen;

            return FScaffold(
              childPad: false,
              resizeToAvoidBottomInset: false,
              child: Stack(
                children: [
                  // Passed through ValueListenableBuilder.child so opening a
                  // sheet cannot rebuild or relayout the routed page.
                  content!,
                  // Floating dock — layered above content.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: sheetOpen
                        ? const SizedBox.shrink()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const PersistentUndoBanner(),
                              if (showNav)
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    _kMobileDockHorizontalPadding,
                                    _kMobileDockTopPadding,
                                    _kMobileDockHorizontalPadding,
                                    _kMobileDockBottomPadding + safeAreaBottom,
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
                                      onAssistantAction: assistantAction == null
                                          ? null
                                          : () => assistantAction(context, ref),
                                      assistantLabel: l10n.navAskAi,
                                      assistantSemanticLabel:
                                          l10n.commandPaletteOpenAi,
                                    ),
                                  ),
                                ),
                            ],
                          ),
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

String _activePath(GoRouter router) {
  final config = router.routerDelegate.currentConfiguration;
  if (config.isEmpty) {
    return router.routeInformationProvider.value.uri.path;
  }
  final last = config.last;
  if (last is ImperativeRouteMatch) {
    return last.matches.uri.path;
  }
  return config.uri.path;
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
    return FScaffold(
      childPad: false,
      // See _MobileLayout: the routed page owns keyboard avoidance; the shell
      // must not double-count the inset.
      resizeToAvoidBottomInset: false,
      sidebar: SizedBox(
        width: AppControlWidths.tabletRail,
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
      child: child,
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
              style:
                  (selected
                          ? context.captionLabelStyle
                          : context.captionMediumStyle)
                      .copyWith(
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
