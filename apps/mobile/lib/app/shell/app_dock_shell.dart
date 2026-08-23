import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/ai/composition/ai_context.dart';
import '../../core/ai/composition/ask_ai.dart';
import '../../core/developer/developer_issue.dart';
import '../../core/developer/providers.dart';
import '../../core/lifeos/domain_pack.dart';
import '../../core/shell/desktop_sidebar.dart';
import '../../core/shell/domain_shell.dart';
import '../../core/shell/domain_switcher.dart';
import '../../design_system/design_system.dart';
import '../../features/settings/ui/ai/ai_privacy_onboarding.dart';
import '../../l10n/gen/app_localizations.dart';
import '../routing/route_paths.dart';
import '../share_intents/share_intent_service.dart';

/// Outer multi-domain shell (`docs/architecture/lifeos-shell.md` §3 Option B, D-2.3b).
///
/// Lives one layer above each domain's `StatefulShellRoute`:
///
///   ShellRoute (this)
///   ├── financeShellRoute    (4 branches → DomainTabsShell)
///   ├── healthShellRoute     (2 branches → DomainTabsShell)
///   └── knowledgeShellRoute  (3 branches → DomainTabsShell)
///
/// Responsibilities the inner per-domain shells should *not* duplicate:
///   * share-intent lifecycle (mounts once, survives domain switches)
///   * `aiContextProvider` sync (route + domain, location-driven, global)
///   * root-level system back handling (pop → exit-arm)
///   * adaptive shell chrome — desktop merges workspace switching and
///     domain-local tabs into one sidebar. Compact/tablet layouts keep the
///     domain switcher in page headers; see `domain_switcher.dart`.
///   * `aiContextProvider.domain` — derived from the active route via
///     `domainForRoute`; the `askAi` helper reads this so no call site
///     needs to know which OS it's invoked from.
class AppDockShell extends ConsumerStatefulWidget {
  const AppDockShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppDockShell> createState() => _AppDockShellState();
}

class _AppDockShellState extends ConsumerState<AppDockShell> {
  late final ShareIntentService _shareIntentService;
  GoRouter? _router;
  bool _routeSyncScheduled = false;

  @override
  void initState() {
    super.initState();
    // §5.10.10 / S5c-native — app-wide share receiver. Self-guarded:
    // a no-op wherever the share channel is absent (tests / web /
    // desktop), so this is safe to start unconditionally here.
    _shareIntentService = ref.read(shareIntentServiceProvider);
    _shareIntentService.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (!identical(router, _router)) {
      _router?.routerDelegate.removeListener(_onRouteChanged);
      _router = router;
      _router!.routerDelegate.addListener(_onRouteChanged);
      _scheduleRouteSync();
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    _shareIntentService.stop();
    super.dispose();
  }

  void _onRouteChanged() {
    if (_router == null || !mounted) return;
    _scheduleRouteSync();
  }

  void _scheduleRouteSync() {
    if (_routeSyncScheduled) return;
    _routeSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeSyncScheduled = false;
      final router = _router;
      if (router == null || !mounted) return;
      _syncRoute(router);
    });
  }

  void _syncRoute(GoRouter router) {
    final location = router.routeInformationProvider.value.uri.path;
    final nextDomain = domainForRoute(
      ref.read(domainPackRegistryProvider),
      location,
    );
    if (nextDomain != null) {
      ref.read(developerIssueContextProvider.notifier).state =
          DeveloperIssueContext(route: location, domain: nextDomain.name);
    }
    final current = ref.read(aiContextProvider);
    if (current.path != location || current.domain != nextDomain) {
      ref.read(aiContextProvider.notifier).state = AiContext(
        path: location,
        domain: nextDomain,
      );
    }
  }

  /// Root back-button strategy. Defers steps 1–3 ("pop a pushed page /
  /// dismiss a modal / clear `?selected=`") to the shared [attemptBack]
  /// primitive so system back, the toolbar arrow, and the Esc shortcut
  /// stay in lockstep; only the app-shell-specific tail lives here:
  ///  1–3. delegated to [attemptBack];
  ///  4. at a non-first tab root or contextual review root → return to
  ///     the domain's first tab (doc 15 §7.5 — previously back at ANY
  ///     tab root went straight to the exit prompt);
  ///  5. at the domain's first tab root → fall through to
  ///     [ExitConfirmingSystemBackScope].
  bool _handleSystemBackBeforeExit(BuildContext context) {
    if (attemptBack(context)) return true;
    final router = GoRouter.of(context);
    final path = router.routeInformationProvider.value.uri.path;
    final packs = ref.read(activeDomainPacksProvider);
    final tabs = domainTabPathsForLocation(packs, path);
    if (tabs.length > 1 && tabs.contains(path) && path != tabs.first) {
      router.go(tabs.first);
      return true;
    }
    for (final pack in packs) {
      if (pack.reviewRoutePath == path && pack.tabPaths.isNotEmpty) {
        router.go(pack.tabPaths.first);
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final specs = ref.watch(activeDomainShellsProvider);
    final router = GoRouter.of(context);
    return AnimatedBuilder(
      animation: router.routerDelegate,
      child: widget.child,
      builder: (context, child) {
        final location = router.routeInformationProvider.value.uri.path;
        final routedChild = child ?? const SizedBox.shrink();
        final shellChild = specs.isEmpty
            ? routedChild
            : _DockChrome(
                specs: specs,
                activePath: location,
                child: routedChild,
              );

        return ExitConfirmingSystemBackScope(
          onBack: _handleSystemBackBeforeExit,
          disarmKey: location,
          child: _ShellGlobalMounts(child: shellChild),
        );
      },
    );
  }
}

class _ShellGlobalMounts extends StatelessWidget {
  const _ShellGlobalMounts({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        const IgnorePointer(child: AiPrivacyOnboardingMount()),
      ],
    );
  }
}

class _DockChrome extends StatelessWidget {
  const _DockChrome({
    required this.specs,
    required this.activePath,
    required this.child,
  });

  final List<DomainShellSpec> specs;
  final String activePath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        if (viewportWidth < Breakpoints.shellDesktop) {
          // Compact and tablet layouts already expose the workspace switcher
          // in the page header. The domain shell continues to own its bottom
          // bar / compact rail at these widths.
          return child;
        }
        return Row(
          children: [
            _UnifiedDesktopSidebar(
              specs: specs,
              activePath: activePath,
              forceCollapsed: viewportWidth < Breakpoints.shellExpandedSidebar,
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class _UnifiedDesktopSidebar extends ConsumerWidget {
  const _UnifiedDesktopSidebar({
    required this.specs,
    required this.activePath,
    required this.forceCollapsed,
  });

  final List<DomainShellSpec> specs;
  final String activePath;
  final bool forceCollapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final homePath = ref.watch(domainSwitcherHomePathProvider);
    final onLife =
        activePath == AppRoutes.life ||
        activePath.startsWith('${AppRoutes.life}/');
    final activeSpec = activeSpecForPath(specs, activePath);
    final selectedTab = activeSpec.tabs.indexWhere(
      (tab) =>
          activePath == tab.routePath ||
          activePath.startsWith('${tab.routePath}/'),
    );
    final workspaceLabel = onLife ? l10n.lifeNavLabel : activeSpec.label;
    final workspaceIcon = onLife ? FLucideIcons.house : activeSpec.selectedIcon;
    final destinations = <DesktopSidebarDestination>[
      DesktopSidebarDestination(
        icon: FLucideIcons.house,
        selectedIcon: FLucideIcons.house,
        label: l10n.lifeNavLabel,
      ),
      if (!onLife)
        for (final tab in activeSpec.tabs)
          DesktopSidebarDestination(
            icon: tab.icon,
            selectedIcon: tab.selectedIcon,
            label: tab.label,
          ),
    ];
    return DesktopSidebar(
      workspace: DesktopSidebarWorkspace(
        icon: workspaceIcon,
        label: workspaceLabel,
        onPress: () => showDomainSwitcherSheet(context, specs, homePath),
      ),
      destinations: destinations,
      selectedIndex: onLife
          ? 0
          : selectedTab < 0
          ? -1
          : selectedTab + 1,
      onDestinationSelected: (index) {
        AppInteraction.signal(AppInteractionIntent.navigate);
        if (index == 0) {
          GoRouter.of(context).go(AppRoutes.life);
          return;
        }
        GoRouter.of(context).go(activeSpec.tabs[index - 1].routePath);
      },
      footerActions: [
        DesktopSidebarAction(
          icon: FLucideIcons.sparkles,
          label: l10n.navAskAi,
          onPress: () => askAi(context, ref),
          emphasized: true,
        ),
      ],
      forceCollapsed: forceCollapsed,
    );
  }
}
