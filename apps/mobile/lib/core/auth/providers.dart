import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';

import '../../core/persistence/providers.dart';
import '../logging/providers.dart';
import 'auth_api_client.dart';
import 'auth_interceptor.dart';
import 'auth_session.dart';
import 'device_identity_store.dart';
import 'dio_auth_api_client.dart';
import 'domain_opt_in_store.dart';
import 'domain_scope.dart';
import 'token_store.dart';

/// Synchronous read of the active session.
typedef AuthSessionReader = AuthSession? Function();

/// Refresh hook — returns `true` when the caller can retry, `false` when
/// the local session has been cleared and retry would be futile.
typedef AuthOnUnauthorized = Future<bool> Function();

/// Persistent token storage. Backed by the same [SecureKeyStore] used for
/// the SQLCipher master key.
final tokenStoreProvider = Provider<TokenStore>(
  (ref) => TokenStore(ref.watch(secureKeyStoreProvider)),
);

final deviceIdentityStoreProvider = Provider<DeviceIdentityStore>(
  (ref) => DeviceIdentityStore(ref.watch(secureKeyStoreProvider)),
);

/// Dio used for the auth endpoints themselves (login / refresh / devices /
/// logout). Kept separate from any feature Dio so the AuthInterceptor
/// can't recurse into a refresh while building login headers.
final authDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  dio.interceptors.add(TalkerDioLogger(talker: ref.read(talkerProvider)));
  return dio;
});

final authApiClientProvider = Provider<AuthApiClient>(
  (ref) => DioAuthApiClient(dio: ref.watch(authDioProvider)),
);

/// Hook that future protected-feature Dios use to attach the auth header
/// stamp + refresh-then-retry behaviour.
///
/// Stays as a `Provider<AuthInterceptor Function(Dio)>` rather than a bare
/// `AuthInterceptor` because each consumer needs the host Dio attached
/// after the interceptor is registered on it (so the retry travels
/// through the same adapter and base options). Override
/// `authControllerSessionReaderProvider` /
/// `authControllerOnUnauthorizedProvider` in tests to drive the
/// interceptor without touching the full controller.
final authInterceptorFactoryProvider = Provider<AuthInterceptor Function(Dio)>((
  ref,
) {
  final reader = ref.watch(authSessionReaderProvider);
  final onUnauthorized = ref.watch(authOnUnauthorizedProvider);
  return (Dio host) {
    final interceptor = AuthInterceptor(
      sessionReader: reader,
      onUnauthorized: onUnauthorized,
    )..attach(host);
    host.interceptors.add(interceptor);
    return interceptor;
  };
});

/// Override-target for the active-session reader. The auth feature module
/// (see `bootstrap.dart`) overrides this with `AuthController.currentSession`
/// once login wiring is live. The default is "no session" so unrelated
/// tests / wiring don't have to mount the controller.
final authSessionReaderProvider = Provider<AuthSessionReader>(
  (ref) =>
      () => null,
);

/// Reactive active-session snapshot. Consumers that need to rebuild when
/// login/logout changes should watch this instead of [authSessionReaderProvider].
///
/// The auth feature overrides this in `bootstrap.dart` with
/// `authControllerProvider`; the default delegates to the reader so tests that
/// only override [authSessionReaderProvider] keep working.
final authSessionProvider = Provider<AuthSession?>((ref) {
  return ref.watch(authSessionReaderProvider)();
});

/// Override-target for the refresh hook. Overridden in `bootstrap.dart`
/// with `AuthController.refreshIfPossible`. Defaults to "can't recover".
final authOnUnauthorizedProvider = Provider<AuthOnUnauthorized>(
  (ref) =>
      () async => false,
);

/// D-1.5: per-user opt-in store backing the Settings → Domains toggle and
/// the next-issued JWT `domains` claim. Backed by `sync_meta`.
///
/// `FutureProvider` (not `Provider`) so the store waits for
/// `appDatabaseProvider` to resolve — `requireValue` would throw during
/// the brief window between app start and the DB being open, and any
/// early read (e.g. `activeDomainShellsProvider` in `bootstrap.dart`)
/// would then latch the notifier into `AsyncError` and make the
/// persisted opt-in look like the default on every restart.
final domainOptInStoreProvider = FutureProvider<DomainOptInStore>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DomainOptInStore(db);
});

/// D-1.5: reactive snapshot of the user's active LifeOS domains.
///
/// On first run / fresh install resolves to [DomainOptIns.financeOnly] —
/// HealthOS stays OFF until D-2 ships and the user manually enables it
/// (`lifeos-shell.md` §5).
final domainOptInsProvider = AsyncNotifierProvider<_DomainOptInsNotifier, DomainOptIns>(
  _DomainOptInsNotifier.new,
);

class _DomainOptInsNotifier extends AsyncNotifier<DomainOptIns> {
  @override
  Future<DomainOptIns> build() async {
    final store = await ref.watch(domainOptInStoreProvider.future);
    return store.read();
  }

  Future<void> setEnabled(DomainScope scope, bool enabled) async {
    final current = state.value ?? DomainOptIns.financeOnly;
    final next = current.withScope(scope, enabled: enabled);
    final store = await ref.read(domainOptInStoreProvider.future);
    await store.write(next);
    state = AsyncData(next);
  }
}
