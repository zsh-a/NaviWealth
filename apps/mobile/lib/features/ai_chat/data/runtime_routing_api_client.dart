/// §4.6 W-D3 — runtime-routing [AiChatApiClient].
///
/// The seam that makes `ChatRepository` "go through the registry"
/// without rewriting it: same [AiChatApiClient] surface, but a turn is
/// dispatched to the on-device [DeviceLlmRuntime] when one was built
/// (native × user key × opt-in, decided by the provider layer per
/// §4.6.2) and otherwise to the cloud relay. Selection already happened
/// upstream, so this just forwards — no [RoutingDecision] synthesis.
///
/// Per-turn failover on an early device error (bad key / offline →
/// retry via cloud) is W-D6; here a device failure surfaces through the
/// loop's own `ErrorEvent` + `DoneEvent`.
library;

import 'package:dio/dio.dart';

import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/runtime/ai_runtime.dart';
import '../../../core/auth/auth_session.dart';
import '../domain/chat_events.dart';
import 'ai_chat_api_client.dart';

class RuntimeRoutingAiChatApiClient implements AiChatApiClient {
  const RuntimeRoutingAiChatApiClient({
    required AiChatApiClient cloud,
    DeviceLlmRuntime? device,
  }) : _cloud = cloud,
       _device = device;

  final AiChatApiClient _cloud;
  final DeviceLlmRuntime? _device;

  /// Which runtime a turn would hit — surfaced for the transparency
  /// badge / trace label (W-D6).
  bool get usesDevice => _device != null;

  @override
  Stream<AiChatEvent> chat({
    required AuthSession session,
    required List<WireMessage> messages,
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    String? model,
    CancelToken? cancelToken,
  }) {
    final device = _device;
    if (device != null) {
      return device.run(
        messages: messages,
        portfolioSnapshot: portfolioSnapshot,
        contextPack: contextPack,
        model: model,
        cancelToken: cancelToken,
      );
    }
    return _cloud.chat(
      session: session,
      messages: messages,
      portfolioSnapshot: portfolioSnapshot,
      contextPack: contextPack,
      model: model,
      cancelToken: cancelToken,
    );
  }
}
