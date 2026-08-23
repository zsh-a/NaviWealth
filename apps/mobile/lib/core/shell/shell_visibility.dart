/// Shell-tab visibility for offstage [StatefulShellRoute.indexedStack]
/// branches.
///
/// Indexed-stack tabs stay mounted when inactive. Without a pause signal,
/// their Riverpod watches keep Drift streams and chart rebuilds alive in the
/// background. [ShellTabPause] listens to the active GoRouter configuration
/// directly so visible and hidden shell branches share the same semantics.
/// The providers remain a lightweight fallback for standalone surfaces and
/// tests that intentionally render without a router.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Active route path fallback for trees rendered without GoRouter.
///
/// Empty string means "unknown / not under a domain shell" — treat as active
/// so standalone routes and tests keep working without shell plumbing.
final activeShellTabPathProvider = Provider<String>((ref) => '');

/// Whether the fallback active route belongs to the [routePath] tab root.
final shellTabIsActiveProvider = Provider.family<bool, String>((
  ref,
  routePath,
) {
  final active = ref.watch(activeShellTabPathProvider);
  return isShellTabPathActive(activeTabPath: active, routePath: routePath);
});

/// Pure helper for tests and non-Riverpod call sites.
bool isShellTabPathActive({
  required String activeTabPath,
  required String routePath,
}) {
  if (activeTabPath.isEmpty) return true;
  if (routePath.isEmpty) return true;
  return routePath == activeTabPath || activeTabPath.startsWith('$routePath/');
}

/// Keeps [child] mounted while its indexed-stack branch is offstage.
///
/// Replacing the live subtree with a placeholder used to dispose list state,
/// auto-dispose providers, and chart caches on every tab switch. The retained
/// subtree is hidden and has tickers disabled instead, so returning to a tab is
/// a warm reveal. The cheap [placeholder] remains available to standalone
/// harnesses that drive this gate without an outer indexed stack.
class ShellTabPause extends ConsumerWidget {
  const ShellTabPause({
    super.key,
    required this.routePath,
    required this.child,
    this.placeholder = const SizedBox.expand(),
  });

  /// Tab root path this surface belongs to (e.g. [FinanceRoutes.home]).
  final String routePath;

  /// Live tree retained across active and inactive tab states.
  final Widget child;

  /// Shown while offstage. Keep this cheap (no providers / charts).
  final Widget placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      return _buildForActive(ref.watch(shellTabIsActiveProvider(routePath)));
    }
    return AnimatedBuilder(
      animation: router.routerDelegate,
      builder: (context, _) {
        return _buildForActive(
          isShellTabPathActive(
            activeTabPath: _activeRouterPath(router),
            routePath: routePath,
          ),
        );
      },
    );
  }

  Widget _buildForActive(bool active) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: !active,
          child: TickerMode(enabled: active, child: child),
        ),
        if (!active) placeholder,
      ],
    );
  }
}

String _activeRouterPath(GoRouter router) {
  final configuration = router.routerDelegate.currentConfiguration;
  if (configuration.isEmpty) {
    return router.routeInformationProvider.value.uri.path;
  }
  final last = configuration.last;
  if (last is ImperativeRouteMatch) {
    return last.matches.uri.path;
  }
  return configuration.uri.path;
}
