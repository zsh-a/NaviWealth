/// Host-side seam for assembling per-turn Agent Runtime context.
///
/// The chat feature owns the invocation point but not domain retrieval.
/// Production composition supplies an app-level implementation that reads the
/// active DomainPacks and the local Memory Runtime.
library;

import '../../../core/ai/runtime/agent_runtime/agent_runtime_context_block.dart';

class ChatContextPrepRequest {
  const ChatContextPrepRequest({
    required this.ownerUserId,
    required this.sessionId,
    required this.turnId,
    required this.userMessage,
    this.systemContext,
  });

  final String ownerUserId;
  final String sessionId;
  final String turnId;
  final String userMessage;
  final String? systemContext;
}

typedef ChatContextBlockPrep =
    Future<List<AgentRuntimeContextBlock>> Function(
      ChatContextPrepRequest request,
    );
