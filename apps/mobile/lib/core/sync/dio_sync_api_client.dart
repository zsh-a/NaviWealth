import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../data/domain/hlc.dart';
import 'errors.dart';
import 'op.dart';
import 'sync_api_client.dart';

/// Dio-backed implementation of [SyncApiClient].
///
/// Translates Dio errors into [SyncException]s with the [SyncErrorKind]
/// the engine reacts to. The mapping mirrors `docs/sync-protocol.md` §5.4.
class DioSyncApiClient implements SyncApiClient {
  DioSyncApiClient({required Dio dio, required this.tokenProvider})
    : _dio = dio;

  final Dio _dio;

  /// Async fetcher for the bearer token. Called on every request so JWT
  /// refresh from FIR-30 is transparent.
  final Future<String?> Function() tokenProvider;

  @override
  Future<MeResponse> me() async {
    final res = await _send<Map<String, Object?>>(method: 'GET', path: '/me');
    return MeResponse(
      userId: res['user_id'] as String,
      serverNow: DateTime.parse(res['server_now'] as String).toUtc(),
      serverHlc: Hlc.parse(res['server_hlc'] as String),
    );
  }

  @override
  Future<PushResponse> push({
    required String deviceId,
    required List<Op> ops,
  }) async {
    final body = {
      'device_id': deviceId,
      'ops': ops.map((o) => o.toJson()).toList(growable: false),
    };
    final res = await _send<Map<String, Object?>>(
      method: 'POST',
      path: '/sync/push',
      body: body,
    );
    final rejectedRaw = (res['rejected'] as List?) ?? const [];
    final rejected = rejectedRaw
        .cast<Map<Object?, Object?>>()
        .map(
          (r) => PushRejection(
            opId: r['op_id'] as String,
            code: r['code'] as String,
            message: r['message'] as String?,
          ),
        )
        .toList(growable: false);
    return PushResponse(
      accepted: res['accepted'] as int,
      rejected: rejected,
      serverHlcHigh: Hlc.parse(res['server_hlc_high'] as String),
      serverNow: DateTime.parse(res['server_now'] as String).toUtc(),
    );
  }

  @override
  Future<PullResponse> pull({
    required String deviceId,
    required Hlc since,
    int limit = kPullPageMaxOps,
  }) async {
    final res = await _send<Map<String, Object?>>(
      method: 'GET',
      path: '/sync/pull',
      query: {
        'since': since.toString(),
        'device_id': deviceId,
        'limit': limit.toString(),
      },
    );
    final opsRaw = (res['ops'] as List).cast<Map<Object?, Object?>>();
    final ops = opsRaw
        .map((m) => Op.fromJson(m.map((k, v) => MapEntry(k as String, v))))
        .toList(growable: false);
    return PullResponse(
      ops: ops,
      serverHlcHigh: Hlc.parse(res['server_hlc_high'] as String),
      hasMore: res['has_more'] as bool,
      serverNow: DateTime.parse(res['server_now'] as String).toUtc(),
    );
  }

  Future<T> _send<T>({
    required String method,
    required String path,
    Map<String, String>? query,
    Object? body,
  }) async {
    final token = await tokenProvider();
    final headers = <String, Object>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      'Sync-Protocol-Version': '$kSyncProtocolVersion',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    try {
      final res = await _dio.request<dynamic>(
        path,
        options: Options(
          method: method,
          headers: headers,
          // Don't let Dio throw for non-2xx — we map to SyncException
          // ourselves so 4xx data is preserved.
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
        ),
        queryParameters: query,
        data: body == null ? null : jsonEncode(body),
      );
      final status = res.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        if (res.data == null ||
            (res.data is String && (res.data as String).isEmpty)) {
          if (T == dynamic) return null as T;
          throw SyncException(
            SyncErrorKind.unknown,
            statusCode: status,
            message: 'empty body on success',
          );
        }
        final decoded = res.data is String
            ? jsonDecode(res.data as String)
            : res.data;
        if (decoded is T) return decoded;
        if (decoded is Map) {
          // Generic comparison `T == Map<String, Object?>` doesn't parse —
          // every endpoint returns a JSON object, so coerce dynamic-valued
          // maps to the expected Map<String, Object?> shape.
          final coerced = <String, Object?>{
            for (final entry in decoded.entries)
              entry.key.toString(): entry.value,
          };
          return coerced as T;
        }
        throw SyncException(
          SyncErrorKind.unknown,
          statusCode: status,
          message: 'unexpected body type for $path',
        );
      }
      throw _mapStatus(res, path);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw SyncException(
          SyncErrorKind.network,
          message: e.message,
          cause: e,
        );
      }
      if (e.response != null) {
        throw _mapStatus(e.response!, path);
      }
      throw SyncException(SyncErrorKind.unknown, message: e.message, cause: e);
    }
  }

  SyncException _mapStatus(Response<dynamic> res, String path) {
    final status = res.statusCode ?? 0;
    Object? bodyJson;
    try {
      bodyJson = res.data is String ? jsonDecode(res.data as String) : res.data;
    } catch (_) {
      bodyJson = null;
    }
    final body = SyncErrorBody.fromJson(bodyJson);
    final code = body.code;
    final retryAfter = _retryAfterHeader(res);
    SyncErrorKind kind;
    switch (status) {
      case 401:
        kind = SyncErrorKind.unauthorized;
      case 426:
        kind = SyncErrorKind.protocolVersion;
      case 409:
        kind = SyncErrorKind.clockSkew;
      case 413:
        kind = SyncErrorKind.payloadTooLarge;
      case 429:
        kind = SyncErrorKind.rateLimited;
      default:
        if (status >= 500) {
          kind = SyncErrorKind.server;
        } else if (status >= 400) {
          kind = SyncErrorKind.badRequest;
        } else {
          kind = SyncErrorKind.unknown;
        }
    }
    return SyncException(
      kind,
      statusCode: status,
      code: code,
      message: body.message ?? 'sync $path returned $status',
      retryAfter: retryAfter,
    );
  }

  Duration? _retryAfterHeader(Response<dynamic> res) {
    final raw = res.headers.value('retry-after');
    if (raw == null) return null;
    // Spec only requires the integer-seconds form (`docs/sync-protocol.md`
    // §5.4). HTTP-date variant is rare and not worth pulling dart:io for —
    // fall through means "back off using the policy default".
    final secs = int.tryParse(raw.trim());
    if (secs != null) return Duration(seconds: secs);
    return null;
  }
}
