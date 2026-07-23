/// Chat client surface. The cloud relay transport
/// (`DioAiChatApiClient` → `POST /ai/chat`) was removed when the cloud
/// AI backend was deleted; turns now run on-device through the app-composed
/// [ChatAgent]. This file keeps the [AiChatApiClient] interface
/// `ChatRepository` injects, the [WireMessage] turn alias, and the
/// request-level error sentinel `ChatRepository` still classifies.
library;

import 'package:dio/dio.dart';

import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_context_block.dart';
import '../../../core/ai/runtime/chat_agent.dart';
import '../../../core/auth/auth_session.dart';

/// Wire shape for one turn. Kept as the typed turn contract between
/// `ChatRepository` and the device runtime.
typedef WireMessage = ChatAgentMessage;

/// Streaming chat client. The only implementation now is
/// [RuntimeRoutingAiChatApiClient] (device-only); the abstraction is
/// retained so `ChatRepository` and its tests stay decoupled from the
/// runtime.
abstract class AiChatApiClient {
  Stream<AiChatEvent> chat({
    required AuthSession session,
    required List<WireMessage> messages,
    String? turnId,
    String? sessionId,
    String? threadId,
    String? surface,
    String? agentId,
    String? mode,
    Map<String, Object?> metadata = const <String, Object?>{},
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    List<AgentRuntimeContextBlock> contextBlocks =
        const <AgentRuntimeContextBlock>[],
    AgentRuntimeContextPolicy? contextPolicy,
    AiInteractionResponse? interactionResponse,
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
