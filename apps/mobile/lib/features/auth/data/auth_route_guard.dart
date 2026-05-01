import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_guard.dart';
import 'auth_controller.dart';

/// Login page route. The router declares it under this name; we reference
/// it from the guard so a typo here surfaces as a compile error rather
/// than a redirect loop.
const String kLoginPath = '/login';

/// Predicate: which paths are reachable while logged out?
///
/// Currently only the login page. The pairing-code flow on the new device
/// will be added here once the backend exposes pairing endpoints.
bool _isPublicPath(String location) {
  return location == kLoginPath;
}

class AuthRouteGuard implements RouteGuard {
  AuthRouteGuard(this._ref);

  final Ref _ref;

  @override
  RedirectPath redirect(GoRouterState state) {
    final auth = _ref.read(authControllerProvider);
    final value = auth.value;
    final location = state.matchedLocation;

    // While the controller is still booting (`AsyncLoading` with no prior
    // value) we let the destination render. Pages that need data will
    // surface their own loading state; the guard re-runs once the
    // controller settles because [authBootstrapWatcherProvider] bumps the
    // router refresh listenable.
    if (value == null) return null;

    final loggedIn = value is AuthLoggedIn;
    if (!loggedIn && !_isPublicPath(location)) {
      // Preserve the destination so we can bounce back after login.
      final target = state.uri.toString();
      if (target.isEmpty || target == '/') return kLoginPath;
      return Uri(
        path: kLoginPath,
        queryParameters: <String, String>{'next': target},
      ).toString();
    }
    if (loggedIn && location == kLoginPath) {
      // Already authed; honour `?next=` if it's a real in-app path,
      // otherwise drop to home.
      final next = state.uri.queryParameters['next'];
      if (next != null && next.startsWith('/') && next != kLoginPath) {
        return next;
      }
      return '/';
    }
    return null;
  }
}

/// Override-friendly factory for the guard list. Tests can swap this with
/// `overrideWithValue` to drop the guard entirely (route_guard_test does
/// this for FIR-15's redirect-machinery tests so they don't have to set
/// up auth state).
final authRouteGuardProvider = Provider<AuthRouteGuard>(AuthRouteGuard.new);
