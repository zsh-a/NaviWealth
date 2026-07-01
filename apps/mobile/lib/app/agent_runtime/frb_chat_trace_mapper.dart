library;

import '../../core/ai/contracts/contracts.dart';
import 'frb_chat_types.dart';

SpanTokens? frbSpanTokensFromUsage(TokenUsage? usage) {
  if (usage == null) return null;
  return SpanTokens(
    input: usage.input,
    output: usage.output,
    cacheRead: usage.cacheRead,
    cacheWrite: usage.cacheWrite,
  );
}

SpanEvent frbCompletionSpan({
  required DateTime startedAt,
  required Map<String, Object?> response,
  required int inputMessageCount,
  required String? requestedModel,
}) {
  final text = frbString(response['content']);
  final responseModel = frbString(response['model']);
  return SpanEvent(
    id: 'r1',
    parentId: kTurnSpanId,
    kind: AiSpanKind.llm,
    name: 'llm:round-1',
    startedAt: startedAt,
    endedAt: DateTime.now().toUtc(),
    status: AiSpanStatus.ok,
    tokens: frbSpanTokensFromUsage(frbUsageFromResponse(response)),
    model: responseModel.isNotEmpty ? responseModel : requestedModel,
    stopReason: frbChatStopReason(frbString(response['finish_reason'])),
    input: <String, Object?>{'messages': inputMessageCount},
    output: text.isEmpty ? null : frbClip(text),
    attributes: const <String, Object?>{
      'round': 1,
      'runtime': 'frb',
      'streaming': false,
    },
  );
}

SpanEvent frbLlmSpan({
  required int round,
  required String roundId,
  required DateTime startedAt,
  required FrbStreamRoundState state,
  required String? requestedModel,
  required AiSpanStatus status,
  String? errorCode,
  String? errorMessage,
}) {
  final response = state.response;
  final responseModel = frbString(response['model']);
  return SpanEvent(
    id: roundId,
    parentId: kTurnSpanId,
    kind: AiSpanKind.llm,
    name: 'llm:round-$round',
    startedAt: startedAt,
    endedAt: DateTime.now().toUtc(),
    status: status,
    errorCode: errorCode,
    errorMessage: errorMessage,
    tokens: frbSpanTokensFromUsage(state.usage),
    model: responseModel.isNotEmpty ? responseModel : requestedModel,
    stopReason: state.stopReason,
    input: <String, Object?>{'messages': state.inputMessageCount},
    output: state.text.isEmpty ? null : frbClip(state.text),
    attributes: <String, Object?>{'round': round, 'runtime': 'frb'},
  );
}

SpanEvent frbInvalidStreamEventSpan({
  required int round,
  required String roundId,
  required DateTime startedAt,
  required FrbStreamRoundState state,
  required String? requestedModel,
  required String message,
}) {
  return frbLlmSpan(
    round: round,
    roundId: roundId,
    startedAt: startedAt,
    state: state,
    requestedModel: requestedModel,
    status: AiSpanStatus.error,
    errorCode: 'frb_chat_event_invalid',
    errorMessage: message,
  );
}
