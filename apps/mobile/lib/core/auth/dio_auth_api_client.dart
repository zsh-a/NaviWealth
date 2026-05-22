import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'auth_api_client.dart';
import 'auth_errors.dart';
import 'auth_session.dart';

/// Dio-backed [AuthApiClient].
///
/// Maps HTTP status to [AuthErrorKind] so call-sites can react without
/// touching Dio types:
///   - 401 on `/auth/login`        → [AuthErrorKind.invalidCredentials]
///   - 401 on every other endpoint → [AuthErrorKind.unauthorized]
///   - 4xx other than 401          → [AuthErrorKind.badRequest]
///   - 5xx                         → [AuthErrorKind.server]
///   - connection / timeout        → [AuthErrorKind.network]
///
/// The login call attaches no `Authorization` header; refresh / list /
/// logout attach the bearer from the caller-supplied session, bypassing any
/// global interceptor (so tests can use a vanilla [Dio]).
class DioAuthApiClient implements AuthApiClient {
  DioAuthApiClient({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
    String? deviceName,
    String? deviceId,
  }) async {
    final body = <String, Object?>{
      'email': email.trim(),
      'password': password,
      if (deviceName != null && deviceName.isNotEmpty)
        'device_name': deviceName,
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
    };
    final res = await _post('/auth/login', body: body, isLogin: true);
    return AuthSession.fromJson(res);
  }

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
    String? deviceName,
    String? deviceId,
  }) async {
    final body = <String, Object?>{
      'email': email.trim(),
      'password': password,
      if (deviceName != null && deviceName.isNotEmpty)
        'device_name': deviceName,
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
    };
    final res = await _post('/auth/register', body: body, isRegister: true);
    return AuthSession.fromJson(res);
  }

  @override
  Future<RefreshedToken> refresh(AuthSession current) async {
    final res = await _post('/auth/refresh', bearer: current.accessToken);
    return RefreshedToken(
      accessToken: res['access_token'] as String,
      expiresAt: DateTime.parse(res['expires_at'] as String).toUtc(),
    );
  }

  @override
  Future<DevicesResponse> listDevices(AuthSession current) async {
    final res = await _get('/auth/devices', bearer: current.accessToken);
    final raw = (res['devices'] as List).cast<Map<Object?, Object?>>();
    final devices = raw
        .map(
          (m) => AuthDevice.fromJson(m.map((k, v) => MapEntry(k as String, v))),
        )
        .toList(growable: false);
    return DevicesResponse(
      devices: devices,
      currentDeviceId: res['current_device_id'] as String,
    );
  }

  @override
  Future<void> logoutDevice(AuthSession current, String deviceId) async {
    await _post(
      '/auth/logout/${Uri.encodeComponent(deviceId)}',
      bearer: current.accessToken,
    );
  }

  Future<Map<String, Object?>> _get(String path, {String? bearer}) =>
      _send(method: 'GET', path: path, bearer: bearer);

  Future<Map<String, Object?>> _post(
    String path, {
    Object? body,
    String? bearer,
    bool isLogin = false,
    bool isRegister = false,
  }) => _send(
    method: 'POST',
    path: path,
    body: body,
    bearer: bearer,
    isLogin: isLogin,
    isRegister: isRegister,
  );

  Future<Map<String, Object?>> _send({
    required String method,
    required String path,
    Object? body,
    String? bearer,
    bool isLogin = false,
    bool isRegister = false,
  }) async {
    final headers = <String, Object>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      if (bearer != null && bearer.isNotEmpty)
        'Authorization': 'Bearer $bearer',
    };
    try {
      final res = await _dio.request<dynamic>(
        path,
        options: Options(
          method: method,
          headers: headers,
          // Map status manually so we can preserve 4xx body/codes.
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
        ),
        data: body == null ? null : jsonEncode(body),
      );
      final status = res.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        if (res.data == null ||
            (res.data is String && (res.data as String).isEmpty)) {
          // Some endpoints (logout) return `{ok: true}`; others may have an
          // empty body. Surface an empty map so callers don't NPE.
          return const <String, Object?>{};
        }
        final decoded = res.data is String
            ? jsonDecode(res.data as String)
            : res.data;
        if (decoded is Map) {
          return <String, Object?>{
            for (final entry in decoded.entries)
              entry.key.toString(): entry.value,
          };
        }
        throw AuthException(
          AuthErrorKind.unknown,
          statusCode: status,
          message: 'unexpected JSON shape from $path',
        );
      }
      throw _mapStatus(
        status,
        res,
        path,
        isLogin: isLogin,
        isRegister: isRegister,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw AuthException(
          AuthErrorKind.network,
          message: e.message,
          cause: e,
        );
      }
      if (e.response != null) {
        final status = e.response!.statusCode ?? 0;
        throw _mapStatus(
          status,
          e.response!,
          path,
          isLogin: isLogin,
          isRegister: isRegister,
        );
      }
      throw AuthException(AuthErrorKind.unknown, message: e.message, cause: e);
    }
  }

  AuthException _mapStatus(
    int status,
    Response<dynamic> res,
    String path, {
    required bool isLogin,
    required bool isRegister,
  }) {
    final message = _readErrorMessage(res.data);
    if (status == 401) {
      return AuthException(
        isLogin ? AuthErrorKind.invalidCredentials : AuthErrorKind.unauthorized,
        statusCode: status,
        message: message,
      );
    }
    if (status >= 500) {
      return AuthException(
        AuthErrorKind.server,
        statusCode: status,
        message: message ?? 'server error from $path',
      );
    }
    if (isRegister && status == 409) {
      return AuthException(
        AuthErrorKind.accountExists,
        statusCode: status,
        message: message,
      );
    }
    if (status >= 400) {
      return AuthException(
        AuthErrorKind.badRequest,
        statusCode: status,
        message: message ?? '$path returned $status',
      );
    }
    return AuthException(
      AuthErrorKind.unknown,
      statusCode: status,
      message: message ?? '$path returned $status',
    );
  }

  String? _readErrorMessage(Object? data) {
    if (data == null) return null;
    Object? json;
    try {
      json = data is String ? jsonDecode(data) : data;
    } on FormatException {
      return null;
    }
    if (json is Map) {
      final msg = json['error'] ?? json['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    return null;
  }
}
