import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/auth_errors.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/auth/current_user.dart' show kLocalOnlyUserId;
import '../../../core/auth/device_identity_store.dart';
import '../../../core/auth/owner_transfer_intent.dart';
import '../../../core/auth/providers.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/logging/providers.dart';
import '../../../core/persistence/owner_data_migration.dart';
import '../../../core/persistence/providers.dart';
import '../../../core/shell/route_guard.dart';
import '../../../core/sync/providers.dart' show syncSchedulerProvider;
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
  bool _changingOwner = false;

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
    // Reconcile before inspecting mode or exposing an owner to repositories.
    // An interrupted SQLite transaction restores the old identity; a committed
    // marker completes the target identity, even if only one store was updated.
    await _recoverOwnerTransfer();
    // Local-only mode is sticky and takes precedence over any persisted
    // session until the user explicitly changes mode. Reading the
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
    _requireReadyIdentity();
    final api = ref.read(authApiClientProvider);
    final store = ref.read(tokenStoreProvider);
    final deviceIdentity = ref.read(deviceIdentityStoreProvider);
    final logger = ref.read(loggerProvider);
    final deviceId = await deviceIdentity.getOrCreate();
    final domains = _activeDomainsForToken();

    final session = await api.login(
      email: email,
      password: password,
      domains: domains,
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
    _requireReadyIdentity();
    final api = ref.read(authApiClientProvider);
    final store = ref.read(tokenStoreProvider);
    final deviceIdentity = ref.read(deviceIdentityStoreProvider);
    final logger = ref.read(loggerProvider);
    final deviceId = await deviceIdentity.getOrCreate();
    final domains = _activeDomainsForToken();

    final session = await api.register(
      email: email,
      password: password,
      domains: domains,
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
    _publishCloudSession(session);
  }

  void _publishCloudSession(AuthSession session) {
    state = AsyncData(AuthLoggedIn(session));
    _bumpRouterRedirect();
  }

  /// Opt into local-only mode. Persists the mode flag, drops any stale
  /// token, and emits [AuthLocalOnly] so the router lands the user on
  /// home.
  Future<void> enterLocalOnlyMode() async {
    _requireReadyIdentity();
    await ref.read(appModeStoreProvider).write(AppMode.localOnly);
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(AuthLocalOnly());
    ref.invalidate(appModeProvider);
    _bumpRouterRedirect();
  }

  /// Register a new cloud account and migrate local-only data.
  ///
  /// Used when a [AuthLocalOnly] user wants to upgrade to cloud sync.
  /// Source rows, confirmed Memory/Profile and local history follow the new
  /// identity. Resumable effects are invalidated and Sync backfill is reset.
  Future<void> upgradeToCloud({
    required String email,
    required String password,
    String? deviceName,
  }) async {
    _requireReadyIdentity();
    final api = ref.read(authApiClientProvider);
    final deviceIdentity = ref.read(deviceIdentityStoreProvider);
    final logger = ref.read(loggerProvider);
    final deviceId = await deviceIdentity.getOrCreate();
    final domains = _activeDomainsForToken();

    final session = await api.register(
      email: email,
      password: password,
      domains: domains,
      deviceName: deviceName,
      deviceId: deviceId,
    );

    await _changeOwner(
      from: kLocalOnlyUserId,
      to: session.userId,
      targetMode: AppMode.cloud,
      targetSession: session,
    );
    logger.i('auth_upgrade_success user=${session.userId}');
  }

  /// Log into an existing cloud account without migrating local data.
  ///
  /// Used when a [AuthLocalOnly] user already has a cloud account and
  /// wants to connect. Local-only rows remain in the DB with
  /// `owner_user_id = 'local-user'` — they are not merged.
  Future<void> connectToCloud({
    required String email,
    required String password,
    String? deviceName,
  }) async {
    _requireReadyIdentity();
    final api = ref.read(authApiClientProvider);
    final store = ref.read(tokenStoreProvider);
    final deviceIdentity = ref.read(deviceIdentityStoreProvider);
    final logger = ref.read(loggerProvider);
    final deviceId = await deviceIdentity.getOrCreate();
    final domains = _activeDomainsForToken();

    final session = await api.login(
      email: email,
      password: password,
      domains: domains,
      deviceName: deviceName,
      deviceId: deviceId,
    );
    await _persistCloudSession(
      session: session,
      requestedDeviceId: deviceId,
      store: store,
      deviceIdentity: deviceIdentity,
    );
    logger.i('auth_connect_success user=${session.userId}');
  }

  /// Downgrade from cloud to local-only mode.
  ///
  /// Migrates all cloud-owned rows back to `owner_user_id = 'local-user'`,
  /// clears the session, and switches to [AuthLocalOnly]. Data stays in
  /// the local DB; sync is fully disabled.
  Future<void> switchToLocalOnly() async {
    _requireReadyIdentity();
    final session = currentSession();
    final logger = ref.read(loggerProvider);

    if (session == null) {
      await enterLocalOnlyMode();
      return;
    }
    await _changeOwner(
      from: session.userId,
      to: kLocalOnlyUserId,
      targetMode: AppMode.localOnly,
      targetSession: null,
    );
    // Revoke only after the local transfer has committed; a data conflict must
    // leave the original cloud session usable.
    try {
      await ref
          .read(authApiClientProvider)
          .logoutDevice(session, session.deviceId);
    } on AuthException catch (e) {
      logger.w('auth_downgrade_logout_failed kind=${e.kind.name}');
    }
    logger.i('auth_downgrade_success');
  }

  Future<void> _changeOwner({
    required String from,
    required String to,
    required AppMode targetMode,
    required AuthSession? targetSession,
  }) async {
    if (_changingOwner) {
      throw StateError('An identity change is already running');
    }
    _changingOwner = true;
    try {
      await _inFlightRefresh;
      final scheduler = await ref.read(syncSchedulerProvider.future);
      final tokenStore = ref.read(tokenStoreProvider);
      final deviceId = await ref
          .read(deviceIdentityStoreProvider)
          .getOrCreate();
      final previous = OwnerIdentitySnapshot(
        mode: ref.read(appModeStoreProvider).read().wire,
        session: await tokenStore.read(),
        deviceId: deviceId,
      );
      final target = OwnerIdentitySnapshot(
        mode: targetMode.wire,
        session: targetSession,
        deviceId: targetSession?.deviceId ?? deviceId,
      );
      final intent = OwnerTransferIntent(
        id: const Uuid().v4(),
        from: from,
        to: to,
        previous: previous,
        target: target,
      );
      final migration = OwnerDataMigration(
        await ref.read(appDatabaseProvider.future),
      );
      if (await tokenStore.readOwnerTransfer() != null) {
        throw StateError('An owner transfer requires recovery');
      }
      var transferred = 0;
      try {
        await scheduler?.pauseAndDrain();
        await tokenStore.writeOwnerTransfer(intent);
        transferred = await migration.transfer(
          from: from,
          to: to,
          transferId: intent.id,
          commitIdentity: () => _persistIdentity(target),
        );
        await _finishOwnerTransfer(intent, migration);
      } catch (error, stack) {
        // Consult the durable marker even when a store operation threw after
        // persisting its value. Never roll auth back after SQLite committed.
        bool committed;
        try {
          committed = await migration.didCommit(intent.id);
          await _persistIdentity(committed ? target : previous);
          await _finishOwnerTransfer(intent, migration);
        } catch (recoveryError, recoveryStack) {
          // Leave the journal intact and prevent owner-dependent actions until
          // startup recovery can complete. Do not resume the previous Sync.
          scheduler?.stop();
          state = AsyncError(recoveryError, recoveryStack);
          rethrow;
        }
        if (!committed) {
          scheduler?.resume();
          Error.throwWithStackTrace(error, stack);
        }
      }
      scheduler?.stop();
      _publishIdentity(target);
      ref
          .read(loggerProvider)
          .event(
            'core.auth.owner_transfer.completed',
            fields: {'row_count': transferred},
          );
    } finally {
      _changingOwner = false;
    }
  }

  Future<void> _recoverOwnerTransfer() async {
    final intent = await ref.read(tokenStoreProvider).readOwnerTransfer();
    if (intent == null) return;
    final migration = OwnerDataMigration(
      await ref.read(appDatabaseProvider.future),
    );
    final committed = await migration.didCommit(intent.id);
    await _persistIdentity(committed ? intent.target : intent.previous);
    await _finishOwnerTransfer(intent, migration);
    ref.invalidate(appModeProvider);
  }

  Future<void> _persistIdentity(OwnerIdentitySnapshot identity) async {
    final store = ref.read(tokenStoreProvider);
    final session = identity.session;
    if (session == null) {
      await store.clear();
    } else {
      await store.write(session);
    }
    await ref.read(appModeStoreProvider).write(AppMode.parse(identity.mode));
    await ref.read(deviceIdentityStoreProvider).remember(identity.deviceId);
  }

  Future<void> _finishOwnerTransfer(
    OwnerTransferIntent intent,
    OwnerDataMigration migration,
  ) async {
    // Removing the journal is the last required write. An orphan commit marker
    // contains only one random id and is harmless; the next transfer replaces it.
    await ref.read(tokenStoreProvider).clearOwnerTransfer();
    try {
      await migration.clearCommitMarker(intent.id);
    } catch (_) {
      ref
          .read(loggerProvider)
          .event('core.auth.owner_transfer.cleanup_deferred');
    }
  }

  void _publishIdentity(OwnerIdentitySnapshot identity) {
    final session = identity.session;
    state = AsyncData(
      AppMode.parse(identity.mode) == AppMode.localOnly
          ? const AuthLocalOnly()
          : session == null
          ? const AuthLoggedOut()
          : AuthLoggedIn(session),
    );
    ref.invalidate(appModeProvider);
    _bumpRouterRedirect();
  }

  void _requireReadyIdentity() {
    if (_changingOwner || !state.hasValue) {
      throw StateError('Identity is not ready');
    }
  }

  /// Mark the user's mode preference as `cloud` so the next router redirect
  /// sends them to /login instead of /onboarding. Does NOT change the
  /// auth state (still [AuthLoggedOut]); the actual session is established
  /// by [login].
  Future<void> chooseCloud() async {
    _requireReadyIdentity();
    await ref.read(appModeStoreProvider).write(AppMode.cloud);
    ref.invalidate(appModeProvider);
    _bumpRouterRedirect();
  }

  /// Logs out the *current* device. Best-effort: a network failure here
  /// still clears local state because the user's intent is "I want this
  /// device logged out" — the device row will time out on the server when
  /// `exp` passes anyway.
  Future<void> logoutCurrent() async {
    _requireReadyIdentity();
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
    if (_changingOwner) return Future.value(false);
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
      final rotated = await api.refresh(
        session,
        domains: _activeDomainsForToken(),
      );
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

  List<String> _activeDomainsForToken() => ref.read(authTokenDomainsProvider);

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
