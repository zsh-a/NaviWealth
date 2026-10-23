import 'package:dio/dio.dart';

import 'app_logger.dart';

/// HTTP diagnostics retain only bounded transport metadata. Request options,
/// URLs, headers, bodies and exception objects never enter the log history.
/// This is also the policy in verbose development mode.
class HttpDiagnosticsInterceptor extends Interceptor {
  HttpDiagnosticsInterceptor({required AppLogger logger, required this.service})
    : _logger = logger;

  final AppLogger _logger;
  final String service;
  final Expando<Stopwatch> _requests = Expando<Stopwatch>();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _requests[options] = Stopwatch()..start();
    _logger.event(
      'core.http.request.started',
      level: AppLogLevel.debug,
      fields: _fields(options),
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _logger.event(
      'core.http.request.completed',
      fields: <String, Object?>{
        ..._fields(response.requestOptions),
        'status_code': response.statusCode,
        'duration_ms': _finish(response.requestOptions),
      },
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logger.event(
      'core.http.request.failed',
      level: AppLogLevel.warning,
      fields: <String, Object?>{
        ..._fields(err.requestOptions),
        'status_code': err.response?.statusCode,
        'error_type': err.type.name.toLowerCase(),
        'duration_ms': _finish(err.requestOptions),
      },
    );
    handler.next(err);
  }

  Map<String, Object?> _fields(RequestOptions options) => <String, Object?>{
    'endpoint': service,
    'method': switch (options.method.toUpperCase()) {
      final method when _methods.contains(method) => method.toLowerCase(),
      _ => 'other',
    },
  };

  int _finish(RequestOptions options) {
    final stopwatch = _requests[options];
    stopwatch?.stop();
    _requests[options] = null;
    return stopwatch?.elapsedMilliseconds ?? 0;
  }
}

const _methods = {'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'};
