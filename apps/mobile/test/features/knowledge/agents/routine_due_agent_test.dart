import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
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
import 'package:naviwealth/core/notifications/notification_service.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/knowledge/agents/knowledge_notifications.dart';
import 'package:naviwealth/features/knowledge/agents/routine_due_agent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/agent_runtime_effect_plan_test_harness.dart';
import '../../../core/persistence/test_database.dart';

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  group('routineDueItemsFromToolResult', () {
    test('parses list_due_routines output', () {
      final items = routineDueItemsFromToolResult(const <String, Object?>{
        'routines': <Object?>[
          <String, Object?>{
            'id': 'routine_1',
            'statement': 'Activate bank card',
            'next_due_at': '2026-06-29T00:00:00.000Z',
          },
        ],
      });

      expect(items, isNotNull);
      expect(items!.single.id, 'routine_1');
      expect(items.single.statement, 'Activate bank card');
      expect(items.single.isDue(DateTime.utc(2026, 6, 29, 8)), isTrue);
    });

    test('returns null for malformed tool output', () {
      final items = routineDueItemsFromToolResult(const <String, Object?>{
        'routines': <Object?>[
          <String, Object?>{'id': 'routine_1'},
        ],
      });

      expect(items, isNull);
    });
  });

  group('KnowledgeNotifications routine payloads', () {
    test('builds the canonical Agent artifact route', () {
      final payload = KnowledgeNotifications.payloadForArtifact(
        'knowledge_routine_due:2026-07-05',
      );

      expect(payload, '/insights/knowledge_routine_due%3A2026-07-05');
    });
  });

  group('FrbRoutineDueReader', () {
    test('reads routines through FRB list_due_routines effect loop', () async {
      final dispatcher = _RoutineDispatcher();
      final bridge = FakeAgentRuntimeEffectPlanBridge();
      final traces = <AgentRuntimeNativeStepRunResult>[];
      final reader = FrbRoutineDueReader(
        runtime: _runtime(
          bridge: bridge,
          dispatcher: dispatcher,
          recordTrace: (stepRun) async => traces.add(stepRun),
        ),
      );

      final snapshot = await reader.listDue(_context());

      expect(snapshot.due, hasLength(1));
      expect(snapshot.due.single.id, 'routine_1');
      expect(snapshot.due.single.statement, 'Activate bank card');
      expect(snapshot.traceId, 'agent-runtime:knowledge_routine_due:run_1');
      expect(dispatcher.calls.single.name, 'list_due_routines');
      expect(dispatcher.calls.single.input, containsPair('limit', 50));
      expect(bridge.startRequests.single.agentId, kKnowledgeRoutineAgentId);
      expect(
        bridge.startRequests.single.request['metadata'],
        containsPair('surface', 'knowledge_routine_due'),
      );
      expect(traces.single.terminalStep['status'], 'completed');
      expect(traces.single.dispatchedEffectCount, 1);
    });

    test('falls back when FRB effect path fails', () async {
      final fallback = _FallbackReader(
        RoutineDueSnapshot(
          due: <RoutineDueItem>[
            RoutineDueItem(
              id: 'fallback_routine',
              statement: 'Fallback routine',
              nextDueAt: DateTime.utc(2026, 6, 30),
            ),
          ],
        ),
      );
      final reader = FrbRoutineDueReader(
        runtime: _runtime(
          bridge: FailingAgentRuntimeEffectPlanBridge(),
          dispatcher: _RoutineDispatcher(),
        ),
        fallback: fallback,
      );

      final snapshot = await reader.listDue(_context());

      expect(snapshot.due.single.id, 'fallback_routine');
      expect(fallback.calls, 1);
    });

    test(
      'ignores trace recording failures after a successful FRB read',
      () async {
        final fallback = _FallbackReader(
          RoutineDueSnapshot(
            due: <RoutineDueItem>[
              RoutineDueItem(
                id: 'fallback_routine',
                statement: 'Fallback routine',
                nextDueAt: DateTime.utc(2026, 6, 30),
              ),
            ],
          ),
        );
        final reader = FrbRoutineDueReader(
          runtime: _runtime(
            bridge: FakeAgentRuntimeEffectPlanBridge(),
            dispatcher: _RoutineDispatcher(),
            recordTrace: (_) async =>
                throw StateError('trace store unavailable'),
          ),
          fallback: fallback,
        );

        final snapshot = await reader.listDue(_context());

        expect(snapshot.due, hasLength(1));
        expect(snapshot.due.single.id, 'routine_1');
        expect(snapshot.traceId, isNull);
        expect(fallback.calls, 0);
      },
    );
  });

  test('run persists a routine reminder artifact with evidence', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final artifactStore = SqliteAgentArtifactStore(db: db);
    final runtime = _FakeMemoryRuntime();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserIdProvider.overrideWithValue(() async => 'user-1'),
        memoryRuntimeProvider.overrideWith((ref) async => runtime),
        agent_providers.agentArtifactStoreProvider.overrideWith(
          (ref) async => artifactStore,
        ),
      ],
    );
    addTearDown(container.dispose);
    final agent = RoutineDueAgent(
      dueReader: _FixedRoutineReader(
        RoutineDueSnapshot(
          due: <RoutineDueItem>[
            RoutineDueItem(
              id: 'routine-overdue',
              statement: 'Activate bank card',
              nextDueAt: DateTime.utc(2026, 7, 4, 8),
            ),
            RoutineDueItem(
              id: 'routine-upcoming',
              statement: 'Review notes',
              nextDueAt: DateTime.utc(2026, 7, 9, 8),
            ),
          ],
          traceId: 'trace-routine-1',
        ),
      ),
    );

    final result = await _runAgent(
      container,
      agent,
      DateTime.utc(2026, 7, 5, 8),
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.memoryId, '$kKnowledgeRoutineMemorySource:2026-07-05');
    expect(result.artifactId, '$kKnowledgeRoutineAgentId:2026-07-05');
    expect(result.traceId, 'trace-routine-1');
    expect(runtime.remembered?.payload['artifact_id'], result.artifactId);
    expect(runtime.remembered?.payload['trace_id'], 'trace-routine-1');

    final artifact = await artifactStore.read(result.artifactId!);
    expect(artifact, isNotNull);
    expect(artifact!.kind, AgentArtifactKind.reminder);
    expect(artifact.severity, AgentArtifactSeverity.attention);
    expect(artifact.memoryId, result.memoryId);
    expect(artifact.traceId, 'trace-routine-1');
    expect(artifact.insights.map((insight) => insight.title), [
      'Overdue routines',
      'Upcoming routines',
    ]);
    expect(artifact.evidence.map((ref) => ref.id), [
      'routine-overdue',
      'routine-upcoming',
    ]);
    expect(artifact.actions.single.intent, 'knowledge.reviewDueItems');
    final outcomeFailures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'knowledge.routine_due.ready',
      ),
      result: result,
      artifact: artifact,
    );
    expect(outcomeFailures, isEmpty);
  });

  test(
    'run skips local notification when agent notifications are off',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final artifactStore = SqliteAgentArtifactStore(db: db);
      final runtime = _FakeMemoryRuntime();
      final preferences = InMemoryAgentPreferenceStore();
      await preferences.setNotificationsEnabled(
        ownerUserId: 'user-1',
        agentId: kKnowledgeRoutineAgentId,
        enabled: false,
        updatedAt: DateTime.utc(2026, 7, 5, 7),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue(() async => 'user-1'),
          memoryRuntimeProvider.overrideWith((ref) async => runtime),
          agent_providers.agentArtifactStoreProvider.overrideWith(
            (ref) async => artifactStore,
          ),
          agent_providers.agentPreferenceStoreProvider.overrideWith(
            (ref) async => preferences,
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier = _RecordingNotificationService();
      final agent = RoutineDueAgent(
        notifier: notifier,
        dueReader: _FixedRoutineReader(
          RoutineDueSnapshot(
            due: <RoutineDueItem>[
              RoutineDueItem(
                id: 'routine-overdue',
                statement: 'Activate bank card',
                nextDueAt: DateTime.utc(2026, 7, 4, 8),
              ),
            ],
          ),
        ),
      );

      final result = await _runAgent(
        container,
        agent,
        DateTime.utc(2026, 7, 5, 8),
      );

      expect(result.status, AgentRunStatus.completed);
      expect(notifier.showCount, 0);
    },
  );

  test('run posts routine notification with artifact route payload', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final artifactStore = SqliteAgentArtifactStore(db: db);
    final runtime = _FakeMemoryRuntime();
    final preferences = InMemoryAgentPreferenceStore();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserIdProvider.overrideWithValue(() async => 'user-1'),
        memoryRuntimeProvider.overrideWith((ref) async => runtime),
        agent_providers.agentArtifactStoreProvider.overrideWith(
          (ref) async => artifactStore,
        ),
        agent_providers.agentPreferenceStoreProvider.overrideWith(
          (ref) async => preferences,
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = _RecordingNotificationService();
    final agent = RoutineDueAgent(
      notifier: notifier,
      dueReader: _FixedRoutineReader(
        RoutineDueSnapshot(
          due: <RoutineDueItem>[
            RoutineDueItem(
              id: 'routine-overdue',
              statement: 'Activate bank card',
              nextDueAt: DateTime.utc(2026, 7, 4, 8),
            ),
          ],
        ),
      ),
    );

    final result = await _runAgent(
      container,
      agent,
      DateTime.utc(2026, 7, 5, 8),
    );

    expect(result.artifactId, '$kKnowledgeRoutineAgentId:2026-07-05');
    expect(notifier.showCount, 1);
    expect(
      notifier.lastPayload,
      '/insights/knowledge_routine_due%3A2026-07-05',
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

AgentRuntimeEffectPlanBinding _runtime({
  required AgentRuntimeExecutionBridge bridge,
  required DeviceToolDispatcher dispatcher,
  Future<void> Function(AgentRuntimeNativeStepRunResult stepRun)? recordTrace,
}) {
  return agentRuntimeEffectPlanTestBinding(
    agentId: kKnowledgeRoutineAgentId,
    domain: 'knowledge',
    surface: 'knowledge_routine_due',
    bridge: bridge,
    dispatcher: dispatcher,
    catalog: _catalog(),
    recordTrace: recordTrace,
  );
}

AgentRuntimeCatalog _catalog() {
  return AgentRuntimeCatalog(
    generatedAt: DateTime.utc(2026, 6, 29, 8),
    activeDomains: const <String>['knowledge'],
    agents: const <AgentRuntimeAgentSpec>[
      AgentRuntimeAgentSpec(
        id: kKnowledgeRoutineAgentId,
        name: 'Routine Due',
        version: '0.1.0',
        schedule: AgentRuntimeScheduleSpec.interval(everySeconds: 86400),
        capabilities: <String>['scheduled_agent'],
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
    ],
    tools: const <AgentRuntimeToolSpec>[
      AgentRuntimeToolSpec(
        name: 'list_due_routines',
        description: 'List due routines',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        replayPolicy: 'safe_retry',
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
    ],
    proposalKinds: const <AgentRuntimeProposalKindSpec>[],
    promptBlocks: const <AgentRuntimePromptBlockSpec>[],
  );
}

class _RoutineDispatcher implements DeviceToolDispatcher {
  final calls = <AgentRuntimeEffectPlanToolEffect>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(AgentRuntimeEffectPlanToolEffect(name, input));
    return <String, Object?>{
      'as_of': '2026-07-06T08:00:00.000Z',
      'routines': <Object?>[
        <String, Object?>{
          'id': 'routine_1',
          'statement': 'Activate bank card',
          'interval_days': 180,
          'scope': 'personal',
          'next_due_at': '2026-06-29T00:00:00.000Z',
          'last_done_at': null,
          'days_until_due': 0,
        },
      ],
    };
  }
}

class _FallbackReader implements RoutineDueReader {
  _FallbackReader(this.result);

  final RoutineDueSnapshot result;
  var calls = 0;

  @override
  Future<RoutineDueSnapshot> listDue(AgentContext ctx) async {
    calls += 1;
    return result;
  }
}

Future<AgentRunResult> _runAgent(
  ProviderContainer container,
  RoutineDueAgent agent,
  DateTime now,
) {
  final probe = FutureProvider<AgentRunResult>(
    (ref) => agent.run(AgentContext(ref: ref, now: now)),
  );
  container.listen(probe, (_, _) {});
  return container.read(probe.future);
}

class _FixedRoutineReader implements RoutineDueReader {
  const _FixedRoutineReader(this.result);

  final RoutineDueSnapshot result;

  @override
  Future<RoutineDueSnapshot> listDue(AgentContext ctx) async => result;
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
  var showCount = 0;
  String? lastPayload;

  @override
  Stream<String> get payloads => const Stream<String>.empty();

  @override
  Future<String?> initialPayload() async => null;

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<bool> hasPermissions() async => true;

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
