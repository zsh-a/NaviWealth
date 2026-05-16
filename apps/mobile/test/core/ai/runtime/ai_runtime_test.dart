// Wave 22 — AiRuntime abstraction + RuntimeRegistry contract.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/router/routing_decision.dart';
import 'package:naviwealth/core/ai/runtime/ai_runtime.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_events.dart';

void main() {
  RoutingDecision decisionWith(Backend b) => RoutingDecision(
    backend: b,
    intent: const IntentHint(
      capability: Capability.analyze,
      risk: RiskLevel.suggest,
      label: 'test',
    ),
    budgetTier: BudgetTier.small,
    confirmation: Confirmation.none,
    reason: const RoutingReason(code: 'test'),
    supported: true,
  );

  test('registry round-trips registered runtimes', () {
    final cloud = _FakeRuntime(RuntimeId.cloudAnthropic, 'cloud');
    final device = _FakeRuntime(RuntimeId.rulesDevice, 'device');
    final r = RuntimeRegistry({
      RuntimeId.cloudAnthropic: cloud,
      RuntimeId.rulesDevice: device,
    });
    expect(r.lookup(RuntimeId.cloudAnthropic), same(cloud));
    expect(r.lookup(RuntimeId.rulesDevice), same(device));
    expect(r.registered(), unorderedEquals(<RuntimeId>{
      RuntimeId.cloudAnthropic,
      RuntimeId.rulesDevice,
    }));
  });

  test('pickFor maps Backend.cloud → cloudAnthropic', () {
    final cloud = _FakeRuntime(RuntimeId.cloudAnthropic, 'cloud');
    final device = _FakeRuntime(RuntimeId.rulesDevice, 'device');
    final r = RuntimeRegistry({
      RuntimeId.cloudAnthropic: cloud,
      RuntimeId.rulesDevice: device,
    });
    expect(r.pickFor(decisionWith(Backend.cloud)), same(cloud));
  });

  test('pickFor maps Backend.device → rulesDevice', () {
    final cloud = _FakeRuntime(RuntimeId.cloudAnthropic, 'cloud');
    final device = _FakeRuntime(RuntimeId.rulesDevice, 'device');
    final r = RuntimeRegistry({
      RuntimeId.cloudAnthropic: cloud,
      RuntimeId.rulesDevice: device,
    });
    expect(r.pickFor(decisionWith(Backend.device)), same(device));
  });

  test('pickFor maps Backend.hybrid → cloudAnthropic (Phase 1)', () {
    final cloud = _FakeRuntime(RuntimeId.cloudAnthropic, 'cloud');
    final device = _FakeRuntime(RuntimeId.rulesDevice, 'device');
    final r = RuntimeRegistry({
      RuntimeId.cloudAnthropic: cloud,
      RuntimeId.rulesDevice: device,
    });
    expect(r.pickFor(decisionWith(Backend.hybrid)), same(cloud));
  });

  test('RulesDeviceRuntime emits a single error event', () async {
    const runtime = RulesDeviceRuntime();
    final session = AuthSession(
      accessToken: 't',
      expiresAt: DateTime.utc(2026, 12, 31),
      userId: 'u',
      deviceId: 'd',
    );
    final events = await runtime
        .chat(
          AiRuntimeRequest(
            session: session,
            messages: const [],
            decision: decisionWith(Backend.device),
          ),
        )
        .toList();
    expect(events, hasLength(1));
    expect(events.single, isA<ErrorEvent>());
  });
}

class _FakeRuntime implements AiRuntime {
  _FakeRuntime(this.id, this._tag);
  @override
  final RuntimeId id;
  final String _tag;
  @override
  bool get supportsStreaming => true;
  @override
  Stream<AiChatEvent> chat(AiRuntimeRequest r) async* {
    yield TextEvent(_tag);
  }
}
