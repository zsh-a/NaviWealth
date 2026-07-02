import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_native_bridge.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_tool_plan_binding.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/features/health/agents/recovery_alert_agent.dart';

import '../../../app/agent_runtime_tool_plan_test_harness.dart';

void main() {
  group('recoveryAlertSignalFromValues', () {
    test('detects sustained HRV decline', () {
      final now = DateTime.utc(2026, 6, 29);
      final result = recoveryAlertSignalFromValues(<RecoveryAlertHrvPoint>[
        for (var i = 7; i >= 4; i--)
          RecoveryAlertHrvPoint(now.subtract(Duration(days: i)), 50),
        RecoveryAlertHrvPoint(now.subtract(const Duration(days: 3)), 42),
        RecoveryAlertHrvPoint(now.subtract(const Duration(days: 2)), 40),
        RecoveryAlertHrvPoint(now.subtract(const Duration(days: 1)), 38),
      ], source: 'test');

      expect(result.skipReason, isNull);
      expect(result.alert, isNotNull);
      expect(result.alert!.consecutiveDays, 3);
      expect(result.alert!.avgBaselineMs, 50);
      expect(result.alert!.avgRecentMs, 40);
      expect(result.alert!.declinePct, 20);
    });

    test('skips when recent HRV is not consistently below baseline', () {
      final now = DateTime.utc(2026, 6, 29);
      final result = recoveryAlertSignalFromValues(<RecoveryAlertHrvPoint>[
        for (var i = 7; i >= 4; i--)
          RecoveryAlertHrvPoint(now.subtract(Duration(days: i)), 50),
        RecoveryAlertHrvPoint(now.subtract(const Duration(days: 3)), 42),
        RecoveryAlertHrvPoint(now.subtract(const Duration(days: 2)), 52),
        RecoveryAlertHrvPoint(now.subtract(const Duration(days: 1)), 38),
      ], source: 'test');

      expect(result.alert, isNull);
      expect(result.skipReason, 'no sustained HRV decline detected');
    });
  });

  group('FrbRecoveryAlertSignalReader', () {
    test('reads HRV through FRB tool-plan continuation', () async {
      final dispatcher = _RecoveryTrendDispatcher();
      final bridge = FakeAgentRuntimeToolPlanBridge();
      final traces = <AgentRuntimeNativeStepRunResult>[];
      final reader = FrbRecoveryAlertSignalReader(
        runtime: _runtime(
          bridge: bridge,
          dispatcher: dispatcher,
          recordTrace: (stepRun) async => traces.add(stepRun),
        ),
      );
      final result = await reader.read(_context());

      expect(result.source, 'frb_tool:get_hrv_trend');
      expect(result.alert, isNotNull);
      expect(result.alert!.consecutiveDays, 3);
      expect(dispatcher.calls.single.name, 'get_hrv_trend');
      expect(dispatcher.calls.single.input, containsPair('window_days', 14));
      expect(bridge.startRequests.single.agentId, kRecoveryAlertAgentId);
      expect(
        bridge.startRequests.single.request['metadata'],
        containsPair('surface', 'health_recovery_alert'),
      );
      expect(traces.single.terminalStep['status'], 'completed');
      expect(traces.single.dispatchedToolCount, 1);
    });

    test('falls back when FRB tool path fails', () async {
      final fallback = _FallbackReader(
        RecoveryAlertSignalRead.skipped(
          source: 'fallback',
          reason: 'fallback used',
        ),
      );
      final reader = FrbRecoveryAlertSignalReader(
        runtime: _runtime(
          bridge: FailingAgentRuntimeToolPlanBridge(),
          dispatcher: _RecoveryTrendDispatcher(),
        ),
        fallback: fallback,
      );

      final result = await reader.read(_context());

      expect(result.source, 'fallback');
      expect(result.skipReason, 'fallback used');
      expect(fallback.calls, 1);
    });

    test(
      'ignores trace recording failures after a successful FRB read',
      () async {
        final fallback = _FallbackReader(
          RecoveryAlertSignalRead.skipped(
            source: 'fallback',
            reason: 'fallback used',
          ),
        );
        final reader = FrbRecoveryAlertSignalReader(
          runtime: _runtime(
            bridge: FakeAgentRuntimeToolPlanBridge(),
            dispatcher: _RecoveryTrendDispatcher(),
            recordTrace: (_) async =>
                throw StateError('trace store unavailable'),
          ),
          fallback: fallback,
        );

        final result = await reader.read(_context());

        expect(result.source, 'frb_tool:get_hrv_trend');
        expect(result.alert, isNotNull);
        expect(result.alert!.consecutiveDays, 3);
        expect(fallback.calls, 0);
      },
    );
  });
}

AgentContext _context() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final ref = container.read(_refProvider);
  return AgentContext(ref: ref, now: DateTime.utc(2026, 6, 29, 8));
}

final _refProvider = Provider<Ref>((ref) => ref);

AgentRuntimeToolPlanBinding _runtime({
  required AgentRuntimeNativeBridge bridge,
  required DeviceToolDispatcher dispatcher,
  Future<void> Function(AgentRuntimeNativeStepRunResult stepRun)? recordTrace,
}) {
  return agentRuntimeToolPlanTestBinding(
    agentId: kRecoveryAlertAgentId,
    domain: 'health',
    surface: 'health_recovery_alert',
    bridge: bridge,
    dispatcher: dispatcher,
    catalog: _catalog(),
    recordTrace: recordTrace,
  );
}

AgentRuntimeCatalog _catalog() {
  return AgentRuntimeCatalog(
    generatedAt: DateTime.utc(2026, 6, 29, 8),
    activeDomains: const <String>['health'],
    agents: const <AgentRuntimeAgentSpec>[
      AgentRuntimeAgentSpec(
        id: kRecoveryAlertAgentId,
        name: 'Recovery Alert',
        version: '0.1.0',
        schedule: AgentRuntimeScheduleSpec.interval(everySeconds: 86400),
        capabilities: <String>['scheduled_agent'],
        metadata: <String, Object?>{'domain': 'health'},
      ),
    ],
    tools: const <AgentRuntimeToolSpec>[
      AgentRuntimeToolSpec(
        name: 'get_hrv_trend',
        description: 'Get HRV trend',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'suggest',
        metadata: <String, Object?>{'domain': 'health'},
      ),
    ],
    proposalKinds: const <AgentRuntimeProposalKindSpec>[],
    promptBlocks: const <AgentRuntimePromptBlockSpec>[],
  );
}

class _RecoveryTrendDispatcher implements DeviceToolDispatcher {
  final calls = <AgentRuntimeToolPlanToolCall>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(AgentRuntimeToolPlanToolCall(name, input));
    return <String, Object?>{
      'window_days': 14,
      'points': <Object?>[
        <String, Object?>{'date': '2026-06-22', 'hrv_ms': 50},
        <String, Object?>{'date': '2026-06-23', 'hrv_ms': 50},
        <String, Object?>{'date': '2026-06-24', 'hrv_ms': 50},
        <String, Object?>{'date': '2026-06-25', 'hrv_ms': 50},
        <String, Object?>{'date': '2026-06-26', 'hrv_ms': 42},
        <String, Object?>{'date': '2026-06-27', 'hrv_ms': 40},
        <String, Object?>{'date': '2026-06-28', 'hrv_ms': 38},
      ],
    };
  }
}

class _FallbackReader implements RecoveryAlertSignalReader {
  _FallbackReader(this.result);

  final RecoveryAlertSignalRead result;
  var calls = 0;

  @override
  Future<RecoveryAlertSignalRead> read(AgentContext ctx) async {
    calls += 1;
    return result;
  }
}
