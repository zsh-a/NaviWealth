import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_errors.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/auth/current_user.dart' show kLocalOnlyUserId;
import '../../../core/auth/owner_transfer_intent.dart';
import '../../../core/auth/providers.dart';
import '../../../core/auth/session_transitions.dart';
import '../../../core/logging/providers.dart';
import '../../../core/persistence/providers.dart' show appDatabaseProvider;
import '../../../core/shell/route_guard.dart';
import 'app_mode_store.dart';
import 'owner_transfer_service.dart';
import 'session_persistence.dart';

export '../../../core/auth/auth_state.dart';

/// Publishes persisted auth state. Network work is revision-scoped; all local
/// session writes share one commit queue, including refresh and owner transfer.
class AuthController extends AsyncNotifier<AuthState> {
  final _transitions = SessionTransitions();
  ({int revision, Future<bool> result})? _refresh;
  Future<void>? _remoteRevocation;

  @override
  Future<AuthState> build() async {
    final revision = _transitions.restart();
    ref.onDispose(_transitions.dispose);
    listenSelf((prev, next) {
      if (prev?.value.runtimeType != next.value.runtimeType) {
        _bumpRouterRedirect();
      }
    });
    return await _transitions.commit(revision, _readPersistedIdentity) ??
        const AuthUnknown();
  }

  Future<AuthState> _readPersistedIdentity() async {
    final persistence = ref.read(sessionPersistenceProvider);
    if (await persistence.tokens.readOwnerTransfer() != null) {
      // A failed database open must remain a reactive recovery dependency.
      // Explicit database reset/retry then rebuilds auth and retries its journal,
      // while ordinary auth startup does not need to initialize the database.
      await ref.watch(appDatabaseProvider.future);
    }
    if (await ref.read(ownerTransferServiceProvider).recoverPending()) {
      ref.invalidate(appModeProvider);
    }
    final mode = persistence.modes.read();
    if (mode == AppMode.localOnly) {
      await persistence.tokens.clear();
      return const AuthLocalOnly();
    }
    final session = await persistence.tokens.read();
    if (session == null) return const AuthLoggedOut();
    if (session.isExpired()) {
      await persistence.tokens.clear();
      return const AuthLoggedOut(reason: LoggedOutReason.sessionExpired);
    }
    await persistence.devices.remember(session.deviceId);
    return AuthLoggedIn(session);
  }

  AuthSession? currentSession() {
    if (state.isLoading || state.hasError) return null;
    final value = state.value;
    return value is AuthLoggedIn ? value.session : null;
  }

  Future<void> login({
    required String email,
    required String password,
    String? deviceName,
  }) => _authenticate(
    email: email,
    password: password,
    deviceName: deviceName,
    registerAccount: false,
  );

  Future<void> register({
    required String email,
    required String password,
    String? deviceName,
  }) => _authenticate(
    email: email,
    password: password,
    deviceName: deviceName,
    registerAccount: true,
  );

  /// Existing cloud accounts keep local-only rows in their original partition.
  Future<void> connectToCloud({
    required String email,
    required String password,
    String? deviceName,
  }) => login(email: email, password: password, deviceName: deviceName);

  /// Registration transfers local truth and history through the secure journal.
  Future<void> upgradeToCloud({
    required String email,
    required String password,
    String? deviceName,
  }) => _authenticate(
    email: email,
    password: password,
    deviceName: deviceName,
    registerAccount: true,
    transferLocalData: true,
  );

  Future<void> _authenticate({
    required String email,
    required String password,
    required bool registerAccount,
    String? deviceName,
    bool transferLocalData = false,
  }) => _transition((revision) async {
    final api = ref.read(authApiClientProvider);
    final persistence = ref.read(sessionPersistenceProvider);
    final deviceId = await persistence.devices.getOrCreate();
    // Device revocation must reach the server before a new login reuses that
    // device. Refresh requests remain independent and can be superseded.
    await _remoteRevocation;
    if (!_transitions.isCurrent(revision)) return;
    final domains = ref.read(authTokenDomainsProvider);
    final session = await (registerAccount ? api.register : api.login)(
      email: email,
      password: password,
      deviceName: deviceName,
      deviceId: deviceId,
      domains: domains,
    );
    await _commit(revision, () async {
      final target = OwnerIdentitySnapshot(
        mode: AppMode.cloud.wire,
        session: session,
        deviceId: session.deviceId,
      );
      if (transferLocalData) {
        await ref
            .read(ownerTransferServiceProvider)
            .transfer(
              from: kLocalOnlyUserId,
              to: session.userId,
              target: target,
            );
      } else {
        await persistence.replace(target);
      }
      _publish(target);
      return true;
    });
  });

  Future<void> enterLocalOnlyMode() => switchToLocalOnly();

  Future<void> switchToLocalOnly() => _transition((revision) async {
    AuthSession? previousSession;
    await _commit(revision, () async {
      final persistence = ref.read(sessionPersistenceProvider);
      final previous = await persistence.read();
      previousSession = previous.session;
      final target = OwnerIdentitySnapshot(
        mode: AppMode.localOnly.wire,
        session: null,
        deviceId: previous.deviceId,
      );
      if (previousSession == null) {
        await persistence.replace(target);
      } else {
        await ref
            .read(ownerTransferServiceProvider)
            .transfer(
              from: previousSession!.userId,
              to: kLocalOnlyUserId,
              target: target,
            );
      }
      _publish(target);
      return true;
    });
    if (_transitions.isCurrent(revision) && previousSession != null) {
      await _revoke(previousSession!);
    }
  });

  /// Persists cloud onboarding choice before the router opens sign-in.
  Future<void> chooseCloud() => _transition((revision) async {
    await _commit(revision, () async {
      final persistence = ref.read(sessionPersistenceProvider);
      final previous = await persistence.read();
      final target = OwnerIdentitySnapshot(
        mode: AppMode.cloud.wire,
        session: previous.session,
        deviceId: previous.deviceId,
      );
      await persistence.replace(target);
      _publish(target);
      return true;
    });
  });

  /// Local logout commits before best-effort remote revocation. Starting it
  /// immediately invalidates outstanding login and refresh responses.
  Future<void> logoutCurrent() => _transition((revision) async {
    AuthSession? previousSession;
    await _commit(revision, () async {
      final persistence = ref.read(sessionPersistenceProvider);
      final previous = await persistence.read();
      previousSession = previous.session;
      final target = OwnerIdentitySnapshot(
        mode: AppMode.cloud.wire,
        session: null,
        deviceId: previous.deviceId,
      );
      await persistence.replace(target);
      _publish(target, reason: LoggedOutReason.manuallyLoggedOut);
      return true;
    });
    if (_transitions.isCurrent(revision) && previousSession != null) {
      await _revoke(previousSession!);
    }
  });

  Future<void> _revoke(AuthSession session) async {
    final api = ref.read(authApiClientProvider);
    final logger = ref.read(loggerProvider);
    final operation = () async {
      try {
        await api.logoutDevice(session, session.deviceId);
      } on AuthException catch (error) {
        logger.event(
          'core.auth.logout.remote_failed',
          fields: {'error_code': error.kind.name},
        );
      }
    }();
    _remoteRevocation = operation;
    try {
      await operation;
    } finally {
      if (identical(_remoteRevocation, operation)) _remoteRevocation = null;
    }
  }

  Future<bool> refreshIfPossible() {
    if (_transitions.isPending ||
        state.isLoading ||
        state.hasError ||
        !state.hasValue) {
      return Future.value(false);
    }
    final revision = _transitions.revision;
    final pending = _refresh;
    if (pending != null && pending.revision == revision) return pending.result;
    final result = _refreshNow(revision);
    _refresh = (revision: revision, result: result);
    return result.whenComplete(() {
      if (_refresh?.revision == revision) _refresh = null;
    });
  }

  Future<bool> _refreshNow(int revision) async {
    final session = currentSession();
    if (session == null || session.isExpired()) return false;
    final api = ref.read(authApiClientProvider);
    final persistence = ref.read(sessionPersistenceProvider);
    try {
      final rotated = await api.refresh(
        session,
        domains: ref.read(authTokenDomainsProvider),
      );
      final result = await _commit(revision, () async {
        final updated = session.withRotatedToken(
          accessToken: rotated.accessToken,
          expiresAt: rotated.expiresAt,
        );
        final target = OwnerIdentitySnapshot(
          mode: AppMode.cloud.wire,
          session: updated,
          deviceId: updated.deviceId,
        );
        await persistence.replace(target);
        _publish(target);
        return true;
      });
      return result == true && _transitions.isCurrent(revision);
    } on AuthException {
      await _commit(revision, () async {
        final target = OwnerIdentitySnapshot(
          mode: AppMode.cloud.wire,
          session: null,
          deviceId: session.deviceId,
        );
        await persistence.replace(target);
        _publish(target, reason: LoggedOutReason.sessionExpired);
        return true;
      });
      return false;
    }
  }

  Future<void> _transition(Future<void> Function(int revision) action) async {
    if (state.isLoading || state.hasError || !state.hasValue) {
      throw StateError('Identity is not ready');
    }
    final revision = _transitions.begin();
    try {
      await action(revision);
    } finally {
      _transitions.finish(revision);
    }
  }

  Future<T?> _commit<T>(int revision, Future<T> Function() action) =>
      _transitions.commit(revision, () async {
        try {
          if (state.isLoading || state.hasError || !state.hasValue) {
            throw const IdentityRecoveryRequired();
          }
          return await action();
        } on IdentityRecoveryRequired catch (error, stack) {
          if (ref.mounted && !state.isLoading) state = AsyncError(error, stack);
          rethrow;
        }
      });

  void _publish(OwnerIdentitySnapshot identity, {LoggedOutReason? reason}) {
    if (!ref.mounted || state.isLoading) return;
    final session = identity.session;
    state = AsyncData(
      AppMode.parse(identity.mode) == AppMode.localOnly
          ? const AuthLocalOnly()
          : session == null
          ? AuthLoggedOut(reason: reason)
          : AuthLoggedIn(session),
    );
    ref.invalidate(appModeProvider);
    _bumpRouterRedirect();
  }

  void _bumpRouterRedirect() {
    Future<void>.microtask(() {
      if (!ref.mounted) return;
      final notifier = ref.read(routeRedirectVersionProvider.notifier);
      notifier.state = notifier.state + 1;
    });
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
