import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'errors.dart';
import 'sync_api_client.dart';

/// Dio-backed implementation of [SyncApiClient].
///
/// Translates Dio errors into [SyncException]s with the [SyncErrorKind] the
/// engine reacts to. The mapping mirrors `docs/sync/sync-v2.md` §5.
class DioSyncApiClient implements SyncApiClient {
  DioSyncApiClient({required Dio dio, required this.tokenProvider})
    : _dio = dio;

  final Dio _dio;

  /// Async fetcher for the bearer token. Called on every request so a JWT
  /// refresh is picked up transparently.
  final Future<String?> Function() tokenProvider;

  @override
  Future<SyncResponse> sync({
    required String deviceId,
    required int since,
    required List<RowChange> changes,
  }) async {
    final body = {
      'device_id': deviceId,
      'since': since,
      'changes': changes.map((c) => c.toJson()).toList(growable: false),
    };
    final res = await _send<Map<String, Object?>>(
      method: 'POST',
      path: '/sync',
      body: body,
    );
    final changesRaw = (res['changes'] as List? ?? const [])
        .cast<Map<Object?, Object?>>();
    final acceptedRaw = (res['accepted'] as List? ?? const [])
        .cast<Map<Object?, Object?>>();
    return SyncResponse(
      seq: (res['seq'] as num).toInt(),
      changes: changesRaw
          .map(
            (m) =>
                RowChange.fromJson(m.map((k, v) => MapEntry(k as String, v))),
          )
          .toList(growable: false),
      more: (res['more'] as bool?) ?? false,
      accepted: acceptedRaw
          .map(
            (m) => RowAck.fromJson(m.map((k, v) => MapEntry(k as String, v))),
          )
          .toList(growable: false),
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
    final secs = int.tryParse(raw.trim());
    if (secs != null) return Duration(seconds: secs);
    return null;
  }
}
