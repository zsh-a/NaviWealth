/// FRB-backed adapter for the existing AI Chat runner seam.
///
/// The native FRB LLM API now exposes a primitive JSON event stream. This runner
/// maps those native events into the existing `AiChatEvent` vocabulary. Tool
/// calls are executed through the JSON-RPC tool host and fed back into bounded
/// follow-up LLM rounds, matching the existing device loop contract.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_stream_bridge.dart';
import 'package:naviwealth/app/agent_runtime/chat/frb_chat_event.dart';
import 'package:naviwealth/app/agent_runtime/chat/frb_chat_trace_mapper.dart';
import 'package:naviwealth/app/agent_runtime/chat/frb_chat_types.dart';
import 'package:naviwealth/app/agent_runtime/persistence/agent_runtime_chat_snapshot_store.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/progress/long_task_progress.dart';
import 'package:naviwealth/core/ai/runtime/ai_runtime.dart';
import 'package:naviwealth/core/ai/runtime/device/device_system_prompt.dart'
    show kMaxToolRounds;
import 'package:naviwealth/core/ai/runtime/device/tools/ask_user_tool.dart'
    show kAskUserToolName;

part 'frb_chat_cancellation.dart';
part 'frb_chat_event_projection.dart';
part 'frb_chat_recovery.dart';
part 'frb_chat_run.dart';
part 'frb_chat_tool_dispatch.dart';
part 'frb_chat_tool_journal.dart';

const String kFrbChatRunnerAgentId = 'ai_chat';
const String _kInteractionEnvelopeErrorCode =
    'frb_chat_interaction_envelope_invalid';
const String _kInteractionEnvelopeErrorMessage =
    'ask_user tool result must include a valid pending chat interaction envelope';
const String _kToolNotAllowedErrorCode = 'frb_chat_tool_not_allowed';
const String _kAskUserBatchErrorCode = 'frb_chat_ask_user_not_exclusive';
const String _kTerminalDoneMissingErrorCode = 'frb_chat_terminal_done_missing';
const String _kToolCancelledErrorCode = 'cancelled';
const String _kToolCancelledMessage = 'FRB chat tool dispatch cancelled';

class FrbChatRunner implements ChatAgent {
  FrbChatRunner({
    required AgentRuntimeLlmStreamBridge streamBridge,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    AgentRuntimeToolLineHandler? toolLineHandler,
    AgentRuntimeChatSnapshotStore? snapshotStore,
    int maxToolRounds = kMaxToolRounds,
    String agentId = kFrbChatRunnerAgentId,
    this.emitModelProgress = false,
  }) : _streamBridge = streamBridge,
       _toolsReader = (() => tools),
       _toolLineHandler = toolLineHandler,
       _snapshotStore = snapshotStore,
       _maxToolRounds = maxToolRounds,
       _agentId = agentId;

  const FrbChatRunner.lazyTools({
    required AgentRuntimeLlmStreamBridge streamBridge,
    required List<Map<String, Object?>> Function() toolsReader,
    AgentRuntimeToolLineHandler? toolLineHandler,
    AgentRuntimeChatSnapshotStore? snapshotStore,
    int maxToolRounds = kMaxToolRounds,
    String agentId = kFrbChatRunnerAgentId,
    this.emitModelProgress = false,
  }) : _streamBridge = streamBridge,
       _toolsReader = toolsReader,
       _toolLineHandler = toolLineHandler,
       _snapshotStore = snapshotStore,
       _maxToolRounds = maxToolRounds,
       _agentId = agentId;

  final AgentRuntimeLlmStreamBridge _streamBridge;
  final List<Map<String, Object?>> Function() _toolsReader;
  final AgentRuntimeToolLineHandler? _toolLineHandler;
  final AgentRuntimeChatSnapshotStore? _snapshotStore;
  final int _maxToolRounds;
  final String _agentId;
  final bool emitModelProgress;

  @override
  Stream<AiChatEvent> runTurn(ChatAgentTurnRequest request) {
    return _runRequest(request);
  }

  Stream<AiChatEvent> run({
    required List<ChatAgentMessage> messages,
    String? model,
    double? temperature,
    int? maxOutputTokens,
    CancelToken? cancelToken,
  }) {
    return _runRequest(
      ChatAgentTurnRequest(
        messages: messages,
        surface: 'ai_chat',
        agentId: _agentId,
        mode: 'chat',
        model: model,
        temperature: temperature,
        maxOutputTokens: maxOutputTokens,
        cancelToken: cancelToken,
      ),
    );
  }

  Stream<AiChatEvent> _runRequest(ChatAgentTurnRequest request) async* {
    final cancelToken = request.cancelToken;
    if (cancelToken?.isCancelled == true) {
      yield const DoneEvent(stopReason: 'error', rounds: 0);
      return;
    }

    try {
      yield* _FrbChatRun(
        streamBridge: _streamBridge,
        tools: _toolsReader(),
        toolLineHandler: _toolLineHandler,
        snapshotStore: _snapshotStore,
        maxToolRounds: _maxToolRounds,
        agentId: _agentId,
        emitModelProgress: emitModelProgress,
      ).run(request);
    } catch (error) {
      yield ErrorEvent(error.toString(), code: 'frb_chat_error');
      yield const DoneEvent(stopReason: 'error', rounds: 1);
    }
  }
}
