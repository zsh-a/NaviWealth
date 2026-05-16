/// Provider-neutral device LLM/tool loop (§4.6 W-D3).
///
/// Dart port of `apps/backend/src/ai/runtime/agent_loop.rs`
/// (`run_inner` + `collect_model_round`). Consumes the W-D2
/// [LlmStreamEvent] stream per round and emits the existing
/// [AiChatEvent] taxonomy so `ChatRepository` / the chat UI / the trace
/// builder stay byte-for-byte unchanged versus the cloud path.
///
/// Differences from the backend, all intentional:
/// * tool data comes from a [DeviceToolDispatcher] over Drift (W-D4),
///   not D1 — so there is no freshness gate on this path (§4.6.1).
/// * the turn-timeout race uses a Dart [Timer] instead of
///   `gloo_timers::select`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../../features/ai_chat/domain/chat_events.dart';
import 'anthropic/anthropic_wire.dart';
import 'device_session.dart';
import 'device_system_prompt.dart';
import 'device_tool_dispatcher.dart';
import 'llm_stream_event.dart';

/// One streaming round, injectable so tests can script
/// [LlmStreamEvent]s without a network. Production passes
/// `AnthropicClient.streamMessages`.
typedef LlmStreamFn = Stream<LlmStreamEvent> Function(
  AnthropicRequest request, {
  CancelToken? cancelToken,
});

class TurnBudget {
  const TurnBudget({
    this.maxRounds = kMaxToolRounds,
    this.turnTimeout = const Duration(seconds: 60),
  });

  final int maxRounds;
  final Duration turnTimeout;
}

class DeviceAgentLoop {
  DeviceAgentLoop({
    required LlmStreamFn streamFn,
    required this.model,
    required this.dispatcher,
    this.toolSchemas = const [],
    this.budget = const TurnBudget(),
  }) : _streamFn = streamFn;

  final LlmStreamFn _streamFn;
  final String model;
  final DeviceToolDispatcher dispatcher;
  final List<AnthropicToolSchema> toolSchemas;
  final TurnBudget budget;

  /// Drive one user turn to completion. The returned stream is finite —
  /// it always ends with exactly one terminal [DoneEvent] (mirroring
  /// the backend `Stop`), possibly preceded by an [ErrorEvent].
  Stream<AiChatEvent> run(
    DeviceSession session, {
    CancelToken? cancelToken,
  }) {
    final controller = StreamController<AiChatEvent>();
    var aborted = false;
    Timer? timer;

    void emit(AiChatEvent e) {
      if (!aborted && !controller.isClosed) controller.add(e);
    }

    Future<void> finishTimeout() async {
      if (aborted || controller.isClosed) return;
      aborted = true;
      controller.add(
        const ErrorEvent('chat turn timed out', code: 'chat_timeout'),
      );
      controller.add(
        DoneEvent(stopReason: 'error', rounds: session.roundsUsed),
      );
      await controller.close();
    }

    Future<void> runner() async {
      if (budget.turnTimeout == Duration.zero) {
        await finishTimeout();
        return;
      }
      timer = Timer(budget.turnTimeout, finishTimeout);
      try {
        await _runInner(session, emit, () => aborted, cancelToken);
      } finally {
        timer?.cancel();
        if (!aborted && !controller.isClosed) await controller.close();
      }
    }

    controller.onCancel = () async {
      aborted = true;
      timer?.cancel();
      if (cancelToken != null && !cancelToken.isCancelled) {
        cancelToken.cancel('listener cancelled');
      }
    };

    unawaited(runner());
    return controller.stream;
  }

  Future<void> _runInner(
    DeviceSession session,
    void Function(AiChatEvent) emit,
    bool Function() aborted,
    CancelToken? cancelToken,
  ) async {
    final system = session.systemPrompt();
    var lastStop = LlmStopReason.endTurn;

    for (var round = 0; round < budget.maxRounds; round++) {
      if (aborted()) return;
      session.roundsUsed = round + 1;

      final request = AnthropicRequest(
        model: model,
        maxTokens: kAnthropicMaxOutputTokens,
        system: system,
        messages: session.messages,
        tools: toolSchemas,
        stream: true,
      );

      final _ModelRound mr;
      try {
        mr = await _collectModelRound(
          _streamFn(request, cancelToken: cancelToken),
          emit,
          aborted,
        );
      } catch (e) {
        if (aborted()) return;
        emit(ErrorEvent('$e', code: 'provider_error'));
        emit(DoneEvent(stopReason: 'error', rounds: session.roundsUsed));
        return;
      }
      if (aborted()) return;

      if (mr.error != null) {
        emit(ErrorEvent(mr.error!.message, code: mr.error!.code));
        emit(DoneEvent(stopReason: 'error', rounds: session.roundsUsed));
        return;
      }
      lastStop = mr.stopReason;

      if (mr.toolUses.isEmpty) break;

      final proposalsBefore = _countExistingProposals(session.messages);
      session.messages.add(
        AnthropicChatMessage(role: 'assistant', content: mr.assistantContent),
      );

      final toolResults = <Map<String, Object?>>[];
      var proposalsThisTurn = 0;
      for (final tu in mr.toolUses) {
        if (aborted()) return;
        final isPropose = tu.name.startsWith('propose_');
        final Object? output;
        if (isPropose &&
            proposalsBefore + proposalsThisTurn >=
                kMaxProposalsPerConversation) {
          output = _proposalCapExceeded();
        } else {
          if (isPropose) proposalsThisTurn++;
          output = await dispatcher.dispatch(session, tu.name, tu.input);
        }
        emit(ToolResultEvent(id: tu.id, name: tu.name, output: output));
        toolResults.add(
          AnthropicBlocks.toolResult(
            toolUseId: tu.id,
            content: jsonEncode(output),
          ),
        );
      }

      session.messages.add(
        AnthropicChatMessage(role: 'user', content: toolResults),
      );
    }

    if (session.roundsUsed >= budget.maxRounds &&
        lastStop == LlmStopReason.toolUse) {
      emit(
        const ErrorEvent(
          'tool round budget exhausted',
          code: 'tool_round_budget_exhausted',
        ),
      );
    }
    emit(DoneEvent(stopReason: lastStop.wire, rounds: session.roundsUsed));
  }

  /// Mirror of `collect_model_round`: streams text/tool deltas straight
  /// through while assembling the assistant content blocks + the
  /// tool-use list for this round.
  Future<_ModelRound> _collectModelRound(
    Stream<LlmStreamEvent> stream,
    void Function(AiChatEvent) emit,
    bool Function() aborted,
  ) async {
    final textBuf = StringBuffer();
    final toolNames = <String, String>{};
    final assistantContent = <Map<String, Object?>>[];
    final toolUses = <_ToolUse>[];
    var stopReason = LlmStopReason.endTurn;

    void flushText() {
      if (textBuf.isNotEmpty) {
        assistantContent.add(AnthropicBlocks.text(textBuf.toString()));
        textBuf.clear();
      }
    }

    await for (final event in stream) {
      if (aborted()) break;
      switch (event) {
        case LlmTextDelta(:final text):
          textBuf.write(text);
          emit(TextEvent(text));
        case LlmThinkingDelta(:final text):
          emit(ThinkingDeltaEvent(text));
        case LlmToolCallStart(:final id, :final name):
          flushText();
          toolNames[id] = name;
          emit(ToolCallStartEvent(id: id, name: name));
        case LlmToolCallDelta(:final id, :final partialInputJson):
          emit(
            ToolCallDeltaEvent(id: id, partialInputJson: partialInputJson),
          );
        case LlmToolCallEnd(:final id, :final name, :final input):
          final resolved = name.isNotEmpty ? name : (toolNames[id] ?? '');
          assistantContent.add(<String, Object?>{
            'type': 'tool_use',
            'id': id,
            'name': resolved,
            'input': input,
          });
          toolUses.add(_ToolUse(id: id, name: resolved, input: input));
          emit(ToolCallEvent(id: id, name: resolved, input: input));
        case LlmUsage(
            :final inputTokens,
            :final outputTokens,
            :final cacheReadTokens,
            :final cacheWriteTokens,
          ):
          emit(
            UsageEvent(
              TokenUsage(
                input: inputTokens,
                output: outputTokens,
                cacheRead: cacheReadTokens,
                cacheWrite: cacheWriteTokens,
              ),
            ),
          );
        case LlmMessageStop(:final reason):
          stopReason = reason;
        case LlmStreamErrorEvent(:final code, :final message):
          return _ModelRound(
            assistantContent: assistantContent,
            toolUses: toolUses,
            stopReason: stopReason,
            error: (code: code, message: message),
          );
      }
    }

    flushText();
    return _ModelRound(
      assistantContent: assistantContent,
      toolUses: toolUses,
      stopReason: stopReason,
    );
  }
}

class _ToolUse {
  const _ToolUse({required this.id, required this.name, required this.input});
  final String id;
  final String name;
  final Object? input;
}

class _ModelRound {
  const _ModelRound({
    required this.assistantContent,
    required this.toolUses,
    required this.stopReason,
    this.error,
  });
  final List<Map<String, Object?>> assistantContent;
  final List<_ToolUse> toolUses;
  final LlmStopReason stopReason;
  final ({String code, String message})? error;
}

/// Port of `guardrails::count_existing_proposals`.
int _countExistingProposals(List<AnthropicChatMessage> messages) {
  var n = 0;
  for (final m in messages) {
    final content = m.content;
    if (content is! List) continue;
    for (final b in content) {
      if (b is Map &&
          b['type'] == 'tool_use' &&
          b['name'] is String &&
          (b['name'] as String).startsWith('propose_')) {
        n++;
      }
    }
  }
  return n;
}

/// Port of `agent_loop::proposal_cap_exceeded`.
Map<String, Object?> _proposalCapExceeded() => <String, Object?>{
  'error': 'proposal_cap_exceeded',
  'code': 'proposal_cap_exceeded',
  'limit': kMaxProposalsPerConversation,
  'message':
      '本次对话已达到 $kMaxProposalsPerConversation 个 propose_* 上限。'
      '请让用户先在前端确认页处理已有的提议（确认或取消），再继续录入。',
};
