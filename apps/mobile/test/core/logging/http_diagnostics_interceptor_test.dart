import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/config/providers.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/logging/http_diagnostics_interceptor.dart';
import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/core/sync/providers.dart';

class _PrivateResponseAdapter implements HttpClientAdapter {
  bool fail = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (fail) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        error: StateError('private-exception-content'),
        message: 'private-error-message',
        response: Response<Object?>(
          requestOptions: options,
          statusCode: 401,
          data: {'password': 'private-error-body'},
          headers: Headers.fromMap({
            'set-cookie': ['private-cookie'],
          }),
        ),
      );
    }
    return ResponseBody.fromString(
      '{"access_token":"private-response-token","balance":987654321}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        'set-cookie': ['private-cookie'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  for (final environment in [AppEnvironment.dev, AppEnvironment.prod]) {
    for (final service in ['auth', 'sync']) {
      test(
        '$service $environment logs metadata without retaining HTTP secrets',
        () async {
          final container = ProviderContainer(
            overrides: [
              appConfigProvider.overrideWithValue(
                AppConfig(
                  apiBaseUrl: 'https://private-host.example',
                  environment: environment,
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          final dio = service == 'auth'
              ? container.read(authDioProvider)
              : container.read(syncDioProvider);
          expect(
            dio.interceptors.whereType<HttpDiagnosticsInterceptor>(),
            hasLength(1),
          );
          final adapter = _PrivateResponseAdapter();
          dio.httpClientAdapter = adapter;
          addTearDown(() => dio.close(force: true));

          await dio.post<Object?>(
            '/private-account-path?token=private-query-token',
            data: {'password': 'private-request-password', 'amount': 123456789},
            options: Options(
              headers: {'Authorization': 'Bearer private-header-token'},
            ),
          );
          adapter.fail = true;
          await expectLater(
            dio.post<Object?>(
              '/private-error-path',
              data: 'private-error-request',
            ),
            throwsA(isA<DioException>()),
          );
          final history = container
              .read(talkerProvider)
              .history
              .map((entry) => entry.generateTextMessage())
              .join('\n');
          for (final output in [history, sanitizeDiagnosticExport(history)]) {
            expect(output, isNot(contains('private-')));
            expect(output, isNot(contains('987654321')));
            expect(output, isNot(contains('123456789')));
          }
          expect(history, contains('core.http.request.failed'));
          expect(history, contains('"status_code":401'));
          expect(history, contains('"endpoint":"$service"'));
          if (environment == AppEnvironment.dev) {
            expect(history, contains('core.http.request.started'));
            expect(history, contains('"status_code":200'));
            expect(history, contains('"method":"post"'));
            expect(history, contains('"duration_ms":'));
          } else {
            expect(history, isNot(contains('core.http.request.started')));
          }
        },
      );
    }
  }

  test('legacy export removes quoted and unquoted credentials', () {
    final output = sanitizeDiagnosticExport('''{"password": "private multi word password", "refresh_token": "private-refresh"}
passphrase='private multi word passphrase' api_key=private-key token=private-token
client_secret: private-client-secret Authorization: Bearer private-bearer''');
    expect(output, isNot(contains('private')));
    expect(output, contains('<redacted>'));
  });
}
