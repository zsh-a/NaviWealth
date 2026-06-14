import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/domain_scope.dart';
import '../core/auth/providers.dart';
import '../core/lifeos/domain_pack.dart';
import 'route_paths.dart';

/// Decision returned by a [RouteGuard]. `null` means "let the requested route
/// proceed"; a non-null path means "redirect there instead".
typedef RedirectPath = String?;

/// Pluggable guard. Inspect [state] (the destination the user is trying to
/// reach) and either return `null` or the path to redirect to.
///
/// Guards run in registration order; the first non-null result wins. Don't
/// use guards to do expensive async work — the redirect callback is sync. If
/// a guard depends on an async source (e.g. session restore from disk),
/// expose a Riverpod provider for that source and watch it from a wrapper
/// guard, then bump [routeRedirectVersionProvider] when the source changes.
abstract class RouteGuard {
  RedirectPath redirect(GoRouterState state);
}

/// Empty default. Overridden once auth lands; until then every route
/// is reachable.
final routeGuardsProvider = Provider<List<RouteGuard>>((_) => const []);

/// Monotonic counter consumed by [routeRefreshListenableProvider]. Bump it
/// (`ref.read(routeRedirectVersionProvider.notifier).state++`) whenever the
/// inputs to your guards change so go_router re-evaluates the current route
/// and applies the new redirect decision.
final routeRedirectVersionProvider = StateProvider<int>((_) => 0);

/// Bridge between Riverpod and go_router's `refreshListenable`. Reading this
/// returns a [Listenable] that fires whenever guard inputs change, prompting
/// go_router to re-run [routerRedirect].
final routeRefreshListenableProvider = Provider<Listenable>((ref) {
  final notifier = ValueNotifier<int>(ref.read(routeRedirectVersionProvider));
  ref.listen<int>(routeRedirectVersionProvider, (_, _) {
    notifier.value++;
  });
  ref.listen<AsyncValue<DomainOptIns>>(domainOptInsProvider, (_, _) {
    notifier.value++;
  });
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// Composes the registered [RouteGuard]s into a single `redirect` callback
/// for [GoRouter]. Returns the first non-null redirect, or `null` if every
/// guard says "go ahead".
String? routerRedirect(
  ProviderContainer container,
  BuildContext context,
  GoRouterState state,
) {
  final guards = container.read(routeGuardsProvider);
  for (final guard in guards) {
    final target = guard.redirect(state);
    if (target != null && target != state.matchedLocation) return target;
  }
  return null;
}

/// Blocks deep links into optional domains until the user opts in.
///
/// Routes are mounted unconditionally so deep links remain structurally valid,
/// but business surfaces for inactive domains should not be reachable.
class DomainOptInRouteGuard implements RouteGuard {
  DomainOptInRouteGuard(this._ref);

  final Ref _ref;

  @override
  RedirectPath redirect(GoRouterState state) {
    final optIns = _ref.read(domainOptInsProvider).value;
    if (optIns == null) return null;

    final owner = domainForRoute(
      _ref.read(domainPackRegistryProvider),
      state.uri.path,
    );
    if (owner == null || optIns.contains(owner)) return null;
    return AppRoutes.settings;
  }
}

final domainOptInRouteGuardProvider = Provider<DomainOptInRouteGuard>(
  DomainOptInRouteGuard.new,
);
