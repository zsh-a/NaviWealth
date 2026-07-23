library;

import 'package:dio/dio.dart';

import '../contracts/contracts.dart';
import 'agent_runtime/agent_runtime_context_block.dart';

class ChatAgentMessage {
  const ChatAgentMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role,
    'content': content,
  };
}

class ChatAgentTurnRequest {
  const ChatAgentTurnRequest({
    required this.messages,
    this.turnId,
    this.sessionId,
    this.threadId,
    this.surface,
    this.agentId,
    this.mode,
    this.portfolioSnapshot,
    this.contextPack,
    this.contextBlocks = const <AgentRuntimeContextBlock>[],
    this.contextPolicy,
    this.interactionResponse,
    this.metadata = const <String, Object?>{},
    this.model,
    this.temperature,
    this.maxOutputTokens,
    this.cancelToken,
  });

  final List<ChatAgentMessage> messages;
  final String? turnId;
  final String? sessionId;
  final String? threadId;
  final String? surface;
  final String? agentId;
  final String? mode;
  final Map<String, Object?>? portfolioSnapshot;
  final ContextPack? contextPack;
  final List<AgentRuntimeContextBlock> contextBlocks;
  final AgentRuntimeContextPolicy? contextPolicy;
  final AiInteractionResponse? interactionResponse;
  final Map<String, Object?> metadata;
  final String? model;
  final double? temperature;
  final int? maxOutputTokens;
  final CancelToken? cancelToken;
}

abstract class ChatAgent {
  Stream<AiChatEvent> runTurn(ChatAgentTurnRequest request);
}
