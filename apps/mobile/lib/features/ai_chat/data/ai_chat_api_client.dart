/// §4.6 W-D7 — chat client surface. The cloud relay transport
/// (`DioAiChatApiClient` → `POST /ai/chat`) was removed when the cloud
/// AI backend was deleted; turns now run on-device via
/// [RuntimeRoutingAiChatApiClient] over the [DeviceChatRunner]. This
/// file keeps the shared contract types: the [AiChatApiClient]
/// interface `ChatRepository` injects, the [WireMessage] turn shape,
/// and the request-level error sentinel `ChatRepository` still
/// classifies.
library;

import 'package:dio/dio.dart';

import '../../../core/ai/contracts/contracts.dart';
import '../../../core/auth/auth_session.dart';
import '../domain/chat_events.dart';

/// Wire shape for one turn. Kept as the typed turn contract between
/// `ChatRepository` and the device runtime.
class WireMessage {
  const WireMessage({required this.role, required this.content});
  final String role;
  final String content;

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role,
    'content': content,
  };
}

/// Streaming chat client. The only implementation now is
/// [RuntimeRoutingAiChatApiClient] (device-only); the abstraction is
/// retained so `ChatRepository` and its tests stay decoupled from the
/// runtime.
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

/// Request-level failure surfaced to `ChatRepository` (it categorises
/// this distinctly from mid-stream errors). Still thrown by callers
/// that reject a turn before any stream is produced.
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
