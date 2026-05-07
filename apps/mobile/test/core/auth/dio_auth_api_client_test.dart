import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_errors.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/auth/dio_auth_api_client.dart';

/// One captured request — adapter buffers the request stream so the test
/// can assert on body contents without racing the request lifecycle.
class _Captured {
  _Captured(this.options, this.body);
  final RequestOptions options;
  final String body;
}

/// In-memory adapter that scripts responses by `(method, path)`. Keeps the
/// tests free of socket / mock-server overhead and makes failure modes
/// (timeouts, malformed bodies) trivial to express.
class _FakeAdapter implements HttpClientAdapter {
  final Map<String, _Reply> replies = {};
  final List<_Captured> calls = [];

  void on(String method, String path, _Reply reply) {
    replies['$method $path'] = reply;
  }

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = requestStream == null
        ? ''
        : utf8.decode(
            (await requestStream.toList())
                .expand<int>((c) => c)
                .toList(growable: false),
          );
    calls.add(_Captured(options, body));
    final key = '${options.method} ${options.path}';
    final reply = replies[key];
    if (reply == null) {
      throw StateError('no reply scripted for $key');
    }
    if (reply.error != null) {
      throw reply.error!;
    }
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: <String, List<String>>{
        'content-type': <String>['application/json'],
      },
    );
  }
}

class _Reply {
  _Reply._({required this.status, required this.body, this.error});
  factory _Reply.ok(Object body) =>
      _Reply._(status: 200, body: jsonEncode(body));
  factory _Reply.json(int status, Object body) =>
      _Reply._(status: status, body: jsonEncode(body));
  factory _Reply.raw(int status, String body) =>
      _Reply._(status: status, body: body);
  factory _Reply.networkError() => _Reply._(
    status: 0,
    body: '',
    error: DioException.connectionTimeout(
      timeout: const Duration(seconds: 1),
      requestOptions: RequestOptions(),
    ),
  );

  final int status;
  final String body;
  final Object? error;
}

DioAuthApiClient _buildClient(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
  dio.httpClientAdapter = adapter;
  return DioAuthApiClient(dio: dio);
}

AuthSession _liveSession() => AuthSession(
  accessToken: 'live-token',
  expiresAt: DateTime.utc(2026, 12, 31),
  userId: 'u-1',
  deviceId: 'd-1',
);

void main() {
  group('login', () {
    test('parses LoginResponse into AuthSession', () async {
      final adapter = _FakeAdapter()
        ..on(
          'POST',
          '/auth/login',
          _Reply.ok({
            'access_token': 'jwt',
            'token_type': 'Bearer',
            'expires_at': '2026-12-01T00:00:00Z',
            'user_id': 'u-7',
            'device_id': 'd-9',
          }),
        );
      final client = _buildClient(adapter);

      final session = await client.login(
        email: 'a@b.com',
        password: 'hunter22',
        deviceName: 'iOS',
        deviceId: 'install-device-1',
      );

      expect(session.accessToken, 'jwt');
      expect(session.userId, 'u-7');
      expect(session.deviceId, 'd-9');
      expect(session.expiresAt, DateTime.utc(2026, 12, 1));
      expect(adapter.calls, hasLength(1));
      final call = adapter.calls.single;
      final body = jsonDecode(call.body) as Map<String, Object?>;
      expect(body['email'], 'a@b.com');
      expect(body['password'], 'hunter22');
      expect(body['device_name'], 'iOS');
      expect(body['device_id'], 'install-device-1');
      expect(call.options.headers['Authorization'], isNull);
    });

    test('trims whitespace on email before sending', () async {
      final adapter = _FakeAdapter()
        ..on(
          'POST',
          '/auth/login',
          _Reply.ok({
            'access_token': 't',
            'token_type': 'Bearer',
            'expires_at': '2026-12-01T00:00:00Z',
            'user_id': 'u',
            'device_id': 'd',
          }),
        );
      final client = _buildClient(adapter);
      await client.login(email: '  user@example.com\n', password: 'p');
      final body =
          jsonDecode(adapter.calls.single.body) as Map<String, Object?>;
      expect(body['email'], 'user@example.com');
    });

    test('401 on /auth/login → invalidCredentials', () async {
      final adapter = _FakeAdapter()
        ..on(
          'POST',
          '/auth/login',
          _Reply.json(401, {'code': 'unauthorized', 'message': 'unauthorized'}),
        );
      final client = _buildClient(adapter);

      expect(
        () => client.login(email: 'a@b.com', password: 'wrong'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.kind,
            'kind',
            AuthErrorKind.invalidCredentials,
          ),
        ),
      );
    });

    test('5xx maps to server', () async {
      final adapter = _FakeAdapter()
        ..on(
          'POST',
          '/auth/login',
          _Reply.json(503, {'code': 'internal', 'message': 'down'}),
        );
      final client = _buildClient(adapter);
      expect(
        () => client.login(email: 'a@b.com', password: 'p'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.kind,
            'kind',
            AuthErrorKind.server,
          ),
        ),
      );
    });

    test('connection error maps to network', () async {
      final adapter = _FakeAdapter()
        ..on('POST', '/auth/login', _Reply.networkError());
      final client = _buildClient(adapter);
      expect(
        () => client.login(email: 'a@b.com', password: 'p'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.kind,
            'kind',
            AuthErrorKind.network,
          ),
        ),
      );
    });
  });

  group('refresh', () {
    test('attaches Bearer header and returns rotated token', () async {
      final adapter = _FakeAdapter()
        ..on(
          'POST',
          '/auth/refresh',
          _Reply.ok({
            'access_token': 'rotated',
            'token_type': 'Bearer',
            'expires_at': '2027-01-01T00:00:00Z',
          }),
        );
      final client = _buildClient(adapter);
      final result = await client.refresh(_liveSession());
      expect(result.accessToken, 'rotated');
      expect(result.expiresAt, DateTime.utc(2027, 1, 1));
      expect(
        adapter.calls.single.options.headers['Authorization'],
        'Bearer live-token',
      );
    });

    test('401 on refresh → unauthorized (not invalidCredentials)', () async {
      final adapter = _FakeAdapter()
        ..on(
          'POST',
          '/auth/refresh',
          _Reply.json(401, {'code': 'unauthorized', 'message': 'unauthorized'}),
        );
      final client = _buildClient(adapter);
      expect(
        () => client.refresh(_liveSession()),
        throwsA(
          isA<AuthException>().having(
            (e) => e.kind,
            'kind',
            AuthErrorKind.unauthorized,
          ),
        ),
      );
    });
  });

  group('listDevices', () {
    test('parses devices array and current_device_id', () async {
      final adapter = _FakeAdapter()
        ..on(
          'GET',
          '/auth/devices',
          _Reply.ok({
            'devices': [
              {
                'id': 'd-1',
                'name': 'iOS',
                'created_at': '2026-04-01T00:00:00Z',
                'last_seen_at': '2026-04-28T09:30:00Z',
              },
              {
                'id': 'd-2',
                'name': null,
                'created_at': '2026-04-02T00:00:00Z',
                'last_seen_at': '2026-04-15T12:00:00Z',
              },
            ],
            'current_device_id': 'd-1',
          }),
        );
      final client = _buildClient(adapter);
      final res = await client.listDevices(_liveSession());
      expect(res.devices, hasLength(2));
      expect(res.devices.first.id, 'd-1');
      expect(res.devices.first.name, 'iOS');
      expect(res.devices[1].name, isNull);
      expect(res.currentDeviceId, 'd-1');
    });
  });

  group('logoutDevice', () {
    test('URL-encodes the device id and includes Bearer', () async {
      final adapter = _FakeAdapter()
        ..on('POST', '/auth/logout/d%2Fweird', _Reply.ok({'ok': true}));
      final client = _buildClient(adapter);
      await client.logoutDevice(_liveSession(), 'd/weird');
      expect(
        adapter.calls.single.options.headers['Authorization'],
        'Bearer live-token',
      );
    });

    test('empty body still resolves to a successful return', () async {
      final adapter = _FakeAdapter()
        ..on('POST', '/auth/logout/d-2', _Reply.raw(204, ''));
      final client = _buildClient(adapter);
      // Should not throw — 2xx + empty body == OK.
      await client.logoutDevice(_liveSession(), 'd-2');
    });
  });
}
