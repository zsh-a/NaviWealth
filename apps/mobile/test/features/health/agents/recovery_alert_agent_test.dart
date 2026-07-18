import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_intents.dart';
import 'package:naviwealth/core/ai/agents/agent_preference_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/regression/agent_outcome_evaluator.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/notifications/notification_service.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/features/health/agents/providers.dart'
    as health_agent_providers;
import 'package:naviwealth/features/health/agents/recovery_alert_agent.dart';

import '../../../app/agent_runtime_effect_plan_test_harness.dart';
import '../../../core/persistence/test_database.dart';

const _owner = 'u-health-recovery';

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
    test('reads HRV through FRB effect continuation', () async {
      final dispatcher = _RecoveryTrendDispatcher();
      final bridge = FakeAgentRuntimeEffectPlanBridge();
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
      expect(result.traceId, 'agent-runtime:recovery_alert:run_1');
      expect(result.alert!.consecutiveDays, 3);
      expect(dispatcher.calls.single.name, 'get_hrv_trend');
      expect(dispatcher.calls.single.input, containsPair('window_days', 14));
      expect(bridge.startRequests.single.agentId, kRecoveryAlertAgentId);
      expect(
        bridge.startRequests.single.request['metadata'],
        containsPair('surface', 'health_recovery_alert'),
      );
      expect(traces.single.terminalStep['status'], 'completed');
      expect(traces.single.dispatchedEffectCount, 1);
    });

    test('falls back when FRB effect path fails', () async {
      final fallback = _FallbackReader(
        RecoveryAlertSignalRead.skipped(
          source: 'fallback',
          reason: 'fallback used',
        ),
      );
      final reader = FrbRecoveryAlertSignalReader(
        runtime: _runtime(
          bridge: FailingAgentRuntimeEffectPlanBridge(),
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
            bridge: FakeAgentRuntimeEffectPlanBridge(),
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

  test(
    'writes a unified recovery alert artifact from an alert signal',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteAgentArtifactStore(db: db);
      final preferences = InMemoryAgentPreferenceStore();
      final runtime = _FakeMemoryRuntime();
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue(() async => _owner),
          memoryRuntimeProvider.overrideWith((ref) async => runtime),
          agent_providers.agentArtifactStoreProvider.overrideWith(
            (ref) async => store,
          ),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => preferences,
          ),
        ],
      );
      addTearDown(container.dispose);
      final ref = container.read(_refProvider);
      final notifier = _RecordingNotificationService();
      final agent = RecoveryAlertAgent(
        notifier: notifier,
        signalReader: _FallbackReader(
          RecoveryAlertSignalRead.alert(
            source: 'test',
            alert: const RecoveryAlertSignal(
              avgBaselineMs: 50,
              avgRecentMs: 40,
              declinePct: 20,
              consecutiveDays: 3,
            ),
            traceId: 'trace-recovery-1',
          ),
        ),
      );

      final result = await agent.run(
        AgentContext(ref: ref, now: DateTime.utc(2026, 6, 29, 8)),
      );

      expect(result.status, AgentRunStatus.completed);
      expect(result.artifactId, '$kRecoveryAlertAgentId:2026-06-29');
      expect(result.traceId, 'trace-recovery-1');
      expect(runtime.remembered?.payload['artifact_id'], result.artifactId);
      expect(runtime.remembered?.payload['trace_id'], 'trace-recovery-1');
      final outcome = runtime.remembered?.payload['outcome'] as Map;
      expect(outcome['trace_id'], 'trace-recovery-1');

      final artifact = await store.read(result.artifactId!);
      expect(artifact, isNotNull);
      expect(artifact!.kind, AgentArtifactKind.alert);
      expect(artifact.domain, 'health');
      expect(artifact.severity, AgentArtifactSeverity.warning);
      expect(artifact.memoryId, result.memoryId);
      expect(artifact.traceId, 'trace-recovery-1');
      expect(artifact.summary, result.summary);
      expect(
        artifact.insights.map((insight) => insight.title),
        contains('HRV decline'),
      );
      expect(artifact.evidence.single.type, 'health_metric_trend');
      expect(artifact.actions.single.objectId, result.artifactId);
      expect(artifact.actions.single.intent, kHealthExplainRecoveryAlertIntent);
      expect(artifact.actions.single.objectType, kAgentArtifactObjectType);
      final outcomeFailures = evaluateAgentOutcomeCase(
        regressionCase: agentOutcomeRegressionCaseById(
          'health.recovery_alert.ready',
        ),
        result: result,
        artifact: artifact,
      );
      expect(outcomeFailures, isEmpty, reason: outcomeFailures.join('\n'));
      expect(notifier.showCount, 1);
      expect(
        notifier.lastPayload,
        '/health?agent_artifact_id=recovery_alert%3A2026-06-29',
      );
    },
  );

  test(
    'skips local notification when recovery alert notifications are off',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteAgentArtifactStore(db: db);
      final preferences = InMemoryAgentPreferenceStore();
      await preferences.setNotificationsEnabled(
        ownerUserId: _owner,
        agentId: kRecoveryAlertAgentId,
        enabled: false,
        updatedAt: DateTime.utc(2026, 6, 29, 8),
      );
      final runtime = _FakeMemoryRuntime();
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue(() async => _owner),
          memoryRuntimeProvider.overrideWith((ref) async => runtime),
          agent_providers.agentArtifactStoreProvider.overrideWith(
            (ref) async => store,
          ),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => preferences,
          ),
        ],
      );
      addTearDown(container.dispose);
      final ref = container.read(_refProvider);
      final notifier = _RecordingNotificationService();
      final agent = RecoveryAlertAgent(
        notifier: notifier,
        signalReader: _FallbackReader(
          RecoveryAlertSignalRead.alert(
            source: 'test',
            alert: const RecoveryAlertSignal(
              avgBaselineMs: 50,
              avgRecentMs: 40,
              declinePct: 20,
              consecutiveDays: 3,
            ),
          ),
        ),
      );

      final result = await agent.run(
        AgentContext(ref: ref, now: DateTime.utc(2026, 6, 29, 8)),
      );

      expect(result.status, AgentRunStatus.completed);
      expect(await store.read(result.artifactId!), isNotNull);
      expect(notifier.showCount, 0);
    },
  );

  test(
    'latest recovery alert artifact provider returns newest alert',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteAgentArtifactStore(db: db);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => _owner),
          agent_providers.agentArtifactStoreProvider.overrideWith(
            (ref) async => store,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(auth.domainOptInsProvider.future);
      await container
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.health, true);
      await store.save(
        _recoveryArtifact(
          id: 'recovery-old',
          createdAt: DateTime.utc(2026, 6, 28, 8),
        ),
      );
      await store.save(
        _recoveryArtifact(
          id: 'recovery-new',
          createdAt: DateTime.utc(2026, 6, 29, 8),
        ),
      );

      final artifact = await container.read(
        health_agent_providers.latestRecoveryAlertArtifactProvider.future,
      );

      expect(artifact?.id, 'recovery-new');
    },
  );
}

AgentContext _context() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final ref = container.read(_refProvider);
  return AgentContext(ref: ref, now: DateTime.utc(2026, 6, 29, 8));
}

final _refProvider = Provider<Ref>((ref) => ref);

AgentArtifact _recoveryArtifact({
  required String id,
  required DateTime createdAt,
}) {
  return AgentArtifact(
    id: id,
    ownerUserId: _owner,
    agentId: kRecoveryAlertAgentId,
    domain: 'health',
    kind: AgentArtifactKind.alert,
    severity: AgentArtifactSeverity.attention,
    title: 'Recovery Alert',
    summary: 'HRV has been below baseline.',
    createdAt: createdAt,
  );
}

AgentRuntimeEffectPlanBinding _runtime({
  required AgentRuntimeExecutionBridge bridge,
  required DeviceToolDispatcher dispatcher,
  Future<void> Function(AgentRuntimeNativeStepRunResult stepRun)? recordTrace,
}) {
  return agentRuntimeEffectPlanTestBinding(
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
        replayPolicy: 'safe_retry',
        metadata: <String, Object?>{'domain': 'health'},
      ),
    ],
    proposalKinds: const <AgentRuntimeProposalKindSpec>[],
    promptBlocks: const <AgentRuntimePromptBlockSpec>[],
  );
}

class _RecoveryTrendDispatcher implements DeviceToolDispatcher {
  final calls = <AgentRuntimeEffectPlanToolEffect>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(AgentRuntimeEffectPlanToolEffect(name, input));
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

class _FakeMemoryRuntime implements MemoryRuntime {
  MemoryRecord? remembered;

  @override
  Future<void> remember(MemoryRecord record) async {
    remembered = record;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _RecordingNotificationService implements NotificationService {
  int showCount = 0;
  String? lastPayload;

  @override
  Stream<String> get payloads => const Stream<String>.empty();

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<String?> initialPayload() async => null;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required NotificationChannelSpec channel,
    String? payload,
  }) async {
    showCount += 1;
    lastPayload = payload;
  }
}
