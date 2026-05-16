import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/dio_sync_api_client.dart';
import 'package:naviwealth/core/sync/errors.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/core/sync/sync_api_client.dart';
import 'package:naviwealth/data/domain/hlc.dart';

class _Captured {
  _Captured(this.options, this.body);

  final RequestOptions options;
  final String body;
}

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
                .expand<int>((chunk) => chunk)
                .toList(growable: false),
          );
    calls.add(_Captured(options, body));
    final reply = replies['${options.method} ${options.path}'];
    if (reply == null) {
      throw StateError(
        'no reply scripted for ${options.method} ${options.path}',
      );
    }
    if (reply.networkError) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'connection failed',
      );
    }
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: {
        'content-type': ['application/json'],
        ...reply.headers,
      },
    );
  }
}

class _Reply {
  const _Reply._({
    required this.status,
    required this.body,
    this.headers = const {},
    this.networkError = false,
  });

  factory _Reply.ok(Object body) =>
      _Reply._(status: 200, body: jsonEncode(body));
  factory _Reply.json(
    int status,
    Object body, {
    Map<String, List<String>> headers = const {},
  }) => _Reply._(status: status, body: jsonEncode(body), headers: headers);
  factory _Reply.networkError() =>
      const _Reply._(status: 0, body: '', networkError: true);

  final int status;
  final String body;
  final Map<String, List<String>> headers;
  final bool networkError;
}

DioSyncApiClient _buildClient(
  _FakeAdapter adapter, {
  Future<String?> Function()? tokenProvider,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
  dio.httpClientAdapter = adapter;
  return DioSyncApiClient(
    dio: dio,
    tokenProvider: tokenProvider ?? () async => 'sync-token',
  );
}

Op _op({
  String opId = 'op-1',
  String table = 'accounts',
  String rowId = 'A1',
  OpType type = OpType.update,
  Map<String, Object?>? fieldsDiff = const {'name': 'Cash'},
  String deviceId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  Hlc hlc = const Hlc(
    wallMillis: 1714291200000,
    counter: 1,
    nodeId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  ),
}) {
  return Op(
    opId: opId,
    tableName: table,
    rowId: rowId,
    opType: type,
    fieldsDiff: type == OpType.delete ? null : fieldsDiff,
    hlc: hlc,
    deviceId: deviceId,
  );
}

void main() {
  group('DioSyncApiClient wire protocol', () {
    test('me sends sync protocol headers and parses HLC response', () async {
      final adapter = _FakeAdapter()
        ..on(
          'GET',
          '/me',
          _Reply.ok({
            'user_id': 'u-1',
            'server_now': '2026-04-28T12:34:56.789Z',
            'server_hlc':
                '1714303596789.0000-00000000-0000-0000-0000-000000000000',
          }),
        );
      final client = _buildClient(adapter);

      final res = await client.me();

      expect(res.userId, 'u-1');
      expect(res.serverNow, DateTime.utc(2026, 4, 28, 12, 34, 56, 789));
      expect(res.serverHlc.wallMillis, 1714303596789);
      final headers = adapter.calls.single.options.headers;
      expect(headers['Sync-Protocol-Version'], '$kSyncProtocolVersion');
      expect(headers['Content-Type'], 'application/json; charset=utf-8');
      expect(headers['Accept'], 'application/json');
      expect(headers['Authorization'], 'Bearer sync-token');
    });

    test('push encodes batch body and parses per-op rejection', () async {
      final adapter = _FakeAdapter()
        ..on(
          'POST',
          '/sync/push',
          _Reply.ok({
            'accepted': 1,
            'rejected': [
              {'op_id': 'op-bad', 'code': 'op_id_mutated', 'message': 'reused'},
            ],
            'server_hlc_high':
                '1714291205000.0002-00000000-0000-0000-0000-000000000000',
            'server_now': '2026-04-28T12:00:05.000Z',
          }),
        );
      final client = _buildClient(adapter);

      final res = await client.push(
        deviceId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        ops: [
          _op(),
          _op(opId: 'op-bad'),
        ],
      );

      expect(res.accepted, 1);
      expect(res.rejected.single.code, 'op_id_mutated');
      expect(res.serverHlcHigh.counter, 2);
      final body =
          jsonDecode(adapter.calls.single.body) as Map<String, Object?>;
      expect(body['device_id'], 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      final ops = body['ops'] as List<Object?>;
      expect(ops, hasLength(2));
      expect((ops.first as Map<String, Object?>)['op_type'], 'update');
      expect((ops.first as Map<String, Object?>)['fields_diff'], {
        'name': 'Cash',
      });
    });

    test('pull sends canonical cursor and parses returned ops', () async {
      final since = Hlc.parse(
        '1714291200000.0001-00000000-0000-0000-0000-000000000000',
      );
      final remote = _op(
        opId: 'remote-1',
        type: OpType.insert,
        fieldsDiff: const {'id': 'A1', 'name': 'Cash'},
        hlc: Hlc.parse(
          '1714291205000.0000-00000000-0000-0000-0000-000000000000',
        ),
        deviceId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      );
      final adapter = _FakeAdapter()
        ..on(
          'GET',
          '/sync/pull',
          _Reply.ok({
            'ops': [remote.toJson()],
            'server_hlc_high': remote.hlc.toString(),
            'has_more': true,
            'server_now': '2026-04-28T12:00:05.000Z',
          }),
        );
      final client = _buildClient(adapter);

      final res = await client.pull(
        deviceId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        since: since,
        limit: 123,
      );

      expect(res.ops.single.opId, 'remote-1');
      expect(res.hasMore, isTrue);
      final query = adapter.calls.single.options.queryParameters;
      expect(query['since'], since.toString());
      expect(query['device_id'], 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      expect(query['limit'], '123');
    });

    test('maps protocol status codes to SyncException kinds', () async {
      final cases = <int, SyncErrorKind>{
        401: SyncErrorKind.unauthorized,
        409: SyncErrorKind.clockSkew,
        413: SyncErrorKind.payloadTooLarge,
        426: SyncErrorKind.protocolVersion,
        500: SyncErrorKind.server,
      };

      for (final entry in cases.entries) {
        final adapter = _FakeAdapter()
          ..on(
            'GET',
            '/me',
            _Reply.json(entry.key, {
              'code': 'c_${entry.key}',
              'message': 'status ${entry.key}',
            }),
          );
        final client = _buildClient(adapter);

        await expectLater(
          client.me(),
          throwsA(
            isA<SyncException>()
                .having((e) => e.kind, 'kind', entry.value)
                .having((e) => e.statusCode, 'statusCode', entry.key)
                .having((e) => e.code, 'code', 'c_${entry.key}'),
          ),
        );
      }
    });

    test('429 preserves Retry-After seconds for engine backoff', () async {
      final adapter = _FakeAdapter()
        ..on(
          'GET',
          '/me',
          _Reply.json(
            429,
            {'code': 'rate_limited', 'message': 'slow down'},
            headers: {
              'retry-after': ['12'],
            },
          ),
        );
      final client = _buildClient(adapter);

      await expectLater(
        client.me(),
        throwsA(
          isA<SyncException>()
              .having((e) => e.kind, 'kind', SyncErrorKind.rateLimited)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 12),
              ),
        ),
      );
    });

    test('connection errors map to retryable network failure', () async {
      final adapter = _FakeAdapter()..on('GET', '/me', _Reply.networkError());
      final client = _buildClient(adapter);

      await expectLater(
        client.me(),
        throwsA(
          isA<SyncException>()
              .having((e) => e.kind, 'kind', SyncErrorKind.network)
              .having((e) => e.isRetryable, 'isRetryable', isTrue),
        ),
      );
    });
  });
}
