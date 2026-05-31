import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/route_guard.dart';
import '../../../core/auth/auth_errors.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/auth/device_identity_store.dart';
import '../../../core/auth/providers.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/logging/providers.dart';
import 'app_mode_store.dart';

// Re-export state types for backward compatibility — existing feature-level
// imports of `AuthState`, `AuthLoggedIn`, `AuthLocalOnly`, etc. continue to
// work from this barrel.
export '../../../core/auth/auth_state.dart';

/// Single source of truth for the auth flow. Persists the session,
/// surfaces sync state to the router, and coordinates token rotation.
///
/// Concrete state transitions:
///   1. `build()` reads the persisted session via [TokenStore]. If absent
///      or expired (the JWT's own `exp`), emits [AuthLoggedOut] — note that
///      we don't try to refresh expired tokens, since the backend rejects
///      them on `/auth/refresh` too (HS256 + `exp` check).
///   2. [login] calls the API, persists the session, emits [AuthLoggedIn].
///   3. [logoutCurrent] calls `POST /auth/logout/:current_device_id`, clears
///      storage, and emits `AuthLoggedOut(reason: manuallyLoggedOut)`.
///   4. [refreshIfPossible] is the single entry point used by the API
///      interceptor and by the controller itself before sensitive calls.
///      Single-flight: concurrent calls share the same future.
///   5. On any 401 (caught by the interceptor) [refreshIfPossible] runs;
///      if it itself 401s, we [_clearSession] and emit
///      `AuthLoggedOut(reason: sessionExpired)` so the router redirects
///      to `/login`.
class AuthController extends AsyncNotifier<AuthState> {
  Future<bool>? _inFlightRefresh;

  @override
  Future<AuthState> build() async {
    // After the initial read settles, re-evaluate the active route. The
    // router was constructed before the persisted session resolved, so
    // without this the deep-linked page stays mounted under a logged-out
    // session until the next user-driven navigation.
    listenSelf((prev, next) {
      if (prev?.value.runtimeType == next.value.runtimeType) {
        return;
      }
      _bumpRouterRedirect();
    });
    // Local-only mode is sticky and takes precedence over any persisted
    // session — the choice is one-way per product decision. Reading the
    // mode depends on SharedPreferences; some unit tests don't seed it,
    // so swallow that error and treat the absence as "no preference yet".
    AppMode mode = AppMode.unset;
    try {
      mode = ref.read(appModeProvider);
    } catch (_) {
      // Preference layer not wired (test env) — proceed as if unset.
    }
    if (mode == AppMode.localOnly) {
      // Defensive: clear any stale token so the two never coexist.
      await ref.read(tokenStoreProvider).clear();
      return const AuthLocalOnly();
    }
    final store = ref.read(tokenStoreProvider);
    final session = await store.read();
    if (session == null) return const AuthLoggedOut();
    if (session.isExpired()) {
      await store.clear();
      return const AuthLoggedOut(reason: LoggedOutReason.sessionExpired);
    }
    await ref.read(deviceIdentityStoreProvider).remember(session.deviceId);
    return AuthLoggedIn(session);
  }

  /// Synchronous reader used by the interceptor's `Authorization` header
  /// stamp. Returns `null` while the controller is still booting (before
  /// the first read of `TokenStore` resolves) — in that window the
  /// AuthGuard parks navigation on a splash anyway, so requests aren't
  /// going out yet.
  AuthSession? currentSession() {
    final value = state.value;
    return value is AuthLoggedIn ? value.session : null;
  }

  Future<void> login({
    required String email,
    required String password,
    String? deviceName,
  }) async {
    final api = ref.read(authApiClientProvider);
    final store = ref.read(tokenStoreProvider);
    final deviceIdentity = ref.read(deviceIdentityStoreProvider);
    final logger = ref.read(loggerProvider);
    final deviceId = await deviceIdentity.getOrCreate();

    final session = await api.login(
      email: email,
      password: password,
      deviceName: deviceName,
      deviceId: deviceId,
    );
    await _persistCloudSession(
      session: session,
      requestedDeviceId: deviceId,
      store: store,
      deviceIdentity: deviceIdentity,
    );
    logger.i('auth_login_success user=${session.userId}');
  }

  Future<void> register({
    required String email,
    required String password,
    String? deviceName,
  }) async {
    final api = ref.read(authApiClientProvider);
    final store = ref.read(tokenStoreProvider);
    final deviceIdentity = ref.read(deviceIdentityStoreProvider);
    final logger = ref.read(loggerProvider);
    final deviceId = await deviceIdentity.getOrCreate();

    final session = await api.register(
      email: email,
      password: password,
      deviceName: deviceName,
      deviceId: deviceId,
    );
    await _persistCloudSession(
      session: session,
      requestedDeviceId: deviceId,
      store: store,
      deviceIdentity: deviceIdentity,
    );
    logger.i('auth_register_success user=${session.userId}');
  }

  Future<void> _persistCloudSession({
    required AuthSession session,
    required String requestedDeviceId,
    required TokenStore store,
    required DeviceIdentityStore deviceIdentity,
  }) async {
    if (session.deviceId != requestedDeviceId) {
      await deviceIdentity.remember(session.deviceId);
    }
    await store.write(session);
    // Lock in the cloud mode so a cold start doesn't bounce the user
    // back through onboarding. Defensive try/catch keeps tests that
    // don't inject SharedPreferences passing.
    try {
      await ref.read(appModeStoreProvider).write(AppMode.cloud);
      ref.invalidate(appModeProvider);
    } catch (_) {
      // Preference layer not wired (test env) — skip the mode bump.
    }
    state = AsyncData(AuthLoggedIn(session));
    _bumpRouterRedirect();
  }

  /// Opt into local-only mode. Persists the mode flag, drops any stale
  /// token, and emits [AuthLocalOnly] so the router lands the user on
  /// home. One-way per product decision.
  Future<void> enterLocalOnlyMode() async {
    await ref.read(appModeStoreProvider).write(AppMode.localOnly);
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(AuthLocalOnly());
    ref.invalidate(appModeProvider);
    _bumpRouterRedirect();
  }

  /// Mark the user's mode preference as `cloud` so the next router redirect
  /// sends them to /login instead of /onboarding. Does NOT change the
  /// auth state (still [AuthLoggedOut]); the actual session is established
  /// by [login].
  Future<void> chooseCloud() async {
    await ref.read(appModeStoreProvider).write(AppMode.cloud);
    ref.invalidate(appModeProvider);
    _bumpRouterRedirect();
  }

  /// Logs out the *current* device. Best-effort: a network failure here
  /// still clears local state because the user's intent is "I want this
  /// device logged out" — the device row will time out on the server when
  /// `exp` passes anyway.
  Future<void> logoutCurrent() async {
    final session = currentSession();
    if (session == null) {
      _clearSessionState(LoggedOutReason.manuallyLoggedOut);
      return;
    }
    final api = ref.read(authApiClientProvider);
    final logger = ref.read(loggerProvider);
    try {
      await api.logoutDevice(session, session.deviceId);
    } on AuthException catch (e) {
      logger.w('auth_logout_remote_failed kind=${e.kind.name}');
    }
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(
      AuthLoggedOut(reason: LoggedOutReason.manuallyLoggedOut),
    );
    logger.i('auth_logout_success user=${session.userId}');
    _bumpRouterRedirect();
  }

  /// Single-flight refresh. The interceptor calls this on a 401; the result
  /// is `true` when the new session is persisted and consumers can retry,
  /// `false` when the refresh itself failed (in which case we've already
  /// cleared local state and routed to `/login`).
  Future<bool> refreshIfPossible() {
    final pending = _inFlightRefresh;
    if (pending != null) return pending;
    final future = _refreshNow();
    _inFlightRefresh = future;
    return future.whenComplete(() => _inFlightRefresh = null);
  }

  Future<bool> _refreshNow() async {
    final session = currentSession();
    if (session == null || session.isExpired()) return false;
    final api = ref.read(authApiClientProvider);
    final store = ref.read(tokenStoreProvider);
    final logger = ref.read(loggerProvider);
    try {
      final rotated = await api.refresh(session);
      final updated = session.withRotatedToken(
        accessToken: rotated.accessToken,
        expiresAt: rotated.expiresAt,
      );
      await store.write(updated);
      state = AsyncData(AuthLoggedIn(updated));
      return true;
    } on AuthException catch (e) {
      // Refresh failed — the only sane next step is to drop the session.
      logger.i('auth_session_expired kind=${e.kind.name}');
      await store.clear();
      state = const AsyncData(
        AuthLoggedOut(reason: LoggedOutReason.sessionExpired),
      );
      _bumpRouterRedirect();
      return false;
    }
  }

  void _clearSessionState(LoggedOutReason reason) {
    state = AsyncData(AuthLoggedOut(reason: reason));
    _bumpRouterRedirect();
  }

  /// Notify go_router (via refresh listenable) that auth state
  /// changed. Deferred to a microtask so we don't mutate
  /// [routeRedirectVersionProvider] from inside a Riverpod build —
  /// `listenSelf` fires synchronously during the AsyncNotifier's build
  /// completion, and writing to another provider in that window throws
  /// "Tried to modify a provider while the widget tree was building".
  void _bumpRouterRedirect() {
    Future<void>.microtask(() {
      final notifier = ref.read(routeRedirectVersionProvider.notifier);
      notifier.state = notifier.state + 1;
    });
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
