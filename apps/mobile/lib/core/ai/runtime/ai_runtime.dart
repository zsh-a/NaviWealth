/// Device LLM runtime contract.
///
/// The cloud AI backend was deleted. Production interactive chat is composed
/// in `app/bootstrap.dart` through the FRB-backed `FrbChatRunner`; this
/// direct-Dart runtime remains as a legacy/tested device loop contract and as
/// the implementation behind focused runtime tests.
///
/// This file deliberately stays thin: [DeviceLlmRuntime] (legacy direct-Dart
/// runtime contract) + [DeviceChatRunner] (the seam production/tests inject
/// through).
library;

import 'package:dio/dio.dart';

import '../../../features/ai_chat/data/ai_chat_api_client.dart';
import '../contracts/contracts.dart';
import 'device/anthropic/anthropic_client.dart';
import 'device/anthropic/anthropic_wire.dart';
import 'device/device_agent_loop.dart';
import 'device/device_session.dart';
import 'device/device_system_prompt.dart';
import 'device/device_tool_dispatcher.dart';
import 'device/device_user_profile_prompt.dart';

/// The slice of the device runtime the routing client depends on.
/// An interface so tests can inject a scripted device without a
/// network-bound provider client.
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
/// that talks straight to the user's provider with their key,
/// and emits [AiChatEvent]s consumed by `ChatRepository`.
class DeviceLlmRuntime implements DeviceChatRunner {
  DeviceLlmRuntime({
    required this.client,
    this.dispatcher = const UnavailableToolDispatcher(),
    this.toolSchemas = const [],
    this.budget = const TurnBudget(),
    this.basePrompt = kDeviceSystemPromptBase,
  });

  final DeviceLlmClient client;
  final DeviceToolDispatcher dispatcher;
  final List<AnthropicToolSchema> toolSchemas;
  final TurnBudget budget;

  /// Pre-assembled prompt (base + active-domain blocks) built by
  /// `assembledSystemPromptProvider`. Default is the bare base for tests
  /// / shell-only builds.
  final String basePrompt;

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
      // MT-2.5.M1.2 — first turn injects a 1KB user-profile appendix so
      // the model grounds its answers in the user's actual finance shape
      // (risk preference / cashflow trend / FIRE progress) without having
      // to call a tool first.
      systemAppendix: renderContextPackSystemAppendix(contextPack),
      basePrompt: basePrompt,
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
