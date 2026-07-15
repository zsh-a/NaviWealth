import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_interceptor.dart';
import 'package:naviwealth/core/auth/auth_session.dart';

/// Captured snapshot of the headers as they were *at request time*. The
/// AuthInterceptor mutates the original [RequestOptions] in place when it
/// retries, so storing a reference would let later state leak into earlier
/// assertions.
class _Call {
  _Call(this.method, this.path, Map<String, dynamic> headers)
    : headers = Map<String, dynamic>.unmodifiable(headers);

  final String method;
  final String path;
  final Map<String, dynamic> headers;
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._replies);
  final List<_R> _replies;
  final List<_Call> calls = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(_Call(options.method, options.path, options.headers));
    if (calls.length > _replies.length) {
      throw StateError(
        'unexpected call ${calls.length} to ${options.method} ${options.path}',
      );
    }
    final reply = _replies[calls.length - 1];
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: const <String, List<String>>{
        'content-type': <String>['application/json'],
      },
    );
  }
}

class _R {
  _R(this.status, [this.body = '{}']);
  final int status;
  final String body;
}

AuthSession _session(String token) => AuthSession(
  accessToken: token,
  expiresAt: DateTime.utc(2026, 12, 1),
  userId: 'u',
  deviceId: 'd',
);

Dio _buildDio({
  required HttpClientAdapter adapter,
  required AuthSession? Function() reader,
  required FutureOr<bool> Function() onUnauthorized,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
  dio.httpClientAdapter = adapter;
  final interceptor = AuthInterceptor(
    sessionReader: reader,
    onUnauthorized: onUnauthorized,
  )..attach(dio);
  dio.interceptors.add(interceptor);
  return dio;
}

void main() {
  group('AuthInterceptor', () {
    test('stamps Bearer header from sessionReader on every request', () async {
      final adapter = _ScriptedAdapter([_R(200)]);
      final dio = _buildDio(
        adapter: adapter,
        reader: () => _session('tok'),
        onUnauthorized: () => false,
      );
      await dio.get<dynamic>('/sync');
      expect(adapter.calls.single.headers['Authorization'], 'Bearer tok');
    });

    test('skips Authorization when sessionReader returns null', () async {
      final adapter = _ScriptedAdapter([_R(200)]);
      final dio = _buildDio(
        adapter: adapter,
        reader: () => null,
        onUnauthorized: () => false,
      );
      await dio.get<dynamic>('/me');
      expect(adapter.calls.single.headers['Authorization'], isNull);
    });

    test(
      '401 → onUnauthorized rotates token → original request retried with new bearer',
      () async {
        // First call returns 401 (with stale token); second call returns 200
        // (must carry the rotated token).
        final adapter = _ScriptedAdapter([
          _R(401, '{"code":"unauthorized"}'),
          _R(200),
        ]);
        var token = 'old';
        var refreshes = 0;
        final dio = _buildDio(
          adapter: adapter,
          reader: () => _session(token),
          onUnauthorized: () async {
            refreshes += 1;
            token = 'new';
            return true;
          },
        );

        final res = await dio.get<dynamic>('/sync');
        expect(res.statusCode, 200);
        expect(refreshes, 1);
        expect(adapter.calls, hasLength(2));
        expect(adapter.calls[0].headers['Authorization'], 'Bearer old');
        expect(adapter.calls[1].headers['Authorization'], 'Bearer new');
      },
    );

    test('refresh failing → 401 propagates without retrying', () async {
      final adapter = _ScriptedAdapter([_R(401, '{"code":"unauthorized"}')]);
      var refreshes = 0;
      final dio = _buildDio(
        adapter: adapter,
        reader: () => _session('old'),
        onUnauthorized: () async {
          refreshes += 1;
          return false;
        },
      );

      await expectLater(
        dio.get<dynamic>('/sync'),
        throwsA(isA<DioException>()),
      );
      expect(refreshes, 1);
      expect(adapter.calls, hasLength(1));
    });

    test('no Bearer → 401 propagates without calling onUnauthorized', () async {
      final adapter = _ScriptedAdapter([_R(401, '{"code":"unauthorized"}')]);
      var refreshes = 0;
      final dio = _buildDio(
        adapter: adapter,
        reader: () => null,
        onUnauthorized: () async {
          refreshes += 1;
          return true;
        },
      );

      await expectLater(dio.get<dynamic>('/me'), throwsA(isA<DioException>()));
      expect(refreshes, 0);
    });

    test('does not loop when /auth/refresh itself 401s', () async {
      final adapter = _ScriptedAdapter([_R(401, '{"code":"unauthorized"}')]);
      var refreshes = 0;
      final dio = _buildDio(
        adapter: adapter,
        reader: () => _session('old'),
        onUnauthorized: () async {
          refreshes += 1;
          return true;
        },
      );

      await expectLater(
        dio.post<dynamic>('/auth/refresh'),
        throwsA(isA<DioException>()),
      );
      // Refresh path is excluded from the rotate-and-retry loop, so the
      // controller-driven onUnauthorized is never triggered here.
      expect(refreshes, 0);
    });

    test(
      'retried request that 401s a second time is not rotated again',
      () async {
        // First 401 → rotate, retry 401 again → bail out.
        final adapter = _ScriptedAdapter([
          _R(401, '{"code":"unauthorized"}'),
          _R(401, '{"code":"unauthorized"}'),
        ]);
        var refreshes = 0;
        final dio = _buildDio(
          adapter: adapter,
          reader: () => _session('old'),
          onUnauthorized: () async {
            refreshes += 1;
            return true;
          },
        );

        await expectLater(
          dio.get<dynamic>('/sync'),
          throwsA(isA<DioException>()),
        );
        expect(refreshes, 1);
        expect(adapter.calls, hasLength(2));
      },
    );
  });
}
