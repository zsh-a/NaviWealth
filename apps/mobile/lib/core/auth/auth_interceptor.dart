import 'dart:async';

import 'package:dio/dio.dart';

import 'auth_session.dart';

/// Bridge between the auth subsystem and any [Dio] that needs to talk to a
/// protected endpoint.
///
/// On request:   reads the current [AuthSession] (sync) and stamps
///               `Authorization: Bearer <jwt>`. If there's no session,
///               leaves the header absent — the server will respond 401
///               and the caller's domain layer maps that to "logged out".
///
/// On 401:       calls [onUnauthorized] (single-flight is the caller's
///               responsibility; we just yield to it). When that future
///               completes the interceptor reads the session again. If the
///               token rotated, the original request is retried *once* with
///               the new bearer; otherwise the 401 is propagated.
///
/// We intentionally do **not** drive the refresh from the interceptor itself
/// — refresh involves clearing the local session on failure and routing to
/// `/login`, which is responsibility of `AuthController`. Keeping the
/// interceptor narrow makes it trivial to test (see
/// `auth_interceptor_test.dart`) and keeps the redirect logic in one place.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.sessionReader,
    required this.onUnauthorized,
    Dio? hostDio,
  }) : _hostDio = hostDio;

  /// Synchronous read of the current session — typically `() =>
  /// container.read(authSessionProvider)`. Returning `null` means the user
  /// is logged out (requests go out without `Authorization`).
  final AuthSession? Function() sessionReader;

  /// Called when the server returns 401 on a request that *did* carry a
  /// bearer. Implementations should attempt token rotation, persist the
  /// updated session, and complete. If they cannot rotate (refresh itself
  /// 401s) they should clear the local session — the interceptor will then
  /// see `sessionReader()` return `null` and propagate the original 401.
  ///
  /// Returns `true` if a retry might succeed (rotation likely succeeded);
  /// `false` to bail out without retrying.
  final FutureOr<bool> Function() onUnauthorized;

  /// Dio used to issue the retried request after a successful rotation.
  /// Must be the same instance the interceptor is attached to, so the
  /// retry travels through the host's adapter / base options. Set via
  /// [attach] right after construction; we don't take it in the
  /// constructor because providers wire the interceptor before they
  /// have a Dio handle.
  Dio? _hostDio;

  /// Bind the host Dio. Idempotent.
  void attach(Dio dio) {
    _hostDio ??= dio;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!options.headers.containsKey('Authorization')) {
      final session = sessionReader();
      if (session != null && session.accessToken.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    if (response == null || response.statusCode != 401) {
      handler.next(err);
      return;
    }
    // Don't retry requests that already carried no bearer — there's nothing
    // to refresh, the 401 is authoritative.
    final originalAuth = err.requestOptions.headers['Authorization'];
    if (originalAuth == null) {
      handler.next(err);
      return;
    }
    // Don't recurse — if the failed request was itself a refresh attempt
    // we can't fix it here; let the controller clear state and reroute.
    if (err.requestOptions.path.endsWith('/auth/refresh')) {
      handler.next(err);
      return;
    }
    if (err.requestOptions.extra['_authRetry'] == true) {
      handler.next(err);
      return;
    }
    final ok = await onUnauthorized();
    if (!ok) {
      handler.next(err);
      return;
    }
    final fresh = sessionReader();
    if (fresh == null) {
      handler.next(err);
      return;
    }
    final host = _hostDio;
    if (host == null) {
      // Caller forgot to call [attach]. Better to surface the original 401
      // than silently spin up a fresh Dio (which would bypass the host's
      // adapter / interceptors) — the consequence is just "this request
      // doesn't auto-retry," which the call site can recover from.
      handler.next(err);
      return;
    }
    final retryOpts = err.requestOptions
      ..headers['Authorization'] = 'Bearer ${fresh.accessToken}'
      ..extra['_authRetry'] = true;
    try {
      final response = await host.fetch<dynamic>(retryOpts);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
