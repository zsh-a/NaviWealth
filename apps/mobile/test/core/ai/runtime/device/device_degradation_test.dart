import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/runtime/ai_runtime.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool_registry.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/features/ai_chat/data/ai_chat_api_client.dart';
import 'package:naviwealth/features/ai_chat/data/runtime_routing_api_client.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_events.dart';
import 'package:naviwealth/features/ai_chat/ui/ai_transparency_badge.dart';

AiTrace _trace({
  required Backend backend,
  String routingReason = 'capability_classify',
}) => AiTrace(
  requestId: 'r',
  startedAtIso: '2026-05-16T00:00:00Z',
  intent: const IntentHint(capability: Capability.analyze, risk: RiskLevel.info),
  backend: backend,
  budgetTier: BudgetTier.small,
  routingReason: routingReason,
  usedCloud: backend != Backend.device,
  usedRawLedger: false,
  totalDurationMs: 1200,
);

AuthSession _session() => AuthSession(
  accessToken: 't',
  expiresAt: DateTime.utc(2030),
  userId: 'u',
  deviceId: 'd',
);

class _ScriptedDevice implements DeviceChatRunner {
  _ScriptedDevice(this._events, {this.throwAfter});
  final List<AiChatEvent> _events;
  final int? throwAfter; // throw after N yielded events (null = never)

  @override
  Stream<AiChatEvent> run({
    required List<WireMessage> messages,
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    String? model,
    CancelToken? cancelToken,
  }) async* {
    var n = 0;
    for (final e in _events) {
      if (throwAfter != null && n == throwAfter) {
        throw StateError('device socket closed');
      }
      yield e;
      n++;
    }
    if (throwAfter != null && n == throwAfter) {
      throw StateError('device socket closed');
    }
  }
}

class _SpyCloud implements AiChatApiClient {
  bool called = false;
  @override
  Stream<AiChatEvent> chat({
    required AuthSession session,
    required List<WireMessage> messages,
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    String? model,
    CancelToken? cancelToken,
  }) async* {
    called = true;
    yield const TextEvent('cloud-answer');
    yield const DoneEvent(stopReason: 'end_turn', rounds: 1);
  }
}

Future<List<AiChatEvent>> _run(RuntimeRoutingAiChatApiClient c) => c
    .chat(session: _session(), messages: const [
      WireMessage(role: 'user', content: 'hi'),
    ])
    .toList();

void main() {
  group('formatAiTraceBadge — device-direct text (W-D6)', () {
    test('device + device_llm_direct → "未经我方服务器"', () {
      final s = formatAiTraceBadge(
        _trace(
          backend: Backend.device,
          routingReason: kDeviceLlmDirectRoutingReason,
        ),
      );
      expect(s, contains('端侧直连模型'));
      expect(s, contains('未经我方服务器'));
    });

    test('device without that reason stays "全部本地处理"', () {
      final s = formatAiTraceBadge(_trace(backend: Backend.device));
      expect(s, contains('全部本地处理'));
      expect(s, isNot(contains('未经我方服务器')));
    });

    test('cloud unchanged', () {
      expect(
        formatAiTraceBadge(_trace(backend: Backend.cloud)),
        contains('仅云端推理'),
      );
    });
  });

  group('AiTrace.copyWith (W-D6)', () {
    test('overrides only the runtime axes, preserves the rest', () {
      final base = _trace(backend: Backend.cloud);
      final dev = base.copyWith(
        backend: Backend.device,
        routingReason: kDeviceLlmDirectRoutingReason,
        usedCloud: false,
      );
      expect(dev.backend, Backend.device);
      expect(dev.routingReason, kDeviceLlmDirectRoutingReason);
      expect(dev.usedCloud, isFalse);
      expect(dev.requestId, base.requestId);
      expect(dev.totalDurationMs, base.totalDurationMs);
      // roundtrips through the wire
      expect(
        AiTrace.fromJson(dev.toJson()).routingReason,
        kDeviceLlmDirectRoutingReason,
      );
      expect(AiTrace.fromJson(dev.toJson()).backend, Backend.device);
    });
  });

  group('RuntimeRoutingAiChatApiClient — §4.6.4 device→cloud failover', () {
    test('no device → cloud, unchanged behaviour', () async {
      final cloud = _SpyCloud();
      final out = await _run(RuntimeRoutingAiChatApiClient(cloud: cloud));
      expect(cloud.called, isTrue);
      expect((out.first as TextEvent).text, 'cloud-answer');
    });

    test('device produces content → committed, cloud NOT called', () async {
      final cloud = _SpyCloud();
      final c = RuntimeRoutingAiChatApiClient(
        cloud: cloud,
        device: _ScriptedDevice(const [
          TextEvent('device-answer'),
          DoneEvent(stopReason: 'end_turn', rounds: 1),
        ]),
      );
      final out = await _run(c);
      expect(cloud.called, isFalse);
      expect((out.first as TextEvent).text, 'device-answer');
      expect(out.last, isA<DoneEvent>());
    });

    test('device errors with no content → silently fails over to cloud',
        () async {
      final cloud = _SpyCloud();
      final c = RuntimeRoutingAiChatApiClient(
        cloud: cloud,
        device: _ScriptedDevice(const [
          ErrorEvent('bad api key', code: 'provider_error'),
          DoneEvent(stopReason: 'error', rounds: 1),
        ]),
      );
      final out = await _run(c);
      expect(cloud.called, isTrue);
      // the device's error is suppressed; user sees the cloud answer
      expect(out.whereType<ErrorEvent>(), isEmpty);
      expect((out.first as TextEvent).text, 'cloud-answer');
    });

    test('device throws before any content → fails over to cloud', () async {
      final cloud = _SpyCloud();
      final c = RuntimeRoutingAiChatApiClient(
        cloud: cloud,
        device: _ScriptedDevice(const [], throwAfter: 0),
      );
      final out = await _run(c);
      expect(cloud.called, isTrue);
      expect((out.first as TextEvent).text, 'cloud-answer');
    });

    test('device throws AFTER content → propagates, cloud NOT called',
        () async {
      final cloud = _SpyCloud();
      final c = RuntimeRoutingAiChatApiClient(
        cloud: cloud,
        device: _ScriptedDevice(
          const [TextEvent('partial')],
          throwAfter: 1,
        ),
      );
      expect(_run(c), throwsA(isA<StateError>()));
      // give the stream a tick to surface; cloud must not be retried
      await Future<void>.delayed(Duration.zero);
      expect(cloud.called, isFalse);
    });
  });

  group('device tool static contract (W-D6)', () {
    test('every kDeviceTools name resolves in the descriptor mirror', () {
      for (final tool in kDeviceTools) {
        final d = lookupToolDescriptor(tool.name);
        expect(
          d,
          isNotNull,
          reason:
              '${tool.name} is dispatchable on device but missing from '
              'tool_descriptor.dart — wire/descriptor drift (§10)',
        );
        // device tools are read-only in this wave (no propose_* yet)
        expect(d!.sideEffect, SideEffect.none, reason: tool.name);
      }
    });

    test('registry advertises exactly the canonical set, sorted', () {
      final names = defaultDeviceToolRegistry().schemas().map((s) => s.name);
      expect(names, [
        'get_anomaly_flags',
        'get_asset_allocation',
        'get_holdings',
        'get_investment_performance',
        'get_recurring_patterns',
        'get_refund_links',
        'get_subscription_changes',
        'get_transfer_links',
        'list_payment_accounts',
      ]);
    });
  });
}
