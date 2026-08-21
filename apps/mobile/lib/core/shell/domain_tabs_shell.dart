import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../ai/write/persistent_undo_banner.dart';
import 'domain_shell.dart';
import 'domain_switcher.dart';
import 'sync_activity_strip.dart';

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

class _DomainTabsShellState extends ConsumerState<DomainTabsShell> {
  void _onSelected(int i) {
    widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.spec.tabs;
    final index = widget.shell.currentIndex;
    // Every shell branch must be declared on the spec — visible tabs first,
    // then hidden (routable-only) branches — so an under-declared spec fails
    // loudly in debug instead of silently dropping nav state.
    assert(
      index < tabs.length + widget.spec.hiddenTabs.length,
      'DomainTabsShell: branch $index of ${widget.spec.scope} has no matching '
      'visible or hidden tab in its DomainShellSpec',
    );
    // Branch roots are already retained by StatefulShellRoute.indexedStack.
    // _BranchFadeIn plays a fast fade-in on the newly selected branch while
    // keeping the shell at a stable element position — offstage branch state
    // and ShellTabPause stream pausing are untouched. The fade is bounded to
    // Motion.fast so the opacity compositing it forces on chart/glass
    // surfaces lasts one short window per switch, not the whole transition.
    final shellChild = _BranchFadeIn(activeIndex: index, child: widget.shell);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Navigation chrome is a window-level decision. At large widths the
        // app-level shell owns the unified workspace/tab sidebar; this inner
        // shell contributes no second desktop navigation surface.
        final width = MediaQuery.sizeOf(context).width;
        if (width >= DomainTabsShell._desktopBreakpoint) {
          return _withGlobalOverlays(_DesktopLayout(child: shellChild));
        }
        if (width >= DomainTabsShell._tabletBreakpoint) {
          return _withGlobalOverlays(
            _TabletLayout(
              tabs: tabs,
              selectedIndex: index,
              onDestinationSelected: _onSelected,
              child: shellChild,
            ),
          );
        }
        // Mobile mounts its own undo banner above the floating dock.
        return _withGlobalOverlays(
          undoBanner: false,
          _MobileLayout(
            tabs: tabs,
            selectedIndex: index,
            onDestinationSelected: _onSelected,
            child: shellChild,
          ),
        );
      },
    );
  }
}

/// Fast fade-in played on the newly selected shell branch.
///
/// The child is the [StatefulNavigationShell] itself — an indexed stack that
/// keeps every branch alive — so this wrapper must never swap or unmount it.
/// It stays at a fixed element position and only restarts its controller when
/// [activeIndex] changes; the first render shows the branch at full opacity.
///
/// Reduced motion resolves to [Duration.zero] via [AppMotionPolicy], so the
/// switch stays instant for users who opt out of animation.
class _BranchFadeIn extends StatefulWidget {
  const _BranchFadeIn({required this.activeIndex, required this.child});

  final int activeIndex;
  final Widget child;

  @override
  State<_BranchFadeIn> createState() => _BranchFadeInState();
}

class _BranchFadeInState extends State<_BranchFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, value: 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = AppMotionPolicy.reduceMotion(context)
        ? Duration.zero
        : Motion.fast;
  }

  @override
  void didUpdateWidget(covariant _BranchFadeIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeIndex != widget.activeIndex) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      key: const ValueKey<String>('domain-tabs-shell.branch-fade'),
      opacity: CurvedAnimation(
        parent: _controller,
        curve: Motion.standardDecelerate,
      ),
      child: widget.child,
    );
  }
}

/// Cross-layout overlays that must not be phone-only: the "AI changed X ·
/// undo" banner previously lived inside [_MobileLayout] alone, so every
/// tablet/desktop viewport silently lost the undo affordance (blueprint
/// doc 15 §7.3). Mobile keeps its own copy stacked above the floating dock.
Widget _withGlobalOverlays(Widget layout, {bool undoBanner = true}) {
  return Stack(
    children: [
      Positioned.fill(child: layout),
      if (undoBanner)
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(top: false, child: PersistentUndoBanner()),
        ),
      // Shell-level sync activity: a hairline strip at the very top of
      // every layout (doc 11 "完成同步" trigger).
      const Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: SafeArea(bottom: false, child: SyncActivityStrip()),
      ),
    ],
  );
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
    final switcherHomePath = ref.watch(domainSwitcherHomePathProvider);
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
        //
        // Tab roots get the full floating dock height (nav + safe area).
        // Pushed pages keep the device safe-area bottom so content does not
        // sit under the home indicator, without reserving dock space.
        final bottomInset = onTabRoot
            ? _dockTotalHeight(safeAreaBottom)
            : safeAreaBottom;
        final content = Positioned.fill(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: MediaQuery.of(
                context,
              ).padding.copyWith(bottom: bottomInset),
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
                                            switcherHomePath,
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

class _TabletLayout extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // Compact and tablet widths share the header workspace switcher. Keep
    // this rail domain-local so there is exactly one discoverable switcher
    // per shell tier; Ask AI remains available as a global rail action.
    final assistantAction = ref.watch(domainTabsAssistantActionProvider);
    final l10n = AppLocalizations.of(context);
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
            if (assistantAction != null) ...[
              const FDivider(),
              _TabletRailAction(
                icon: FLucideIcons.sparkles,
                label: l10n.navAskAi,
                onTap: () => assistantAction(context, ref),
              ),
            ],
          ],
        ),
      ),
      child: child,
    );
  }
}

/// Rail entry for non-tab actions (domain switcher, Ask-AI). Mirrors
/// [_TabletRailItem]'s metrics in its unselected state.
class _TabletRailAction extends StatelessWidget {
  const _TabletRailAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return AppTappable(
      onPress: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s4,
        ),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colors.mutedForeground, size: AppIconSizes.mlg),
            const SizedBox(height: AppSpacing.s4),
            Text(
              label,
              style: context.captionMediumStyle.copyWith(
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
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: AppTappable(
        onPress: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.s4,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppSelectionIndicator(
                  selected: selected,
                  axis: Axis.vertical,
                  length: AppSpacing.s24,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s10),
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
                                color: selected
                                    ? colors.primary
                                    : colors.mutedForeground,
                              ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
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
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      childPad: false,
      // See _MobileLayout: the routed page owns keyboard avoidance; the shell
      // must not double-count the inset.
      resizeToAvoidBottomInset: false,
      child: child,
    );
  }
}
