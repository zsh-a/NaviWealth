import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/llm_credentials/providers.dart' as llm_credentials;
import '../../core/config/providers.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/providers.dart';
import '../../core/update/native_update_background.dart';
import '../domain_bootstrap.dart';

/// Schedules non-visual startup after Flutter has produced its first frame.
///
/// [runner] is a narrow test seam used to prove that the callback is genuinely
/// post-frame without constructing the production provider graph.
void schedulePostFrameStartup(
  ProviderContainer container, {
  @visibleForTesting Future<void> Function()? runner,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited((runner ?? () => runPostFrameStartup(container))());
  });
}

/// Mounts reactive startup providers and launches best-effort warm-ups.
///
/// This function intentionally does not await authentication, secure storage,
/// the database, network diagnostics, or native model loading. The mounted
/// providers observe auth/domain state and start their work when prerequisites
/// settle.
@visibleForTesting
Future<void> runPostFrameStartup(ProviderContainer container) async {
  final logger = container.read(loggerProvider);
  final started = Stopwatch()..start();

  try {
    container.read(authenticatedStartupBootstrapProvider);
    container.read(domainBackgroundBootstrapProvider);
    container.read(nativeUpdateBackgroundBootstrapProvider);
  } on Object catch (error, stackTrace) {
    logger.w(
      'Post-frame provider startup failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  unawaited(_warmLlmCredentials(container, logger));
  if (kDebugMode) {
    unawaited(_checkBackendHealth(container, logger));
  }
  logger.i('Post-frame startup mounted (${started.elapsed})');
}

Future<void> _warmLlmCredentials(
  ProviderContainer container,
  AppLogger logger,
) async {
  try {
    await container.read(llm_credentials.llmCredentialsProvider.future);
  } on Object catch (error, stackTrace) {
    logger.w(
      'LLM credential warm-up failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

Future<void> _checkBackendHealth(
  ProviderContainer container,
  AppLogger logger,
) async {
  final config = container.read(appConfigProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 5),
    ),
  );
  try {
    final response = await dio.get<dynamic>('/health');
    logger.i('Backend health check: ${response.statusCode} ${response.data}');
  } on DioException catch (error, stackTrace) {
    logger.w(
      'Backend health check failed (${error.type.name}: ${error.message})',
      error: error,
      stackTrace: stackTrace,
    );
  } finally {
    dio.close(force: true);
  }
}
