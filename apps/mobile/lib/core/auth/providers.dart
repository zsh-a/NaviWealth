import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';

import '../../data/db/providers.dart';
import '../logging/providers.dart';
import 'auth_api_client.dart';
import 'auth_interceptor.dart';
import 'auth_session.dart';
import 'dio_auth_api_client.dart';
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
  dio.interceptors.add(
    TalkerDioLogger(talker: ref.read(talkerProvider)),
  );
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
final authInterceptorFactoryProvider =
    Provider<AuthInterceptor Function(Dio)>((ref) {
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
final authSessionReaderProvider =
    Provider<AuthSessionReader>((ref) => () => null);

/// Override-target for the refresh hook. Overridden in `bootstrap.dart`
/// with `AuthController.refreshIfPossible`. Defaults to "can't recover".
final authOnUnauthorizedProvider =
    Provider<AuthOnUnauthorized>((ref) => () async => false);

