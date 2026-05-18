/// Device-side OpenAI-compatible Chat Completions client.
///
/// The rest of the device agent loop is Anthropic-block shaped because
/// that was the first implemented provider. This adapter translates
/// those internal request/session blocks to OpenAI Chat Completions
/// (`/v1/chat/completions`) and maps streaming deltas back to the
/// provider-neutral [LlmStreamEvent] stream.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../llm_credentials/llm_credentials.dart';
import '../anthropic/anthropic_client.dart';
import '../anthropic/anthropic_wire.dart';
import '../llm_stream_event.dart';
import 'openai_sse_decoder.dart';

const String _kDefaultBaseUrl = 'https://api.openai.com';
const String kDefaultOpenAiDeviceModel = 'gpt-4o-mini';

class OpenAiConfig implements DeviceLlmConfig {
  OpenAiConfig({required this.apiKey, String? baseUrl, required this.model})
    : baseUrl = (baseUrl == null || baseUrl.trim().isEmpty)
          ? _kDefaultBaseUrl
          : baseUrl.trim();

  factory OpenAiConfig.fromProfile(LlmProfile profile) => OpenAiConfig(
    apiKey: profile.apiKey,
    baseUrl: profile.baseUrl,
    model: (profile.model != null && profile.model!.trim().isNotEmpty)
        ? profile.model!.trim()
        : kDefaultOpenAiDeviceModel,
  );

  final String apiKey;
  final String baseUrl;

  @override
  final String model;

  String chatCompletionsUrl() {
    final base = _trimTrailingSlashes(baseUrl);
    if (base.endsWith('/v1/chat/completions') ||
        base.endsWith('/chat/completions')) {
      return base;
    }
    if (base.endsWith('/v1')) return '$base/chat/completions';
    return '$base/v1/chat/completions';
  }

  static String _trimTrailingSlashes(String s) {
    var end = s.length;
    while (end > 0 && s[end - 1] == '/') {
      end--;
    }
    return s.substring(0, end);
  }
}

Map<String, Object> openAiAuthHeaders(String apiKey) => {
  'authorization': 'Bearer $apiKey',
  'content-type': 'application/json',
};

class OpenAiClient implements DeviceLlmClient {
  OpenAiClient({required Dio dio, required this.config}) : _dio = dio;

  final Dio _dio;

  @override
  final OpenAiConfig config;

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
          config.chatCompletionsUrl(),
          data: jsonEncode(openAiChatCompletionsPayload(request, stream: true)),
          cancelToken: cancelToken,
          options: Options(
            method: 'POST',
            headers: {
              ...openAiAuthHeaders(config.apiKey),
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
      sub = decodeOpenAiSse(guarded).listen(
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

  @override
  Future<AnthropicCompletion> complete(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  }) async {
    final Response<String> res;
    try {
      res = await _dio.post<String>(
        config.chatCompletionsUrl(),
        data: jsonEncode(openAiChatCompletionsPayload(request, stream: false)),
        cancelToken: cancelToken,
        options: Options(
          method: 'POST',
          headers: openAiAuthHeaders(config.apiKey),
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
    return _completionFromOpenAi(decoded);
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
}

Map<String, Object?> openAiChatCompletionsPayload(
  AnthropicRequest request, {
  required bool stream,
}) {
  final tools = request.tools
      .map(
        (t) => <String, Object?>{
          'type': 'function',
          'function': <String, Object?>{
            'name': t.name,
            'description': t.description,
            'parameters': t.inputSchema,
          },
        },
      )
      .toList(growable: false);
  return <String, Object?>{
    'model': request.model,
    'messages': _openAiMessages(request),
    'max_tokens': request.maxTokens,
    'stream': stream,
    if (stream) 'stream_options': <String, Object?>{'include_usage': true},
    if (tools.isNotEmpty) 'tools': tools,
    if (!stream && tools.length == 1)
      'tool_choice': <String, Object?>{
        'type': 'function',
        'function': <String, Object?>{'name': request.tools.single.name},
      },
  };
}

List<Map<String, Object?>> _openAiMessages(AnthropicRequest request) {
  final out = <Map<String, Object?>>[];
  if (request.system.trim().isNotEmpty) {
    out.add(<String, Object?>{'role': 'system', 'content': request.system});
  }
  for (final message in request.messages) {
    out.addAll(_openAiMessagesFor(message));
  }
  return out;
}

List<Map<String, Object?>> _openAiMessagesFor(AnthropicChatMessage message) {
  final content = message.content;
  if (content is String) {
    return [
      <String, Object?>{'role': message.role, 'content': content},
    ];
  }
  if (content is! List) {
    return [
      <String, Object?>{'role': message.role, 'content': '$content'},
    ];
  }

  if (message.role == 'assistant') {
    final text = StringBuffer();
    final reasoning = StringBuffer();
    final toolCalls = <Map<String, Object?>>[];
    for (final block in content) {
      if (block is! Map) continue;
      switch (block['type']) {
        case 'text':
          final t = block['text'];
          if (t is String) text.write(t);
        case 'thinking':
          final r = block['thinking'];
          if (r is String) reasoning.write(r);
        case 'tool_use':
          toolCalls.add(<String, Object?>{
            'id': block['id'] as String? ?? '',
            'type': 'function',
            'function': <String, Object?>{
              'name': block['name'] as String? ?? '',
              'arguments': jsonEncode(block['input'] ?? <String, Object?>{}),
            },
          });
      }
    }
    return [
      <String, Object?>{
        'role': 'assistant',
        'content': text.isEmpty ? null : text.toString(),
        // Reasoning models reject a follow-up tool round whose
        // assistant turn dropped its reasoning; echo it back on the
        // field the streaming decoder reads (`reasoning_content`).
        if (reasoning.isNotEmpty) 'reasoning_content': reasoning.toString(),
        if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
      },
    ];
  }

  final normalParts = <Map<String, Object?>>[];
  final toolMessages = <Map<String, Object?>>[];
  for (final block in content) {
    if (block is! Map) continue;
    switch (block['type']) {
      case 'text':
        final t = block['text'];
        if (t is String && t.isNotEmpty) {
          normalParts.add(<String, Object?>{'type': 'text', 'text': t});
        }
      case 'image':
        final source = _asMap(block['source']);
        final mediaType = source['media_type'] as String? ?? 'image/png';
        final data = source['data'] as String? ?? '';
        normalParts.add(<String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{'url': 'data:$mediaType;base64,$data'},
        });
      case 'tool_result':
        toolMessages.add(<String, Object?>{
          'role': 'tool',
          'tool_call_id': block['tool_use_id'] as String? ?? '',
          'content': block['content'] is String
              ? block['content']
              : jsonEncode(block['content']),
        });
    }
  }

  return [
    if (normalParts.isNotEmpty)
      <String, Object?>{'role': message.role, 'content': normalParts},
    ...toolMessages,
  ];
}

AnthropicCompletion _completionFromOpenAi(Object? decoded) {
  if (decoded is! Map) {
    throw const LlmRequestException(
      statusCode: 0,
      message: 'llm json: not an object',
    );
  }
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty || choices.first is! Map) {
    throw const LlmRequestException(
      statusCode: 0,
      message: 'llm json: missing choices',
    );
  }
  final choice = _asMap(choices.first);
  final message = _asMap(choice['message']);
  final content = <Object?>[];
  final text = message['content'];
  if (text is String && text.isNotEmpty) {
    content.add(AnthropicBlocks.text(text));
  }
  final toolCalls = message['tool_calls'];
  if (toolCalls is List) {
    for (final raw in toolCalls) {
      final tc = _asMap(raw);
      final fn = _asMap(tc['function']);
      final name = fn['name'] as String? ?? '';
      if (name.isEmpty) continue;
      content.add(<String, Object?>{
        'type': 'tool_use',
        'id': tc['id'] as String? ?? '',
        'name': name,
        'input': _decodeArgs(fn['arguments']),
      });
    }
  }
  final reason = openAiStopReason(choice['finish_reason'] as String?);
  return AnthropicCompletion(content: content, stopReason: reason?.wire);
}

String _errorFromBody(String text) {
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

Object? _decodeArgs(Object? args) {
  if (args is! String || args.trim().isEmpty) return <String, Object?>{};
  try {
    return jsonDecode(args);
  } on FormatException {
    return null;
  }
}

Map<String, Object?> _asMap(Object? v) =>
    v is Map ? v.map((k, val) => MapEntry(k.toString(), val)) : const {};
