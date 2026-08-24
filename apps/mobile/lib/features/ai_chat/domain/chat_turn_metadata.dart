import '../../../core/ai/contracts/interaction.dart';
import '../../../core/ai/session/interaction_state.dart';
import 'chat_models.dart';

class ChatTurnMetadata {
  const ChatTurnMetadata({
    this.decision,
    this.interactionResponse,
    this.invocationTrace,
    this.inputOrigin,
    this.extra = const <String, Object?>{},
  });

  const ChatTurnMetadata.empty()
    : decision = null,
      interactionResponse = null,
      invocationTrace = null,
      inputOrigin = null,
      extra = const <String, Object?>{};

  factory ChatTurnMetadata.forDecision({
    required DecisionSelection selection,
    required String messageId,
    required String toolInvocationId,
    AiInteractionResponse? interactionResponse,
    Map<String, Object?>? invocationTrace,
    InteractionInputOrigin? inputOrigin,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    return ChatTurnMetadata(
      decision: ChatDecisionMetadata(
        selection: selection,
        messageId: messageId,
        toolInvocationId: toolInvocationId,
      ),
      interactionResponse: interactionResponse,
      invocationTrace: invocationTrace,
      inputOrigin: inputOrigin,
      extra: extra,
    );
  }

  final ChatDecisionMetadata? decision;
  final AiInteractionResponse? interactionResponse;
  final Map<String, Object?>? invocationTrace;
  final InteractionInputOrigin? inputOrigin;
  final Map<String, Object?> extra;

  bool get hasInvocationTrace => invocationTrace != null;

  String? get resumeTurnId =>
      interactionResponse == null ? null : decision?.messageId;

  Map<String, Object?> toAgentMetadata() => <String, Object?>{
    ...extra,
    if (decision case final decision?) ...decision.toAgentMetadata(),
    if (interactionResponse case final response?)
      'interaction_response': response.toJson(),
    if (inputOrigin case final origin?) 'input_origin': origin.wire,
    'invocation': ?invocationTrace,
  };
}

class ChatDecisionMetadata {
  const ChatDecisionMetadata({
    required this.selection,
    required this.messageId,
    required this.toolInvocationId,
  });

  final DecisionSelection selection;
  final String messageId;
  final String toolInvocationId;

  Map<String, Object?> toAgentMetadata() => <String, Object?>{
    'decision': selection.toJson(),
    'decision_message_id': messageId,
    'decision_tool_invocation_id': toolInvocationId,
  };
}
