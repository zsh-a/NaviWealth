import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/dio_sync_api_client.dart';
import 'package:naviwealth/core/sync/errors.dart';
import 'package:naviwealth/core/sync/sync_api_client.dart';

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

RowChange _change({
  String table = 'accounts',
  String id = 'A1',
  Map<String, Object?>? payload = const {'name': 'Cash'},
  String version = '1716381000123.0000-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  bool deleted = false,
}) {
  return RowChange(
    table: table,
    id: id,
    payload: payload,
    version: version,
    deleted: deleted,
  );
}

void main() {
  group('DioSyncApiClient.sync wire protocol', () {
    test('encodes the request body and headers', () async {
      final adapter = _FakeAdapter()
        ..on(
          'POST',
          '/sync',
          _Reply.ok({'seq': 1342, 'changes': <Object?>[], 'more': false}),
        );
      final client = _buildClient(adapter);

      await client.sync(
        deviceId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        since: 1287,
        changes: [_change(), _change(id: 'A2')],
      );

      final captured = adapter.calls.single;
      final headers = captured.options.headers;
      expect(headers['Sync-Protocol-Version'], '$kSyncProtocolVersion');
      expect(headers['Content-Type'], 'application/json; charset=utf-8');
      expect(headers['Accept'], 'application/json');
      expect(headers['Authorization'], 'Bearer sync-token');

      final body = jsonDecode(captured.body) as Map<String, Object?>;
      expect(body['device_id'], 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      expect(body['since'], 1287);
      final changes = body['changes'] as List<Object?>;
      expect(changes, hasLength(2));
      final first = changes.first as Map<String, Object?>;
      expect(first['table'], 'accounts');
      expect(first['id'], 'A1');
      expect(first['payload'], {'name': 'Cash'});
      expect(first['deleted'], false);
    });

    test('encodes a deleted row with a null payload', () async {
      final adapter = _FakeAdapter()
        ..on(
          'POST',
          '/sync',
          _Reply.ok({'seq': 5, 'changes': <Object?>[], 'more': false}),
        );
      final client = _buildClient(adapter);

      await client.sync(
        deviceId: 'd',
        since: 0,
        changes: [_change(payload: null, deleted: true)],
      );

      final body = jsonDecode(adapter.calls.single.body) as Map<String, Object?>;
      final change = (body['changes'] as List).single as Map<String, Object?>;
      expect(change['payload'], isNull);
      expect(change['deleted'], true);
    });

    test('parses the response: seq, changes and more', () async {
      final adapter = _FakeAdapter()
        ..on(
          'POST',
          '/sync',
          _Reply.ok({
            'seq': 1342,
            'changes': [
              {
                'table': 'assets',
                'id': 'a1b2',
                'payload': {'name': 'Brokerage'},
                'version': '1716381005000.0000-bbbb',
                'device_id': 'bbbb',
                'deleted': false,
                'seq': 1340,
              },
            ],
            'more': true,
          }),
        );
      final client = _buildClient(adapter);

      final res = await client.sync(deviceId: 'd', since: 0, changes: const []);

      expect(res.seq, 1342);
      expect(res.more, isTrue);
      expect(res.changes, hasLength(1));
      final row = res.changes.single;
      expect(row.table, 'assets');
      expect(row.id, 'a1b2');
      expect(row.payload, {'name': 'Brokerage'});
      expect(row.version, '1716381005000.0000-bbbb');
      expect(row.deviceId, 'bbbb');
      expect(row.seq, 1340);
      expect(row.deleted, isFalse);
    });

    test('parses a tombstone change in the response', () async {
      final adapter = _FakeAdapter()
        ..on(
          'POST',
          '/sync',
          _Reply.ok({
            'seq': 9,
            'changes': [
              {
                'table': 'accounts',
                'id': 'gone',
                'payload': {'name': 'Old', 'deleted_at': 1700000000},
                'version': '1716381005000.0000-bbbb',
                'device_id': 'bbbb',
                'deleted': true,
                'seq': 8,
              },
            ],
            'more': false,
          }),
        );
      final client = _buildClient(adapter);

      final res = await client.sync(deviceId: 'd', since: 0, changes: const []);
      expect(res.changes.single.deleted, isTrue);
    });

    test('maps status codes to SyncException kinds', () async {
      final cases = <int, SyncErrorKind>{
        401: SyncErrorKind.unauthorized,
        413: SyncErrorKind.payloadTooLarge,
        426: SyncErrorKind.protocolVersion,
        429: SyncErrorKind.rateLimited,
        500: SyncErrorKind.server,
      };

      for (final entry in cases.entries) {
        final adapter = _FakeAdapter()
          ..on(
            'POST',
            '/sync',
            _Reply.json(entry.key, {
              'code': 'c_${entry.key}',
              'message': 'status ${entry.key}',
            }),
          );
        final client = _buildClient(adapter);

        await expectLater(
          client.sync(deviceId: 'd', since: 0, changes: const []),
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
          'POST',
          '/sync',
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
        client.sync(deviceId: 'd', since: 0, changes: const []),
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

    test('connection errors map to a retryable network failure', () async {
      final adapter = _FakeAdapter()
        ..on('POST', '/sync', _Reply.networkError());
      final client = _buildClient(adapter);

      await expectLater(
        client.sync(deviceId: 'd', since: 0, changes: const []),
        throwsA(
          isA<SyncException>()
              .having((e) => e.kind, 'kind', SyncErrorKind.network)
              .having((e) => e.isRetryable, 'isRetryable', isTrue),
        ),
      );
    });
  });
}
