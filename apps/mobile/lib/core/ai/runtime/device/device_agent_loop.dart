/// Provider-neutral device LLM/tool loop.
///
/// Dart port of the historical backend agent loop
/// (`run_inner` + `collect_model_round`). Consumes the
/// [LlmStreamEvent] stream per round and emits the existing
/// [AiChatEvent] taxonomy so `ChatRepository` / the chat UI / the trace
/// builder stay byte-for-byte unchanged versus the historical runtime.
///
/// Differences from the backend, all intentional:
/// * tool data comes from a [DeviceToolDispatcher] over Drift,
///   not D1 — so there is no freshness gate on this path (§4.6.1).
/// * the turn-timeout race uses a Dart [Timer] instead of
///   `gloo_timers::select`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../contracts/chat_events.dart';
import '../../contracts/contracts.dart'
    show AiSpanKind, AiSpanStatus, SpanTokens, kTurnSpanId;
import '../../contracts/tool_schema.dart';
import '../../progress/long_task_progress.dart';
import 'anthropic/anthropic_wire.dart';
import 'device_session.dart';
import 'device_system_prompt.dart';
import 'device_tool_dispatcher.dart';
import 'llm_stream_event.dart';
import 'tools/ask_user_tool.dart' show kAskUserToolName;

/// One streaming round, injectable so tests can script
/// [LlmStreamEvent]s without a network. Production passes
/// `AnthropicClient.streamMessages`.
typedef LlmStreamFn =
    Stream<LlmStreamEvent> Function(
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
  final List<DeviceToolSchema> toolSchemas;
  final TurnBudget budget;

  /// Drive one user turn to completion. The returned stream is finite —
  /// it always ends with exactly one terminal [DoneEvent] (mirroring
  /// the backend `Stop`), possibly preceded by an [ErrorEvent].
  Stream<AiChatEvent> run(DeviceSession session, {CancelToken? cancelToken}) {
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
      if (aborted() || (cancelToken?.isCancelled ?? false)) return;
      session.roundsUsed = round + 1;
      final roundId = 'r${round + 1}';
      final roundStart = DateTime.now().toUtc();

      // Per-round child token. `AnthropicClient.streamMessages` cancels
      // whatever token it's given when *its* SSE listener goes away —
      // which happens on every normal round end. Handing it the shared
      // turn token therefore poisons the *next* round (round-2 then
      // fails with `DioException [request cancelled]`). Isolate that
      // side-effect to a disposable per-round token; propagate genuine
      // turn-level cancellation (user / listener / timeout) downward.
      final roundToken = CancelToken();
      final turnToken = cancelToken;
      if (turnToken != null) {
        unawaited(
          turnToken.whenCancel.then((err) {
            if (!roundToken.isCancelled) roundToken.cancel(err);
          }),
        );
      }

      final request = AnthropicRequest(
        model: model,
        maxTokens: kAnthropicMaxOutputTokens,
        system: system,
        messages: session.messages,
        tools: toolSchemas,
        stream: true,
      );

      // Emit the LLM-round span on every exit path so the waterfall
      // captures latency / tokens / stop reason even for the failing
      // round. Observability-only — message state is unaffected.
      void emitLlmSpan(
        _ModelRound mr, {
        required AiSpanStatus status,
        String? errCode,
        String? errMsg,
      }) {
        emit(
          SpanEvent(
            id: roundId,
            parentId: kTurnSpanId,
            kind: AiSpanKind.llm,
            name: 'llm:round-${round + 1}',
            startedAt: roundStart,
            endedAt: DateTime.now().toUtc(),
            status: status,
            errorCode: errCode,
            errorMessage: errMsg,
            tokens: mr.tokens,
            model: model,
            stopReason: mr.stopReason.wire,
            input: <String, Object?>{'messages': session.messages.length},
            output: mr.text.isEmpty ? null : _clip(mr.text),
            attributes: <String, Object?>{'round': round + 1},
          ),
        );
      }

      final _ModelRound mr;
      try {
        mr = await _collectModelRound(
          _streamFn(request, cancelToken: roundToken),
          emit,
          aborted,
        );
      } catch (e) {
        if (aborted()) return;
        emitLlmSpan(
          const _ModelRound(
            assistantContent: [],
            toolUses: [],
            stopReason: LlmStopReason.endTurn,
          ),
          status: AiSpanStatus.error,
          errCode: 'provider_error',
          errMsg: '$e',
        );
        emit(ErrorEvent('$e', code: 'provider_error'));
        emit(DoneEvent(stopReason: 'error', rounds: session.roundsUsed));
        return;
      }
      if (aborted()) return;

      if (mr.error != null) {
        emitLlmSpan(
          mr,
          status: AiSpanStatus.error,
          errCode: mr.error!.code,
          errMsg: mr.error!.message,
        );
        emit(ErrorEvent(mr.error!.message, code: mr.error!.code));
        emit(DoneEvent(stopReason: 'error', rounds: session.roundsUsed));
        return;
      }
      emitLlmSpan(mr, status: AiSpanStatus.ok);
      lastStop = mr.stopReason;

      if (mr.toolUses.isEmpty) break;

      final proposalsBefore = _countExistingProposals(session.messages);
      session.messages.add(
        AnthropicChatMessage(role: 'assistant', content: mr.assistantContent),
      );

      final toolResults = <Map<String, Object?>>[];
      var proposalsThisTurn = 0;
      // `ask_user` is a terminal tool: the model is handing a structured
      // decision to the user, so once it fires we record the result and
      // pause the loop instead of re-invoking the model (which would let
      // it answer its own question). The user's pick arrives as the next
      // turn. See `ask_user_tool.dart`.
      var awaitingUser = false;
      for (final tu in mr.toolUses) {
        if (aborted()) return;
        final isPropose = tu.name.startsWith('propose_');
        final toolStart = DateTime.now().toUtc();
        emit(
          ProgressEvent(
            LongTaskProgress(
              id: 'tool:${tu.id}',
              label: 'tool',
              detail: tu.name,
              startedAt: toolStart,
            ),
          ),
        );
        final Object? output;
        if (isPropose &&
            proposalsBefore + proposalsThisTurn >=
                kMaxProposalsPerConversation) {
          output = _proposalCapExceeded();
        } else {
          if (isPropose) proposalsThisTurn++;
          output = await dispatcher.dispatch(session, tu.name, tu.input);
        }
        emit(
          SpanEvent(
            id: 'tool:${tu.id}',
            parentId: roundId,
            kind: AiSpanKind.tool,
            name: 'tool:${tu.name}',
            startedAt: toolStart,
            endedAt: DateTime.now().toUtc(),
            status: _toolOutputIsError(output)
                ? AiSpanStatus.error
                : AiSpanStatus.ok,
            errorCode: _toolErrorCode(output),
            input: tu.input,
            output: output,
            attributes: <String, Object?>{
              'round': round + 1,
              'tool_use_id': tu.id,
            },
          ),
        );
        emit(ToolResultEvent(id: tu.id, name: tu.name, output: output));
        toolResults.add(
          AnthropicBlocks.toolResult(
            toolUseId: tu.id,
            content: jsonEncode(output),
          ),
        );
        if (tu.name == kAskUserToolName && !_toolOutputIsError(output)) {
          awaitingUser = true;
        }
      }

      session.messages.add(
        AnthropicChatMessage(role: 'user', content: toolResults),
      );

      if (awaitingUser) {
        // Pause: end the turn on a clean stop so the round-budget guard
        // below doesn't fire. The decision card now awaits the user.
        lastStop = LlmStopReason.endTurn;
        break;
      }
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
    // Full assistant text for the round span's output digest — kept
    // separate from `textBuf` (which `flushText` clears per block).
    final fullText = StringBuffer();
    // Streamed reasoning + its opaque signature for the current
    // `thinking` block. Dropping these from the assistant turn makes
    // every subsequent tool round fail on providers that emit reasoning
    // (native Anthropic extended thinking, MiMo thinking mode, …), so
    // they are reconstructed into the content the loop re-sends.
    final thinkingBuf = StringBuffer();
    final thinkingSig = StringBuffer();
    final toolNames = <String, String>{};
    final assistantContent = <Map<String, Object?>>[];
    final toolUses = <_ToolUse>[];
    var stopReason = LlmStopReason.endTurn;
    SpanTokens? tokens;

    // A `thinking` block must precede the text / tool_use blocks it
    // reasoned about, so flush it ahead of any of them. Driven through
    // `flushText`, which already runs at every block boundary (tool
    // start + final), this also keeps interleaved-thinking order
    // (think → tool → think → tool) intact.
    void flushThinking() {
      if (thinkingBuf.isEmpty) return;
      assistantContent.add(
        AnthropicBlocks.thinking(
          thinking: thinkingBuf.toString(),
          signature: thinkingSig.isEmpty ? null : thinkingSig.toString(),
        ),
      );
      thinkingBuf.clear();
      thinkingSig.clear();
    }

    void flushText() {
      flushThinking();
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
          fullText.write(text);
          emit(TextEvent(text));
        case LlmThinkingDelta(:final text):
          thinkingBuf.write(text);
          emit(ThinkingDeltaEvent(text));
        case LlmThinkingSignatureDelta(:final signature):
          // Not surfaced to the UI — accumulated only so the assistant
          // turn can be replayed verbatim on the next tool round.
          thinkingSig.write(signature);
        case LlmToolCallStart(:final id, :final name):
          flushText();
          toolNames[id] = name;
          emit(ToolCallStartEvent(id: id, name: name));
        case LlmToolCallDelta(:final id, :final partialInputJson):
          emit(ToolCallDeltaEvent(id: id, partialInputJson: partialInputJson));
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
          tokens = SpanTokens(
            input: inputTokens,
            output: outputTokens,
            cacheRead: cacheReadTokens,
            cacheWrite: cacheWriteTokens,
          );
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
            tokens: tokens,
            text: fullText.toString(),
            error: (code: code, message: message),
          );
      }
    }

    flushText();
    return _ModelRound(
      assistantContent: assistantContent,
      toolUses: toolUses,
      stopReason: stopReason,
      tokens: tokens,
      text: fullText.toString(),
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
    this.tokens,
    this.text = '',
    this.error,
  });
  final List<Map<String, Object?>> assistantContent;
  final List<_ToolUse> toolUses;
  final LlmStopReason stopReason;
  final SpanTokens? tokens;
  final String text;
  final ({String code, String message})? error;
}

/// Clip a digest string so a verbose-capture blob stays bounded even
/// for very long model turns. Metadata-only capture drops it entirely
/// in the trace builder; this only caps the verbose path.
String _clip(String s, [int max = 4000]) =>
    s.length <= max ? s : '${s.substring(0, max)}…(+${s.length - max})';

/// Mirror of `ChatRepository._isToolError`: device tools surface
/// failures as `{ "error": "...", "code": "..." }`.
bool _toolOutputIsError(Object? output) =>
    output is Map && output['error'] is String;

String? _toolErrorCode(Object? output) =>
    output is Map && output['code'] is String ? output['code'] as String : null;

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
