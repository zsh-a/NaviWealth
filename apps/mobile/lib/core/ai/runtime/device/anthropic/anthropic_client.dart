/// Device-side Anthropic Messages API client.
///
/// Dart port of `apps/backend/src/ai/adapters/anthropic/client.rs`,
/// using the user's own key and calling the provider directly —
/// no Worker in the path. Streaming feeds [decodeAnthropicSse]; the
/// one-shot [complete] backs on-device Vision ingest.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../llm_credentials/llm_credentials.dart';
import '../llm_stream_event.dart';
import 'anthropic_sse_decoder.dart';
import 'anthropic_wire.dart';

const String _kDefaultBaseUrl = 'https://api.anthropic.com';
const String _kAnthropicVersion = '2023-06-01';

/// Max gap between SSE bytes before giving up. Anthropic emits `ping`
/// frames, so a real stall is the only thing that trips this. Sized
/// like the cloud client's watchdog.
const Duration kLlmIdleTimeout = Duration(seconds: 30);

abstract class DeviceLlmConfig {
  String get model;
}

abstract class DeviceLlmClient {
  DeviceLlmConfig get config;

  Stream<LlmStreamEvent> streamMessages(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  });

  Future<AnthropicCompletion> complete(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  });
}

/// Resolved endpoint + auth for one provider call.
class LlmConfig implements DeviceLlmConfig {
  LlmConfig({required this.apiKey, String? baseUrl, required this.model})
    : baseUrl = (baseUrl == null || baseUrl.trim().isEmpty)
          ? _kDefaultBaseUrl
          : baseUrl.trim();

  /// Resolve from the active [LlmProfile]. The profile's optional
  /// model override wins; otherwise the adapter default.
  factory LlmConfig.fromProfile(LlmProfile profile) => LlmConfig(
    apiKey: profile.apiKey,
    baseUrl: profile.baseUrl,
    model: (profile.model != null && profile.model!.trim().isNotEmpty)
        ? profile.model!.trim()
        : kDefaultDeviceModel,
  );

  final String apiKey;
  final String baseUrl;
  @override
  final String model;

  /// Endpoint resolution ported verbatim from the Rust `messages_url`
  /// so custom gateways behave identically across client and (frozen)
  /// backend.
  String messagesUrl() {
    final base = _trimTrailingSlashes(baseUrl);
    if (base.endsWith('/v1/messages') || base.endsWith('/messages')) {
      return base;
    }
    if (base.endsWith('/v1')) return '$base/messages';
    return '$base/v1/messages';
  }

  static String _trimTrailingSlashes(String s) {
    var end = s.length;
    while (end > 0 && s[end - 1] == '/') {
      end--;
    }
    return s.substring(0, end);
  }
}

/// Auth headers. Sends both `x-api-key` (native Anthropic) and
/// `Authorization: Bearer` (gateway proxies) — harmless together, the
/// native API ignores bearer and bearer gateways ignore `x-api-key`
/// (mirrors `auth_headers_bearer`).
Map<String, Object> llmAuthHeaders(String apiKey) => {
  'x-api-key': apiKey,
  'authorization': 'Bearer $apiKey',
  'anthropic-version': _kAnthropicVersion,
  'content-type': 'application/json',
};

/// Thrown when the provider rejects the request before any stream.
class LlmRequestException implements Exception {
  const LlmRequestException({required this.statusCode, required this.message});
  final int statusCode;
  final String message;
  @override
  String toString() => 'LlmRequestException($statusCode): $message';
}

class AnthropicClient implements DeviceLlmClient {
  AnthropicClient({required Dio dio, required this.config}) : _dio = dio;

  final Dio _dio;
  @override
  final LlmConfig config;

  /// Streaming Messages call → low-level provider events. One HTTP
  /// request per turn; the device loop calls this once per round.
  @override
  Stream<LlmStreamEvent> streamMessages(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  }) {
    final controller = StreamController<LlmStreamEvent>();
    StreamSubscription<LlmStreamEvent>? sub;

    Future<void> run() async {
      final Response<ResponseBody> res;
      try {
        res = await _dio.post<ResponseBody>(
          config.messagesUrl(),
          data: request.encodeStreaming(),
          cancelToken: cancelToken,
          options: Options(
            method: 'POST',
            headers: {
              ...llmAuthHeaders(config.apiKey),
              'accept': 'text/event-stream',
            },
            responseType: ResponseType.stream,
            validateStatus: (_) => true,
          ),
        );
      } on DioException catch (e, st) {
        controller.addError(e, st);
        await controller.close();
        return;
      }

      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        controller.addError(
          LlmRequestException(
            statusCode: status,
            message: await _drainError(res.data),
          ),
        );
        await controller.close();
        return;
      }
      final raw = res.data;
      if (raw == null) {
        controller.addError(
          const LlmRequestException(
            statusCode: 0,
            message: 'empty response body',
          ),
        );
        await controller.close();
        return;
      }

      final guarded = raw.stream.timeout(
        kLlmIdleTimeout,
        onTimeout: (sink) {
          if (cancelToken != null && !cancelToken.isCancelled) {
            cancelToken.cancel('idle timeout');
          }
          sink.addError(
            const LlmRequestException(
              statusCode: 0,
              message: 'provider stream idle timeout',
            ),
          );
        },
      );
      sub = decodeAnthropicSse(guarded).listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
        cancelOnError: false,
      );
    }

    controller.onCancel = () async {
      await sub?.cancel();
      if (cancelToken != null && !cancelToken.isCancelled) {
        cancelToken.cancel('listener cancelled');
      }
    };

    unawaited(run());
    return controller.stream;
  }

  /// Non-streaming single-shot call. Returns the raw `content` block
  /// list and `stop_reason` so the Vision ingest path can pull
  /// the forced `tool_use` block. Mirrors the backend `complete`.
  @override
  Future<AnthropicCompletion> complete(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  }) async {
    final Response<String> res;
    try {
      res = await _dio.post<String>(
        config.messagesUrl(),
        data: request.encodeOneShot(),
        cancelToken: cancelToken,
        options: Options(
          method: 'POST',
          headers: llmAuthHeaders(config.apiKey),
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw LlmRequestException(statusCode: 0, message: e.message ?? '$e');
    }
    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw LlmRequestException(
        statusCode: status,
        message: _errorFromBody(res.data ?? ''),
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(res.data ?? '');
    } on FormatException catch (e) {
      throw LlmRequestException(statusCode: status, message: 'llm json: $e');
    }
    if (decoded is! Map) {
      throw const LlmRequestException(
        statusCode: 0,
        message: 'llm json: not an object',
      );
    }
    final content = decoded['content'];
    return AnthropicCompletion(
      content: content is List ? content : const [],
      stopReason: decoded['stop_reason'] as String?,
    );
  }

  Future<String> _drainError(ResponseBody? body) async {
    if (body == null) return 'request failed';
    try {
      final bytes = <int>[];
      await for (final chunk in body.stream) {
        bytes.addAll(chunk);
      }
      return _errorFromBody(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return 'request failed';
    }
  }

  static String _errorFromBody(String text) {
    if (text.isEmpty) return 'request failed';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map && err['message'] is String) {
          return err['message'] as String;
        }
        if (err is String) return err;
      }
    } catch (_) {
      // fall through to raw text
    }
    return text;
  }
}

/// Result of [AnthropicClient.complete].
class AnthropicCompletion {
  const AnthropicCompletion({required this.content, this.stopReason});

  /// Raw Anthropic `content` blocks (`text` / `tool_use` / …).
  final List<Object?> content;
  final String? stopReason;
}
