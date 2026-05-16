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
    DeviceChatRunner? device,
  }) : _cloud = cloud,
       _device = device;

  final AiChatApiClient _cloud;
  final DeviceChatRunner? _device;

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
    if (device == null) {
      return _cloud.chat(
        session: session,
        messages: messages,
        portfolioSnapshot: portfolioSnapshot,
        contextPack: contextPack,
        model: model,
        cancelToken: cancelToken,
      );
    }
    return _deviceThenCloud(
      device,
      session: session,
      messages: messages,
      portfolioSnapshot: portfolioSnapshot,
      contextPack: contextPack,
      model: model,
      cancelToken: cancelToken,
    );
  }

  /// §4.6.4 — try the device runtime; if it fails to produce *any*
  /// assistant content (bad key / offline / empty answer — surfaced by
  /// the loop as `Error`+`Done`, or a thrown stream error before the
  /// first content event), transparently retry the turn on the cloud
  /// relay. Once content has streamed we commit to the device result
  /// (a mid-turn failure propagates as-is; restarting would double the
  /// visible answer).
  Stream<AiChatEvent> _deviceThenCloud(
    DeviceChatRunner device, {
    required AuthSession session,
    required List<WireMessage> messages,
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    String? model,
    CancelToken? cancelToken,
  }) async* {
    final buffered = <AiChatEvent>[];
    var committed = false;
    try {
      await for (final e in device.run(
        messages: messages,
        portfolioSnapshot: portfolioSnapshot,
        contextPack: contextPack,
        model: model,
        cancelToken: cancelToken,
      )) {
        if (committed) {
          yield e;
        } else if (_isContent(e)) {
          committed = true;
          for (final b in buffered) {
            yield b;
          }
          buffered.clear();
          yield e;
        } else {
          // Error / Done — hold until we know whether the turn produced
          // anything.
          buffered.add(e);
        }
      }
    } catch (_) {
      if (committed) rethrow;
      // pre-content stream error → fall through to the cloud relay
    }
    if (committed) return;
    yield* _cloud.chat(
      session: session,
      messages: messages,
      portfolioSnapshot: portfolioSnapshot,
      contextPack: contextPack,
      model: model,
      cancelToken: cancelToken,
    );
  }
}

/// An assistant-content event — its arrival means the device turn is
/// underway, so we stop considering a cloud failover. `Error` / `Done`
/// alone (with no content) means the device call failed.
bool _isContent(AiChatEvent e) =>
    e is TextEvent ||
    e is ThinkingDeltaEvent ||
    e is ToolCallStartEvent ||
    e is ToolCallDeltaEvent ||
    e is ToolCallEvent ||
    e is ToolResultEvent ||
    e is UsageEvent;
