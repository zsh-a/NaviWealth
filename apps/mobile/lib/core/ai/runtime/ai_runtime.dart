/// AiRuntime abstraction (Wave 22).
///
/// Today every chat goes to the cloud Anthropic relay. Tomorrow some
/// turns will run on a device-side LLM (Phase 5) or on a rules-only
/// runtime (deterministic skill dispatch for "how much did I spend on
/// coffee" without invoking any model at all).
///
/// The runtime axis is *independent of* the [Backend] trace label —
/// that one is for AI-trace transparency. The runtime axis decides
/// **which executor receives the chat request**. Two runtimes with
/// different impls can produce the same `Backend` label.
///
/// This module deliberately stays thin: it defines the trait + a
/// [RuntimeRegistry] keyed by [RuntimeId]. The cloud runtime wraps the
/// existing [AiChatApiClient] so we get the abstraction without
/// rewriting `ChatRepository`; future Phase 5 plugs the device runtime
/// in by registering a third implementor.
library;

import 'package:dio/dio.dart';

import '../../../features/ai_chat/data/ai_chat_api_client.dart';
import '../../../features/ai_chat/domain/chat_events.dart';
import '../../auth/auth_session.dart';
import '../contracts/contracts.dart';
import '../router/routing_decision.dart';
import 'device/anthropic/anthropic_client.dart';
import 'device/anthropic/anthropic_wire.dart';
import 'device/device_agent_loop.dart';
import 'device/device_session.dart';
import 'device/device_tool_dispatcher.dart';

/// Identifier for a runtime. String-keyed so trace records and metrics
/// stay stable across renames; the registry resolves it to an
/// implementation at dispatch time.
enum RuntimeId {
  /// Anthropic Claude via the Cloudflare Worker relay.
  cloudAnthropic,

  /// Rules-only device runtime — no model, just skill dispatch + plan
  /// execution. Today returns "unsupported" for anything beyond
  /// pre-registered query plans; Phase 5 may extend it.
  rulesDevice,

  /// §4.6 Phase 5 — on-device LLM calling the user's own provider key
  /// directly (no Worker in the path). Selected by *availability*
  /// (native × key × opt-in) at the provider layer, not by the
  /// `Backend` trace label — see [RuntimeRegistry.pickFor].
  deviceLlm,
}

/// Inputs to one chat turn. Shaped so callers can build it once and
/// pass it to any registered runtime; the cloud runtime drops the
/// fields it doesn't care about (today: cancelToken is dio-specific).
class AiRuntimeRequest {
  const AiRuntimeRequest({
    required this.session,
    required this.messages,
    required this.decision,
    this.portfolioSnapshot,
    this.contextPack,
    this.model,
  });

  final AuthSession session;
  final List<WireMessage> messages;

  /// The routing decision that selected this runtime. Implementations
  /// can use it for capability gating (e.g. rulesDevice refuses
  /// anything not classified as `Capability.answer`).
  final RoutingDecision decision;

  final Map<String, Object?>? portfolioSnapshot;
  final ContextPack? contextPack;
  final String? model;
}

abstract class AiRuntime {
  RuntimeId get id;

  /// Whether this runtime emits events incrementally. Today both impls
  /// stream; the field is for future bulk-completion runtimes.
  bool get supportsStreaming;

  /// Run one chat turn. The stream is finite — implementations close
  /// it after emitting the terminal `done` / `error` event.
  Stream<AiChatEvent> chat(AiRuntimeRequest request);
}

/// Maps [RuntimeId] → [AiRuntime] implementations. Registered at app
/// startup; lookup is `O(1)`. Missing keys return `null` so callers
/// can fall back to a default rather than crash.
class RuntimeRegistry {
  RuntimeRegistry(Map<RuntimeId, AiRuntime> runtimes)
    : _runtimes = Map<RuntimeId, AiRuntime>.unmodifiable(runtimes);

  final Map<RuntimeId, AiRuntime> _runtimes;

  AiRuntime? lookup(RuntimeId id) => _runtimes[id];

  /// Pick a runtime from a [RoutingDecision]. Phase 1 maps the
  /// `Backend` label one-to-one (device → rulesDevice, cloud → cloudAnthropic,
  /// hybrid → cloudAnthropic). Phase 5 may insert a real device-LLM
  /// runtime here without changing call sites.
  AiRuntime? pickFor(RoutingDecision decision) {
    final id = switch (decision.backend) {
      Backend.device => RuntimeId.rulesDevice,
      Backend.cloud => RuntimeId.cloudAnthropic,
      Backend.hybrid => RuntimeId.cloudAnthropic,
    };
    return lookup(id);
  }

  Iterable<RuntimeId> registered() => _runtimes.keys;
}

/// Wraps the existing [AiChatApiClient] (Dio + SSE parsing) so the
/// rest of the system can talk to "an AiRuntime" rather than a
/// concrete HTTP client.
class CloudAnthropicRuntime implements AiRuntime {
  const CloudAnthropicRuntime({required this.apiClient});

  final AiChatApiClient apiClient;

  @override
  RuntimeId get id => RuntimeId.cloudAnthropic;

  @override
  bool get supportsStreaming => true;

  @override
  Stream<AiChatEvent> chat(AiRuntimeRequest request) => apiClient.chat(
    session: request.session,
    messages: request.messages,
    portfolioSnapshot: request.portfolioSnapshot,
    contextPack: request.contextPack,
    model: request.model,
  );
}

/// Stub for the device-side runtime. Today the device router only
/// classifies and quick-answers; full chat turns still go to the
/// cloud. This stub returns a single error event so the trace
/// records "no device runtime" rather than crashing the call site.
class RulesDeviceRuntime implements AiRuntime {
  const RulesDeviceRuntime();

  @override
  RuntimeId get id => RuntimeId.rulesDevice;

  @override
  bool get supportsStreaming => true;

  @override
  Stream<AiChatEvent> chat(AiRuntimeRequest request) async* {
    yield const ErrorEvent(
      'rules_device runtime cannot answer this turn; route via cloud '
      'or extend the runtime',
    );
  }
}

/// §4.6 Phase 5 — on-device LLM runtime.
///
/// Owns the full agent loop client-side: builds a [DeviceSession] from
/// the inbound turn, runs [DeviceAgentLoop] over an [AnthropicClient]
/// that talks straight to the user's provider with their key (W-D1/2),
/// and emits the same [AiChatEvent] stream as [CloudAnthropicRuntime].
/// Tools are stubbed via [UnavailableToolDispatcher] until W-D4 wires
/// the Drift-backed registry, so text-only turns work end to end now.
class DeviceLlmRuntime implements AiRuntime {
  DeviceLlmRuntime({
    required this.client,
    this.dispatcher = const UnavailableToolDispatcher(),
    this.toolSchemas = const [],
    this.budget = const TurnBudget(),
  });

  final AnthropicClient client;
  final DeviceToolDispatcher dispatcher;
  final List<AnthropicToolSchema> toolSchemas;
  final TurnBudget budget;

  @override
  RuntimeId get id => RuntimeId.deviceLlm;

  @override
  bool get supportsStreaming => true;

  @override
  Stream<AiChatEvent> chat(AiRuntimeRequest request) => run(
    messages: request.messages,
    portfolioSnapshot: request.portfolioSnapshot,
    model: request.model,
  );

  /// [AiChatApiClient.chat]-shaped entry point so the routing client
  /// can forward without synthesising a [RoutingDecision] (the device
  /// loop ignores routing — selection already happened upstream).
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
