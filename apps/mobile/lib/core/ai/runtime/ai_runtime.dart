/// Device LLM runtime contract.
///
/// After W-D7 deleted the cloud AI backend, there is exactly one chat
/// runtime: [DeviceLlmRuntime], which owns the on-device agent loop and
/// calls the user's chosen LLM provider directly with the user's own
/// key. The earlier `AiRuntime` / `RuntimeRegistry` / `CloudAnthropicRuntime`
/// / `RulesDeviceRuntime` scaffolding was removed in the post-W-D7
/// boundary audit (see `docs/ai-boundary-audit.md`); selection now
/// happens upstream in [RuntimeRoutingAiChatApiClient], which either
/// dispatches to the device runtime or yields `device_unavailable`.
///
/// This file deliberately stays thin: [DeviceLlmRuntime] (production
/// runtime) + [DeviceChatRunner] (the seam tests inject through).
library;

import 'package:dio/dio.dart';

import '../../../features/ai_chat/data/ai_chat_api_client.dart';
import '../../../features/ai_chat/domain/chat_events.dart';
import '../contracts/contracts.dart';
import 'device/anthropic/anthropic_client.dart';
import 'device/anthropic/anthropic_wire.dart';
import 'device/device_agent_loop.dart';
import 'device/device_session.dart';
import 'device/device_tool_dispatcher.dart';

/// The slice of the device runtime the routing client (W-D3/W-D6
/// failover history) depends on. An interface so tests can inject a
/// scripted device without a network-bound provider client.
abstract class DeviceChatRunner {
  Stream<AiChatEvent> run({
    required List<WireMessage> messages,
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    String? model,
    CancelToken? cancelToken,
  });
}

/// §4.6 Phase 5 — on-device LLM runtime.
///
/// Owns the full agent loop client-side: builds a [DeviceSession] from
/// the inbound turn, runs [DeviceAgentLoop] over a device LLM client
/// that talks straight to the user's provider with their key (W-D1/2),
/// and emits [AiChatEvent]s consumed by `ChatRepository`.
class DeviceLlmRuntime implements DeviceChatRunner {
  DeviceLlmRuntime({
    required this.client,
    this.dispatcher = const UnavailableToolDispatcher(),
    this.toolSchemas = const [],
    this.budget = const TurnBudget(),
  });

  final DeviceLlmClient client;
  final DeviceToolDispatcher dispatcher;
  final List<AnthropicToolSchema> toolSchemas;
  final TurnBudget budget;

  @override
  Stream<AiChatEvent> run({
    required List<WireMessage> messages,
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    String? model,
    CancelToken? cancelToken,
  }) {
    final session = DeviceSession(
      messages: [
        for (final m in messages)
          AnthropicChatMessage(role: m.role, content: m.content),
      ],
      portfolioSnapshot: portfolioSnapshot,
    );
    final loop = DeviceAgentLoop(
      streamFn: client.streamMessages,
      model: (model == null || model.isEmpty) ? client.config.model : model,
      dispatcher: dispatcher,
      toolSchemas: toolSchemas,
      budget: budget,
    );
    return loop.run(session, cancelToken: cancelToken);
  }
}
