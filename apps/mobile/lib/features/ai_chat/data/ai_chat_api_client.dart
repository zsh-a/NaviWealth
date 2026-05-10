import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/ai/contracts/contracts.dart';
import '../../../core/auth/auth_session.dart';
import '../domain/chat_events.dart';
import 'sse_parser.dart';

/// Wire shape for one turn fed into `POST /ai/chat`. The relay accepts
/// either `user` or `assistant`; we never round-trip the system / error
/// roles back to the model.
class WireMessage {
  const WireMessage({required this.role, required this.content});
  final String role;
  final String content;

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role,
    'content': content,
  };
}

/// Streaming chat client. Implementations open one HTTP request per
/// turn and surface decoded SSE events to the caller.
abstract class AiChatApiClient {
  Stream<AiChatEvent> chat({
    required AuthSession session,
    required List<WireMessage> messages,
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    String? model,
    CancelToken? cancelToken,
  });
}

/// What we throw from [DioAiChatApiClient.chat] when the worker
/// rejects the request before producing a stream.
class AiChatRequestException implements Exception {
  const AiChatRequestException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => 'AiChatRequestException($statusCode): $message';
}

/// Sentinel error injected into the SSE stream when no bytes arrive
/// for [kSseIdleTimeout]. The backend's `:keepalive\n\n` comment
/// frames refresh the watchdog every 10s, so this only fires when
/// bytes really stop flowing — almost always the spawn_local task
/// being reclaimed mid-flight.
class SseIdleTimeout implements Exception {
  const SseIdleTimeout();

  @override
  String toString() => 'SseIdleTimeout';
}

/// Maximum gap between SSE bytes before the watchdog gives up. Sized
/// 3× the backend keepalive cadence so a single missed tick doesn't
/// trip the alarm.
const Duration kSseIdleTimeout = Duration(seconds: 30);

/// Dio-backed implementation. Streams the SSE body via
/// `ResponseType.stream` so the caller gets `text` / `tool_call` events
/// as they arrive on native targets.
///
/// On Web, Dio's browser adapter currently buffers the full response
/// before exposing the stream — the user-visible effect is that the
/// assistant turn appears all at once instead of progressively. The
/// chat still works end-to-end; a true streaming web adapter is a
/// follow-up.
class DioAiChatApiClient implements AiChatApiClient {
  DioAiChatApiClient({required Dio dio, this.protocolVersion = '1'})
    : _dio = dio;

  final Dio _dio;
  final String protocolVersion;

  @override
  Stream<AiChatEvent> chat({
    required AuthSession session,
    required List<WireMessage> messages,
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    String? model,
    CancelToken? cancelToken,
  }) {
    final controller = StreamController<AiChatEvent>();
    StreamSubscription<AiChatEvent>? sub;

    Future<void> run() async {
      final body = <String, Object?>{
        'messages': messages.map((m) => m.toJson()).toList(),
        'portfolio_snapshot': ?portfolioSnapshot,
        if (contextPack != null) 'context_pack': contextPack.toJson(),
        if (model != null && model.isNotEmpty) 'model': model,
      };
      final Response<ResponseBody> res;
      try {
        res = await _dio.post<ResponseBody>(
          '/ai/chat',
          data: jsonEncode(body),
          cancelToken: cancelToken,
          options: Options(
            method: 'POST',
            headers: <String, Object>{
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'text/event-stream',
              'Authorization': 'Bearer ${session.accessToken}',
              'Sync-Protocol-Version': protocolVersion,
            },
            responseType: ResponseType.stream,
            // Honour the worker's status codes manually so a 401/429 with a
            // JSON body isn't surfaced as a generic Dio exception.
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
        // Best-effort drain of the JSON error body so callers can show
        // the worker's `error` field instead of "request failed".
        final raw = res.data;
        var message = 'request failed';
        if (raw != null) {
          try {
            final bytes = <int>[];
            await for (final chunk in raw.stream) {
              bytes.addAll(chunk);
            }
            final text = utf8.decode(bytes, allowMalformed: true);
            final decoded = jsonDecode(text);
            if (decoded is Map && decoded['error'] is String) {
              message = decoded['error'] as String;
            } else {
              message = text.isEmpty ? 'request failed' : text;
            }
          } catch (_) {
            // Fall through with the default message.
          }
        }
        controller.addError(
          AiChatRequestException(statusCode: status, message: message),
        );
        await controller.close();
        return;
      }

      final raw = res.data;
      if (raw == null) {
        controller.addError(
          const AiChatRequestException(
            statusCode: 0,
            message: 'empty response body',
          ),
        );
        await controller.close();
        return;
      }

      // Watchdog runs against the *byte* stream so the backend's
      // `:keepalive\n\n` comment frames count as activity even though
      // `decodeSseEvents` strips them. Without this we'd false-trip
      // every time the model is busy mid-round (no real events for
      // >30s) even though the connection is fine.
      final guarded = raw.stream.timeout(
        kSseIdleTimeout,
        onTimeout: (sink) {
          if (cancelToken != null && !cancelToken.isCancelled) {
            cancelToken.cancel('idle timeout');
          }
          sink.addError(const SseIdleTimeout());
        },
      );
      sub = decodeSseEvents(guarded).listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
        cancelOnError: false,
      );
    }

    controller.onCancel = () async {
      await sub?.cancel();
      // Cancel the underlying request when the listener bails so we
      // don't keep the worker spinning.
      if (cancelToken != null && !cancelToken.isCancelled) {
        cancelToken.cancel('listener cancelled');
      }
    };

    unawaited(run());
    return controller.stream;
  }
}
