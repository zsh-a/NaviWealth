part of 'frb_chat_runner.dart';

sealed class _FrbRoundProjection {
  const _FrbRoundProjection();
}

final class _FrbRoundStopped extends _FrbRoundProjection {
  const _FrbRoundStopped();
}

final class _FrbRoundReady extends _FrbRoundProjection {
  const _FrbRoundReady({
    required this.state,
    required this.round,
    required this.status,
  });
  final FrbStreamRoundState state;
  final int round;
  final String status;
}

/// Projects one native stream to UI/trace events without dispatching tools or
/// mutating Rust continuation state.
final class _FrbChatEventProjector {
  _FrbChatEventProjector({
    required this.initialRound,
    required this.roundStart,
    required this.model,
    required this.cancelToken,
    required this.tools,
    required int inputMessageCount,
    required String traceInput,
  }) : roundsUsed = initialRound,
       state = FrbStreamRoundState(
         inputMessageCount: inputMessageCount,
         traceInput: traceInput,
       );
  final int initialRound;
  final DateTime roundStart;
  final String? model;
  final CancelToken? cancelToken;
  final List<Map<String, Object?>> tools;
  final FrbStreamRoundState state;
  int roundsUsed;
  String get roundId => 'r$initialRound';
  _FrbRoundProjection result = const _FrbRoundStopped();

  Stream<AiChatEvent> project(Stream<Map<String, Object?>> source) async* {
    var finished = false;
    var doneReceived = false;
    await for (final rawEvent in source) {
      final event = FrbChatStreamEvent.parse(rawEvent);
      final eventRound = event.round;
      if (eventRound > 0) roundsUsed = eventRound;
      if (cancelToken?.isCancelled == true) {
        yield frbLlmSpan(
          round: roundsUsed == 0 ? initialRound : roundsUsed,
          roundId: roundId,
          startedAt: roundStart,
          state: state,
          requestedModel: model,
          status: AiSpanStatus.cancelled,
          errorCode: _cancellationCode(cancelToken),
          errorMessage: 'FRB chat stream cancelled',
        );
        yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
        return;
      }
      switch (event) {
        case FrbChatCancelledEvent():
          yield frbLlmSpan(
            round: roundsUsed == 0 ? initialRound : roundsUsed,
            roundId: roundId,
            startedAt: roundStart,
            state: state,
            requestedModel: model,
            status: AiSpanStatus.cancelled,
            errorCode: _cancellationCode(cancelToken),
            errorMessage: 'FRB chat stream cancelled',
          );
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        case FrbChatStartedEvent():
        case FrbChatLlmStartedEvent():
          break;
        case FrbChatUsageEvent(:final usage):
          state.recordUsage(usage);
          yield UsageEvent(usage);
        case FrbChatDoneEvent(:final metadata):
          doneReceived = true;
          state.finishDone(metadata);
          break;
        case FrbChatDeltaEvent(:final content):
          if (content.isNotEmpty) {
            state.appendText(content);
            yield TextEvent(content);
          }
        case FrbChatThinkingDeltaEvent(:final content):
          if (content.isNotEmpty) {
            state.appendThinking(content);
            yield ThinkingDeltaEvent(content);
          }
        case FrbChatThinkingSignatureDeltaEvent(:final content):
          state.appendThinkingSignature(content);
        case FrbChatToolCallStartEvent(:final id, :final name):
          state.startToolCall(id: id, name: name);
          yield ToolCallStartEvent(id: id, name: name);
        case FrbChatToolCallDeltaEvent(:final id, :final partialInputJson):
          state.appendToolInput(id: id, partialInputJson: partialInputJson);
          yield ToolCallDeltaEvent(id: id, partialInputJson: partialInputJson);
        case FrbChatToolCallEndEvent(:final id, :final name, :final input):
          state.finishToolCall(id: id, name: name, input: input);
          yield ToolCallEvent(id: id, name: name, input: input);
        case FrbChatRoundFinishedEvent(:final response, :final metadata):
          final hasEmittedUsage = state.usage != null;
          state.finish(response, metadata: metadata);
          final usage = frbUsageFromResponse(response);
          if (!hasEmittedUsage && usage != null) yield UsageEvent(usage);
          final text = frbString(response['content']);
          if (!state.emittedText && text.isNotEmpty) {
            state.appendText(text);
            yield TextEvent(text);
          }
          finished = true;
        case FrbChatErrorEvent(:final code, :final message):
          yield frbLlmSpan(
            round: roundsUsed == 0 ? initialRound : roundsUsed,
            roundId: roundId,
            startedAt: roundStart,
            state: state,
            requestedModel: model,
            status: AiSpanStatus.error,
            errorCode: code,
            errorMessage: message,
          );
          yield ErrorEvent(message, code: code);
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        case FrbInvalidChatEvent(:final message):
          yield frbInvalidStreamEventSpan(
            round: roundsUsed == 0 ? initialRound : roundsUsed,
            roundId: roundId,
            startedAt: roundStart,
            state: state,
            requestedModel: model,
            message: message,
          );
          yield ErrorEvent(message, code: 'frb_chat_event_invalid');
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
        case FrbUnknownChatEvent(:final message):
          yield frbLlmSpan(
            round: roundsUsed == 0 ? initialRound : roundsUsed,
            roundId: roundId,
            startedAt: roundStart,
            state: state,
            requestedModel: model,
            status: AiSpanStatus.error,
            errorCode: 'frb_chat_event_unknown',
            errorMessage: message,
          );
          yield ErrorEvent(message, code: 'frb_chat_event_unknown');
          yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
          return;
      }
    }

    if (!finished) {
      yield frbLlmSpan(
        round: roundsUsed == 0 ? initialRound : roundsUsed,
        roundId: roundId,
        startedAt: roundStart,
        state: state,
        requestedModel: model,
        status: AiSpanStatus.error,
        errorCode: 'frb_chat_stream_incomplete',
        errorMessage: 'FRB LLM stream ended without a finished event',
      );
      yield const ErrorEvent(
        'FRB LLM stream ended without a finished event',
        code: 'frb_chat_stream_incomplete',
      );
      yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
      return;
    }

    final roundStatus = _effectiveRoundStatus(state);
    if (roundStatus != 'requires_tool_results' && !doneReceived) {
      yield frbLlmSpan(
        round: roundsUsed == 0 ? initialRound : roundsUsed,
        roundId: roundId,
        startedAt: roundStart,
        state: state,
        requestedModel: model,
        status: AiSpanStatus.error,
        errorCode: _kTerminalDoneMissingErrorCode,
        errorMessage:
            'FRB LLM stream ended after round_finished without terminal done',
      );
      yield const ErrorEvent(
        'FRB LLM stream ended after round_finished without terminal done',
        code: _kTerminalDoneMissingErrorCode,
      );
      yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
      return;
    }
    if (roundStatus == 'requires_tool_results' && doneReceived) {
      yield frbLlmSpan(
        round: roundsUsed == 0 ? initialRound : roundsUsed,
        roundId: roundId,
        startedAt: roundStart,
        state: state,
        requestedModel: model,
        status: AiSpanStatus.error,
        errorCode: 'frb_chat_tool_round_terminal',
        errorMessage:
            'FRB LLM tool round emitted terminal done before tool results',
      );
      yield const ErrorEvent(
        'FRB LLM tool round emitted terminal done before tool results',
        code: 'frb_chat_tool_round_terminal',
      );
      yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
      return;
    }
    if (roundStatus == 'requires_tool_results') {
      final validation = _validateToolCalls(
        state.requiredToolCalls,
        _toolNames(tools),
      );
      if (validation case final failure?) {
        yield frbLlmSpan(
          round: roundsUsed == 0 ? initialRound : roundsUsed,
          roundId: roundId,
          startedAt: roundStart,
          state: state,
          requestedModel: model,
          status: AiSpanStatus.error,
          errorCode: failure.code,
          errorMessage: failure.message,
        );
        yield ErrorEvent(failure.message, code: failure.code);
        yield DoneEvent(stopReason: 'error', rounds: roundsUsed);
        return;
      }
    }

    yield frbLlmSpan(
      round: roundsUsed == 0 ? initialRound : roundsUsed,
      roundId: roundId,
      startedAt: roundStart,
      state: state,
      requestedModel: model,
      status: AiSpanStatus.ok,
    );

    result = _FrbRoundReady(
      state: state,
      round: roundsUsed,
      status: roundStatus,
    );
  }
}
