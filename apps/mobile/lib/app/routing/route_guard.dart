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

final domainOptInRouteGuardProvider = Provider<DomainOptInRouteGuard>(
  DomainOptInRouteGuard.new,
);
