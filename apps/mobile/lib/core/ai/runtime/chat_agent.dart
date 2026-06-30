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
    this.portfolioSnapshot,
    this.contextPack,
    this.model,
    this.cancelToken,
  });

  final List<ChatAgentMessage> messages;
  final Map<String, Object?>? portfolioSnapshot;
  final ContextPack? contextPack;
  final String? model;
  final CancelToken? cancelToken;
}

abstract class ChatAgent {
  Stream<AiChatEvent> runTurn(ChatAgentTurnRequest request);
}
