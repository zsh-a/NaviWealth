library;

import 'package:naviwealth/app/agent_runtime/chat/frb_chat_types.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';

const String kFrbChatStreamCancelledKind = '__frb_stream_cancelled';

sealed class FrbChatStreamEvent {
  const FrbChatStreamEvent({
    required this.kind,
    required this.round,
    required this.metadata,
  });

  final String kind;
  final int round;
  final Map<String, Object?> metadata;

  static FrbChatStreamEvent parse(Map<String, Object?> raw) {
    final kind = frbString(raw['kind']);
    final round = frbInt(raw['round']);
    final metadata = frbObject(raw['metadata']);
    return switch (kind) {
      kFrbChatStreamCancelledKind => FrbChatCancelledEvent(
        round: round,
        metadata: metadata,
      ),
      'started' => FrbChatStartedEvent(round: round, metadata: metadata),
      'llm_started' => FrbChatLlmStartedEvent(round: round, metadata: metadata),
      'delta' => FrbChatDeltaEvent(
        round: round,
        metadata: metadata,
        content: frbString(raw['content']),
      ),
      'thinking_delta' => FrbChatThinkingDeltaEvent(
        round: round,
        metadata: metadata,
        content: frbString(raw['content']),
      ),
      'thinking_signature_delta' => FrbChatThinkingSignatureDeltaEvent(
        round: round,
        metadata: metadata,
        content: frbString(raw['content']),
      ),
      'usage' => _parseUsage(raw, round: round, metadata: metadata),
      'tool_call_start' => _parseToolCallStart(
        raw,
        round: round,
        metadata: metadata,
      ),
      'tool_call_delta' => _parseToolCallDelta(
        raw,
        round: round,
        metadata: metadata,
      ),
      'tool_call_end' => _parseToolCallEnd(
        raw,
        round: round,
        metadata: metadata,
      ),
      'finished' || 'round_finished' => _parseRoundFinished(
        raw,
        kind: kind,
        round: round,
        metadata: metadata,
      ),
      'error' => FrbChatErrorEvent(round: round, metadata: metadata),
      'done' => FrbChatDoneEvent(round: round, metadata: metadata),
      _ => FrbUnknownChatEvent(kind: kind, round: round, metadata: metadata),
    };
  }
}

final class FrbChatCancelledEvent extends FrbChatStreamEvent {
  const FrbChatCancelledEvent({required super.round, required super.metadata})
    : super(kind: kFrbChatStreamCancelledKind);
}

final class FrbChatStartedEvent extends FrbChatStreamEvent {
  const FrbChatStartedEvent({required super.round, required super.metadata})
    : super(kind: 'started');
}

final class FrbChatLlmStartedEvent extends FrbChatStreamEvent {
  const FrbChatLlmStartedEvent({required super.round, required super.metadata})
    : super(kind: 'llm_started');
}

final class FrbChatDeltaEvent extends FrbChatStreamEvent {
  const FrbChatDeltaEvent({
    required super.round,
    required super.metadata,
    required this.content,
  }) : super(kind: 'delta');

  final String content;
}

final class FrbChatThinkingDeltaEvent extends FrbChatStreamEvent {
  const FrbChatThinkingDeltaEvent({
    required super.round,
    required super.metadata,
    required this.content,
  }) : super(kind: 'thinking_delta');

  final String content;
}

final class FrbChatThinkingSignatureDeltaEvent extends FrbChatStreamEvent {
  const FrbChatThinkingSignatureDeltaEvent({
    required super.round,
    required super.metadata,
    required this.content,
  }) : super(kind: 'thinking_signature_delta');

  final String content;
}

final class FrbChatUsageEvent extends FrbChatStreamEvent {
  const FrbChatUsageEvent({
    required super.round,
    required super.metadata,
    required this.usage,
  }) : super(kind: 'usage');

  final TokenUsage usage;
}

final class FrbChatToolCallStartEvent extends FrbChatStreamEvent {
  const FrbChatToolCallStartEvent({
    required super.round,
    required super.metadata,
    required this.id,
    required this.name,
  }) : super(kind: 'tool_call_start');

  final String id;
  final String name;
}

final class FrbChatToolCallDeltaEvent extends FrbChatStreamEvent {
  const FrbChatToolCallDeltaEvent({
    required super.round,
    required super.metadata,
    required this.id,
    required this.partialInputJson,
  }) : super(kind: 'tool_call_delta');

  final String id;
  final String partialInputJson;
}

final class FrbChatToolCallEndEvent extends FrbChatStreamEvent {
  const FrbChatToolCallEndEvent({
    required super.round,
    required super.metadata,
    required this.id,
    required this.name,
    required this.input,
  }) : super(kind: 'tool_call_end');

  final String id;
  final String name;
  final Object? input;
}

final class FrbChatRoundFinishedEvent extends FrbChatStreamEvent {
  const FrbChatRoundFinishedEvent({
    required super.kind,
    required super.round,
    required super.metadata,
    required this.response,
  });

  final Map<String, Object?> response;
}

final class FrbChatErrorEvent extends FrbChatStreamEvent {
  const FrbChatErrorEvent({required super.round, required super.metadata})
    : super(kind: 'error');

  String get code {
    final value = frbString(metadata['code']);
    return value.isEmpty ? 'frb_chat_error' : value;
  }

  String get message {
    final value = frbString(metadata['message']);
    return value.isEmpty ? 'frb_chat_error' : value;
  }
}

final class FrbChatDoneEvent extends FrbChatStreamEvent {
  const FrbChatDoneEvent({required super.round, required super.metadata})
    : super(kind: 'done');
}

final class FrbInvalidChatEvent extends FrbChatStreamEvent {
  const FrbInvalidChatEvent({
    required super.kind,
    required super.round,
    required super.metadata,
    required this.message,
  });

  final String message;
}

final class FrbUnknownChatEvent extends FrbChatStreamEvent {
  const FrbUnknownChatEvent({
    required super.kind,
    required super.round,
    required super.metadata,
  });

  String get message => 'unknown FRB LLM stream event kind: $kind';
}

FrbChatStreamEvent _parseUsage(
  Map<String, Object?> raw, {
  required int round,
  required Map<String, Object?> metadata,
}) {
  final usage = frbUsageFromValue(raw['usage']);
  if (usage == null) {
    return FrbInvalidChatEvent(
      kind: 'usage',
      round: round,
      metadata: metadata,
      message: 'FRB LLM usage event requires usage',
    );
  }
  return FrbChatUsageEvent(round: round, metadata: metadata, usage: usage);
}

FrbChatStreamEvent _parseToolCallStart(
  Map<String, Object?> raw, {
  required int round,
  required Map<String, Object?> metadata,
}) {
  final id = frbString(raw['tool_call_id']);
  final name = frbString(raw['tool_name']);
  if (id.isEmpty || name.isEmpty) {
    return FrbInvalidChatEvent(
      kind: 'tool_call_start',
      round: round,
      metadata: metadata,
      message:
          'FRB LLM tool_call_start event requires tool_call_id and tool_name',
    );
  }
  return FrbChatToolCallStartEvent(
    round: round,
    metadata: metadata,
    id: id,
    name: name,
  );
}

FrbChatStreamEvent _parseToolCallDelta(
  Map<String, Object?> raw, {
  required int round,
  required Map<String, Object?> metadata,
}) {
  final id = frbString(raw['tool_call_id']);
  if (id.isEmpty) {
    return FrbInvalidChatEvent(
      kind: 'tool_call_delta',
      round: round,
      metadata: metadata,
      message: 'FRB LLM tool_call_delta event requires tool_call_id',
    );
  }
  return FrbChatToolCallDeltaEvent(
    round: round,
    metadata: metadata,
    id: id,
    partialInputJson: frbString(raw['partial_input_json']),
  );
}

FrbChatStreamEvent _parseToolCallEnd(
  Map<String, Object?> raw, {
  required int round,
  required Map<String, Object?> metadata,
}) {
  final id = frbString(raw['tool_call_id']);
  final name = frbString(raw['tool_name']);
  if (id.isEmpty || name.isEmpty) {
    return FrbInvalidChatEvent(
      kind: 'tool_call_end',
      round: round,
      metadata: metadata,
      message:
          'FRB LLM tool_call_end event requires tool_call_id and tool_name',
    );
  }
  return FrbChatToolCallEndEvent(
    round: round,
    metadata: metadata,
    id: id,
    name: name,
    input: frbToolInput(raw['tool_input']),
  );
}

FrbChatStreamEvent _parseRoundFinished(
  Map<String, Object?> raw, {
  required String kind,
  required int round,
  required Map<String, Object?> metadata,
}) {
  final rawResponse = raw['response'];
  final response = frbObjectOrNull(rawResponse);
  final isInteractionPause =
      frbString(metadata['status']) == 'requires_interaction';
  // The native host intentionally emits no provider response when it resumes
  // a pending human interaction: no LLM request was made for that boundary.
  // Keep accepting that one typed shape, while still rejecting scalar or
  // otherwise malformed responses from every other finished event.
  if (response == null && !(isInteractionPause && rawResponse == null)) {
    return FrbInvalidChatEvent(
      kind: kind,
      round: round,
      metadata: metadata,
      message: 'FRB LLM $kind event response is not an object',
    );
  }
  return FrbChatRoundFinishedEvent(
    kind: kind,
    round: round,
    metadata: metadata,
    response: response ?? const <String, Object?>{},
  );
}
