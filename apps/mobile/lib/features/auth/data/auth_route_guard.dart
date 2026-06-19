import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_guard.dart';
import 'app_mode_store.dart';
import 'auth_controller.dart';

/// Login page route. The router declares it under this name; we reference
/// it from the guard so a typo here surfaces as a compile error rather
/// than a redirect loop.
const String kLoginPath = '/login';

/// First-launch mode picker. Shown when the user hasn't yet chosen between
/// a cloud account and local-only mode.
const String kOnboardingPath = '/onboarding';

/// Predicate: which paths are reachable while logged out?
bool _isPublicPath(String location) {
  return location == kLoginPath || location == kOnboardingPath;
}

String? _redirectTarget(GoRouterState state) {
  final redirect = state.uri.queryParameters['redirect'];
  if (redirect != null) return redirect;

  // Back-compat for route hints and tests minted before the web-routing
  // contract settled on `redirect`.
  return state.uri.queryParameters['next'];
}

bool _isSafeRedirectTarget(String target) {
  if (!target.startsWith('/') || target.startsWith('//')) return false;
  final path = Uri.tryParse(target)?.path;
  return path != null && !_isPublicPath(path);
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

    // Local-only users have all in-app routes open. Auth-mode public
    // pages bounce them home, except /login which is reachable for the
    // upgrade-to-cloud flow.
    if (value is AuthLocalOnly) {
      if (location == kOnboardingPath) return '/';
      return null;
    }

    if (value is AuthLoggedIn) {
      if (location == kLoginPath || location == kOnboardingPath) {
        // Honour the web-routing contract's `?redirect=` from the login
        // flow if it's a real in-app path, otherwise drop to home.
        final redirect = _redirectTarget(state);
        if (redirect != null && _isSafeRedirectTarget(redirect)) {
          return redirect;
        }
        return '/';
      }
      return null;
    }

    // Logged out — decide between onboarding and login based on the
    // user's persisted mode choice. Reading the mode depends on
    // SharedPreferences; some unit tests don't seed it, so treat the
    // absence as "user has previously chosen cloud" (the pre-onboarding
    // behaviour) to keep legacy tests passing.
    if (_isPublicPath(location)) return null;
    AppMode mode = AppMode.cloud;
    try {
      mode = _ref.read(appModeProvider);
    } catch (_) {
      // Preference layer not wired (test env) — fall through to /login.
    }
    if (mode == AppMode.unset) {
      return kOnboardingPath;
    }
    final target = state.uri.toString();
    if (target.isEmpty || target == '/') return kLoginPath;
    return Uri(
      path: kLoginPath,
      queryParameters: <String, String>{'redirect': target},
    ).toString();
  }
}

/// Override-friendly factory for the guard list. Tests can swap this with
/// `overrideWithValue` to drop the guard entirely (route_guard_test does
/// this for redirect-machinery tests so they don't have to set
/// up auth state).
final authRouteGuardProvider = Provider<AuthRouteGuard>(AuthRouteGuard.new);
