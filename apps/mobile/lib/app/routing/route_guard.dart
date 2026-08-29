import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/providers.dart';
import '../../core/lifeos/domain_pack.dart';
import '../../core/shell/route_guard.dart';
import '../../core/shell/settings_route_paths.dart';
import 'route_paths.dart';

export '../../core/shell/route_guard.dart';

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
    // `blocked` lets the domains page explain the redirect instead of
    // silently teleporting the user (doc 15 §7.7).
    return '${SettingsRoutes.domains}?blocked=${owner.name}';
  }
}

/// Keeps the cross-domain Life brief out of the way for Finance-only users.
///
/// Life becomes the default workspace once at least one optional domain is
/// active. A fresh install has one domain and should land directly on the
/// Finance Today workflow instead of showing a second summary of it.
class LifeHomeRouteGuard implements RouteGuard {
  LifeHomeRouteGuard(this._ref);

  final Ref _ref;

  @override
  RedirectPath redirect(GoRouterState state) {
    if (state.uri.path != AppRoutes.life) return null;
    final optIns = _ref.read(domainOptInsProvider).value;
    if (optIns == null || optIns.active.length > 1) return null;
    return AppRoutes.home;
  }
}

final domainOptInRouteGuardProvider = Provider<DomainOptInRouteGuard>(
  DomainOptInRouteGuard.new,
);

final lifeHomeRouteGuardProvider = Provider<LifeHomeRouteGuard>(
  LifeHomeRouteGuard.new,
);
