/// Device-only [AiChatApiClient].
///
/// The seam that lets `ChatRepository` "go through the registry"
/// unchanged: same [AiChatApiClient] surface, with app-level composition
/// injecting the active device runner. Production injects the FRB-backed
/// runner; with no injected runner (web platform / no user key / partial test
/// container) AI is unavailable and the turn surfaces a single explanatory
/// `ErrorEvent` + `DoneEvent`. There is no device-to-cloud failover.
library;

import 'package:dio/dio.dart';

import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/runtime/ai_runtime.dart';
import '../../../core/auth/auth_session.dart';
import 'ai_chat_api_client.dart';

/// Surfaced to the user when AI is invoked with no usable on-device
/// runtime. Web has no device runtime; native/desktop needs a
/// user-supplied API key + opt-in (§4.6.2).
const String kDeviceUnavailableMessage = 'device_unavailable';

class RuntimeRoutingAiChatApiClient implements AiChatApiClient {
  const RuntimeRoutingAiChatApiClient({ChatAgent? agent}) : _agent = agent;

  final ChatAgent? _agent;

  /// Which runtime a turn would hit — surfaced for the transparency
  /// badge / trace label. Always device or unavailable now.
  bool get usesDevice => _agent != null;

  @override
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
    String? model,
    CancelToken? cancelToken,
  }) {
    final agent = _agent;
    if (agent == null) return _unavailable();
    return agent.runTurn(
      ChatAgentTurnRequest(
        messages: messages,
        turnId: turnId,
        sessionId: sessionId,
        threadId: threadId,
        surface: surface,
        agentId: agentId,
        mode: mode,
        portfolioSnapshot: portfolioSnapshot,
        contextPack: contextPack,
        metadata: metadata,
        model: model,
        cancelToken: cancelToken,
      ),
    );
  }

  Stream<AiChatEvent> _unavailable() async* {
    yield const ErrorEvent(
      kDeviceUnavailableMessage,
      code: 'device_unavailable',
    );
    yield const DoneEvent(stopReason: 'error', rounds: 0);
  }
}
