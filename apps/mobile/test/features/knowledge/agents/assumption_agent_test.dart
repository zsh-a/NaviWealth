import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/knowledge/agents/assumption_agent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/agent_runtime_effect_plan_test_harness.dart';
import '../../../core/persistence/test_database.dart';

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  group('assumptionReviewItemsFromToolResult', () {
    test('parses list_open_assumptions output', () {
      final items = assumptionReviewItemsFromToolResult(const <String, Object?>{
        'assumptions': <Object?>[
          <String, Object?>{
            'id': 'assumption_1',
            'statement': 'Rates stay high',
            'days_since_verify': 91,
          },
        ],
      });

      expect(items, isNotNull);
      expect(items!.single.id, 'assumption_1');
      expect(items.single.daysSinceVerify, 91);
    });

    test('returns null for malformed output', () {
      final items = assumptionReviewItemsFromToolResult(const <String, Object?>{
        'assumptions': <Object?>[
          <String, Object?>{'id': 'assumption_1'},
        ],
      });

      expect(items, isNull);
    });
  });

  group('FrbAssumptionReviewReader', () {
    test(
      'reads assumptions through FRB list_open_assumptions effect loop',
      () async {
        final dispatcher = _AssumptionDispatcher();
        final bridge = FakeAgentRuntimeEffectPlanBridge();
        final traces = <AgentRuntimeNativeStepRunResult>[];
        final reader = FrbAssumptionReviewReader(
          runtime: _runtime(
            bridge: bridge,
            dispatcher: dispatcher,
            recordTrace: (stepRun) async => traces.add(stepRun),
          ),
        );

        final snapshot = await reader.listOpen(_context());

        expect(snapshot.open, hasLength(2));
        expect(snapshot.open.first.id, 'assumption_stale');
        expect(snapshot.traceId, 'agent-runtime:knowledge_assumption:run_1');
        expect(dispatcher.calls.single.name, 'list_open_assumptions');
        expect(dispatcher.calls.single.input, containsPair('limit', 50));
        expect(
          bridge.startRequests.single.agentId,
          kKnowledgeAssumptionAgentId,
        );
        expect(
          bridge.startRequests.single.request['metadata'],
          containsPair('surface', 'knowledge_assumption'),
        );
        expect(traces.single.terminalStep['status'], 'completed');
        expect(traces.single.dispatchedEffectCount, 1);
      },
    );

    test('falls back when FRB effect path fails', () async {
      final fallback = _FallbackReader(
        const AssumptionReviewSnapshot(
          open: <AssumptionReviewItem>[
            AssumptionReviewItem(
              id: 'fallback_assumption',
              statement: 'Fallback assumption',
              daysSinceVerify: 100,
            ),
          ],
        ),
      );
      final reader = FrbAssumptionReviewReader(
        runtime: _runtime(
          bridge: FailingAgentRuntimeEffectPlanBridge(),
          dispatcher: _AssumptionDispatcher(),
        ),
        fallback: fallback,
      );

      final snapshot = await reader.listOpen(_context());

      expect(snapshot.open.single.id, 'fallback_assumption');
      expect(fallback.calls, 1);
    });

    test(
      'ignores trace recording failures after a successful FRB read',
      () async {
        final fallback = _FallbackReader(
          const AssumptionReviewSnapshot(
            open: <AssumptionReviewItem>[
              AssumptionReviewItem(
                id: 'fallback_assumption',
                statement: 'Fallback assumption',
                daysSinceVerify: 100,
              ),
            ],
          ),
        );
        final reader = FrbAssumptionReviewReader(
          runtime: _runtime(
            bridge: FakeAgentRuntimeEffectPlanBridge(),
            dispatcher: _AssumptionDispatcher(),
            recordTrace: (_) async =>
                throw StateError('trace store unavailable'),
          ),
          fallback: fallback,
        );

        final snapshot = await reader.listOpen(_context());

        expect(snapshot.open, hasLength(2));
        expect(snapshot.open.first.id, 'assumption_stale');
        expect(snapshot.traceId, isNull);
        expect(fallback.calls, 0);
      },
    );
  });

  test('run persists a stale-assumption artifact with evidence', () async {
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
    const agent = AssumptionAgent(
      assumptionReader: _FixedAssumptionReader(
        AssumptionReviewSnapshot(
          open: <AssumptionReviewItem>[
            AssumptionReviewItem(
              id: 'assumption-stale',
              statement: 'Rates stay high',
              daysSinceVerify: kAssumptionStaleDays,
            ),
            AssumptionReviewItem(
              id: 'assumption-fresh',
              statement: 'Demand holds',
              daysSinceVerify: 7,
            ),
          ],
          traceId: 'trace-assumption-1',
        ),
      ),
    );

    final result = await _runAgent(
      container,
      agent,
      DateTime.utc(2026, 7, 5, 8),
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.memoryId, '$kKnowledgeAssumptionMemorySource:2026-07-05');
    expect(result.artifactId, '$kKnowledgeAssumptionAgentId:2026-07-05');
    expect(result.traceId, 'trace-assumption-1');
    expect(runtime.remembered?.payload['artifact_id'], result.artifactId);
    expect(runtime.remembered?.payload['trace_id'], 'trace-assumption-1');

    final artifact = await artifactStore.read(result.artifactId!);
    expect(artifact, isNotNull);
    expect(artifact!.kind, AgentArtifactKind.review);
    expect(artifact.severity, AgentArtifactSeverity.attention);
    expect(artifact.memoryId, result.memoryId);
    expect(artifact.traceId, 'trace-assumption-1');
    expect(artifact.insights.single.title, 'Stale assumptions');
    expect(artifact.evidence.map((ref) => ref.id), ['assumption-stale']);
    expect(artifact.actions.single.intent, 'knowledge.reviewDueItems');
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
  required AgentRuntimeNativeBridge bridge,
  required DeviceToolDispatcher dispatcher,
  Future<void> Function(AgentRuntimeNativeStepRunResult stepRun)? recordTrace,
}) {
  return agentRuntimeEffectPlanTestBinding(
    agentId: kKnowledgeAssumptionAgentId,
    domain: 'knowledge',
    surface: 'knowledge_assumption',
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
        id: kKnowledgeAssumptionAgentId,
        name: 'Assumption Review',
        version: '0.1.0',
        schedule: AgentRuntimeScheduleSpec.interval(everySeconds: 2592000),
        capabilities: <String>['scheduled_agent'],
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
    ],
    tools: const <AgentRuntimeToolSpec>[
      AgentRuntimeToolSpec(
        name: 'list_open_assumptions',
        description: 'List open assumptions',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
    ],
    proposalKinds: const <AgentRuntimeProposalKindSpec>[],
    promptBlocks: const <AgentRuntimePromptBlockSpec>[],
  );
}

class _AssumptionDispatcher implements DeviceToolDispatcher {
  final calls = <AgentRuntimeEffectPlanToolEffect>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(AgentRuntimeEffectPlanToolEffect(name, input));
    return <String, Object?>{
      'assumptions': <Object?>[
        <String, Object?>{
          'id': 'assumption_stale',
          'statement': 'Rates stay high',
          'days_since_verify': 91,
        },
        <String, Object?>{
          'id': 'assumption_fresh',
          'statement': 'Demand holds',
          'days_since_verify': 7,
        },
      ],
    };
  }
}

class _FallbackReader implements AssumptionReviewReader {
  _FallbackReader(this.result);

  final AssumptionReviewSnapshot result;
  var calls = 0;

  @override
  Future<AssumptionReviewSnapshot> listOpen(AgentContext ctx) async {
    calls += 1;
    return result;
  }
}

Future<AgentRunResult> _runAgent(
  ProviderContainer container,
  AssumptionAgent agent,
  DateTime now,
) {
  final probe = FutureProvider<AgentRunResult>(
    (ref) => agent.run(AgentContext(ref: ref, now: now)),
  );
  container.listen(probe, (_, _) {});
  return container.read(probe.future);
}

class _FixedAssumptionReader implements AssumptionReviewReader {
  const _FixedAssumptionReader(this.result);

  final AssumptionReviewSnapshot result;

  @override
  Future<AssumptionReviewSnapshot> listOpen(AgentContext ctx) async => result;
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
