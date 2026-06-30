library;

import 'package:dio/dio.dart';

import '../contracts/contracts.dart';

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
    this.metadata = const <String, Object?>{},
    this.model,
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
  final Map<String, Object?> metadata;
  final String? model;
  final CancelToken? cancelToken;
}

abstract class ChatAgent {
  Stream<AiChatEvent> runTurn(ChatAgentTurnRequest request);
}
