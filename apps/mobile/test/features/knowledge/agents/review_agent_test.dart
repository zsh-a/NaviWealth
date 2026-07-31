import 'dart:ui' show Locale;

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
import 'package:naviwealth/core/ai/local/memory/providers.dart'
    show memoryRuntimeProvider;
import 'package:naviwealth/core/ai/regression/agent_outcome_evaluator.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/knowledge/agents/review_agent.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/agent_runtime_effect_plan_test_harness.dart';
import '../../../core/persistence/test_database.dart';

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  test('run reports no finding when nothing is due', () async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserIdProvider.overrideWithValue(() async => 'user-1'),
        memoryRuntimeProvider.overrideWith((ref) async => _FakeMemoryRuntime()),
      ],
    );
    addTearDown(container.dispose);
    const agent = ReviewAgent(
      dueReader: _FixedReviewDueReader(
        ReviewDueSnapshot(
          dueReviews: <ReviewDecisionItem>[],
          staleAssumptions: <ReviewAssumptionItem>[],
        ),
      ),
    );

    final result = await _runAgent(
      container,
      agent,
      DateTime.utc(2026, 7, 5, 9),
    );

    expect(result.status, AgentRunStatus.skipped);
    expect(result.artifactId, isNull);
    final failures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'knowledge.review.no_finding',
      ),
      result: result,
    );
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('run persists a weekly review artifact with evidence', () async {
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
    const agent = ReviewAgent(
      dueReader: _FixedReviewDueReader(
        ReviewDueSnapshot(
          dueReviews: [
            ReviewDecisionItem(
              id: 'decision-1',
              question: 'Revisit portfolio hedge?',
            ),
          ],
          staleAssumptions: [
            ReviewAssumptionItem(
              id: 'assumption-1',
              statement: 'Rates stay high',
            ),
          ],
          traceId: 'trace-knowledge-review-1',
        ),
      ),
    );

    final result = await _runAgent(
      container,
      agent,
      DateTime.utc(2026, 7, 5, 9),
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.memoryId, '$kKnowledgeReviewMemorySource:2026-07-05');
    expect(result.artifactId, 'knowledge_review:2026-07-05');
    expect(result.traceId, 'trace-knowledge-review-1');
    expect(runtime.remembered?.id, result.memoryId);
    expect(runtime.remembered?.payload['trace_id'], 'trace-knowledge-review-1');

    final artifact = await artifactStore.read(result.artifactId!);
    expect(artifact?.kind, AgentArtifactKind.review);
    expect(artifact?.severity, AgentArtifactSeverity.attention);
    expect(artifact?.memoryId, result.memoryId);
    expect(artifact?.traceId, 'trace-knowledge-review-1');
    expect(artifact?.insights.map((insight) => insight.title), [
      'Decisions due',
      'Stale assumptions',
    ]);
    expect(artifact?.evidence.map((ref) => ref.id), [
      'decision-1',
      'assumption-1',
    ]);
    expect(artifact?.actions.single.intent, 'knowledge.reviewDueItems');
    final outcomeFailures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById('knowledge.review.ready'),
      result: result,
      artifact: artifact,
    );
    expect(outcomeFailures, isEmpty, reason: outcomeFailures.join('\n'));
  });

  test(
    'run persists weekly review artifact labels in Chinese locale',
    () async {
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
      addTearDown(() => prefs.remove('naviwealth.locale'));
      await container.read(localeProvider.notifier).set(const Locale('zh'));
      const agent = ReviewAgent(
        dueReader: _FixedReviewDueReader(
          ReviewDueSnapshot(
            dueReviews: [
              ReviewDecisionItem(id: 'decision-1', question: '是否复查对冲？'),
            ],
            staleAssumptions: [
              ReviewAssumptionItem(id: 'assumption-1', statement: '利率维持高位'),
            ],
          ),
        ),
      );

      final result = await _runAgent(
        container,
        agent,
        DateTime.utc(2026, 7, 5, 9),
      );

      expect(result.status, AgentRunStatus.completed);
      expect(result.summary, contains('可复盘'));
      final artifact = await artifactStore.read(result.artifactId!);
      expect(artifact?.title, '每周知识复盘');
      expect(artifact?.insights.map((insight) => insight.title), [
        '到期决策',
        '过期假设',
      ]);
      expect(artifact?.actions.single.label, '查看知识事项');
    },
  );

  group('review due effect-result parsing', () {
    test('parses terminal multi-tool output and filters stale assumptions', () {
      final snapshot = reviewDueSnapshotFromTerminalStep(
        const <String, Object?>{
          'status': 'completed',
          'output': <String, Object?>{
            'mode': 'frb_effect_loop',
            'effect_results': <Object?>[
              <String, Object?>{
                'effect': <String, Object?>{
                  'kind': 'tool',
                  'name': 'list_due_reviews',
                },
                'effect_response': <String, Object?>{
                  'result': <String, Object?>{
                    'decisions': <Object?>[
                      <String, Object?>{
                        'id': 'decision_1',
                        'question': 'Revisit portfolio hedge?',
                      },
                    ],
                  },
                },
              },
              <String, Object?>{
                'effect': <String, Object?>{
                  'kind': 'tool',
                  'name': 'list_open_assumptions',
                },
                'effect_response': <String, Object?>{
                  'result': <String, Object?>{
                    'assumptions': <Object?>[
                      <String, Object?>{
                        'id': 'assumption_stale',
                        'statement': 'Rates stay high',
                        'days_since_verify': kKnowledgeAssumptionStaleDays,
                      },
                      <String, Object?>{
                        'id': 'assumption_fresh',
                        'statement': 'Demand holds',
                        'days_since_verify': 3,
                      },
                    ],
                  },
                },
              },
            ],
          },
        },
        now: DateTime.utc(2026, 6, 29),
        traceId: 'trace-parser-1',
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.traceId, 'trace-parser-1');
      expect(snapshot.dueReviews.single.id, 'decision_1');
      expect(snapshot.staleAssumptions, hasLength(2));
      expect(
        snapshot.staleAssumptions
            .firstWhere((item) => item.id == 'assumption_stale')
            .daysSinceVerify,
        kKnowledgeAssumptionStaleDays,
      );
    });

    test('returns null for malformed tool output', () {
      final snapshot = reviewDueSnapshotFromTerminalStep(
        const <String, Object?>{
          'status': 'completed',
          'output': <String, Object?>{'effect_results': <Object?>[]},
        },
        now: DateTime.utc(2026, 6, 29),
      );

      expect(snapshot, isNull);
    });
  });

  group('FrbReviewDueReader', () {
    test('reads review inputs through a two-step FRB effect loop', () async {
      final dispatcher = _ReviewDispatcher();
      final bridge = FakeAgentRuntimeEffectPlanBridge();
      final traces = <AgentRuntimeNativeStepRunResult>[];
      final reader = FrbReviewDueReader(
        runtime: _runtime(
          bridge: bridge,
          dispatcher: dispatcher,
          recordTrace: (stepRun) async => traces.add(stepRun),
        ),
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.dueReviews.single.question, 'Revisit portfolio hedge?');
      expect(snapshot.traceId, 'agent-runtime:knowledge_review:run_1');
      expect(
        snapshot.staleAssumptions
            .firstWhere((item) => item.id == 'assumption_stale')
            .statement,
        'Rates stay high',
      );
      expect(dispatcher.calls.map((c) => c.name), <String>[
        'list_due_reviews',
        'list_open_assumptions',
      ]);
      expect(
        dispatcher.calls.first.input,
        containsPair('as_of', '2026-06-29T08:00:00.000Z'),
      );
      expect(bridge.startRequests.single.agentId, kKnowledgeReviewAgentId);
      expect(
        bridge.startRequests.single.request['metadata'],
        containsPair('surface', 'knowledge_review'),
      );
      expect(traces.single.terminalStep['status'], 'completed');
      expect(traces.single.dispatchedEffectCount, 2);
    });

    test('falls back when the FRB path fails', () async {
      final fallback = _FallbackReader(
        const ReviewDueSnapshot(
          dueReviews: <ReviewDecisionItem>[
            ReviewDecisionItem(id: 'fallback_decision', question: 'Fallback?'),
          ],
          staleAssumptions: <ReviewAssumptionItem>[],
        ),
      );
      final reader = FrbReviewDueReader(
        runtime: _runtime(
          bridge: FailingAgentRuntimeEffectPlanBridge(),
          dispatcher: _ReviewDispatcher(),
        ),
        fallback: fallback,
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.dueReviews.single.id, 'fallback_decision');
      expect(fallback.calls, 1);
    });

    test('run persists fallback artifact when the FRB path fails', () async {
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
      final fallback = _FallbackReader(
        const ReviewDueSnapshot(
          dueReviews: <ReviewDecisionItem>[
            ReviewDecisionItem(id: 'fallback_decision', question: 'Fallback?'),
          ],
          staleAssumptions: <ReviewAssumptionItem>[
            ReviewAssumptionItem(
              id: 'fallback_assumption',
              statement: 'Fallback assumption',
            ),
          ],
        ),
      );
      final agent = ReviewAgent(
        dueReader: FrbReviewDueReader(
          runtime: _runtime(
            bridge: FailingAgentRuntimeEffectPlanBridge(),
            dispatcher: _ReviewDispatcher(),
          ),
          fallback: fallback,
        ),
      );

      final result = await _runAgent(
        container,
        agent,
        DateTime.utc(2026, 7, 5, 9),
      );

      expect(result.status, AgentRunStatus.completed);
      expect(fallback.calls, 1);
      final artifact = await artifactStore.read(result.artifactId!);
      final outcomeFailures = evaluateAgentOutcomeCase(
        regressionCase: agentOutcomeRegressionCaseById(
          'knowledge.review.tool_failure_fallback',
        ),
        result: result,
        artifact: artifact,
      );
      expect(outcomeFailures, isEmpty, reason: outcomeFailures.join('\n'));
    });

    test(
      'ignores trace recording failures after a successful FRB read',
      () async {
        final fallback = _FallbackReader(
          const ReviewDueSnapshot(
            dueReviews: <ReviewDecisionItem>[
              ReviewDecisionItem(
                id: 'fallback_decision',
                question: 'Fallback?',
              ),
            ],
            staleAssumptions: <ReviewAssumptionItem>[],
          ),
        );
        final reader = FrbReviewDueReader(
          runtime: _runtime(
            bridge: FakeAgentRuntimeEffectPlanBridge(),
            dispatcher: _ReviewDispatcher(),
            recordTrace: (_) async =>
                throw StateError('trace store unavailable'),
          ),
          fallback: fallback,
        );

        final snapshot = await reader.read(_context());

        expect(snapshot.dueReviews.single.question, 'Revisit portfolio hedge?');
        expect(
          snapshot.staleAssumptions
              .firstWhere((item) => item.id == 'assumption_stale')
              .statement,
          'Rates stay high',
        );
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

AgentRuntimeEffectPlanBinding _runtime({
  required AgentRuntimeExecutionBridge bridge,
  required DeviceToolDispatcher dispatcher,
  Future<void> Function(AgentRuntimeNativeStepRunResult stepRun)? recordTrace,
}) {
  return agentRuntimeEffectPlanTestBinding(
    agentId: kKnowledgeReviewAgentId,
    domain: 'knowledge',
    surface: 'knowledge_review',
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
        id: kKnowledgeReviewAgentId,
        name: 'Weekly Review',
        version: '0.1.0',
        schedule: AgentRuntimeScheduleSpec.interval(everySeconds: 604800),
        capabilities: <String>['scheduled_agent'],
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
    ],
    tools: const <AgentRuntimeToolSpec>[
      AgentRuntimeToolSpec(
        name: 'list_due_reviews',
        description: 'List due reviews',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        replayPolicy: 'safe_retry',
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
      AgentRuntimeToolSpec(
        name: 'list_open_assumptions',
        description: 'List open assumptions',
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

class _ReviewDispatcher implements DeviceToolDispatcher {
  final calls = <AgentRuntimeEffectPlanToolEffect>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(AgentRuntimeEffectPlanToolEffect(name, input));
    return switch (name) {
      'list_due_reviews' => <String, Object?>{
        'decisions': <Object?>[
          <String, Object?>{
            'id': 'decision_1',
            'question': 'Revisit portfolio hedge?',
            'status': 'active',
          },
        ],
      },
      'list_open_assumptions' => <String, Object?>{
        'assumptions': <Object?>[
          <String, Object?>{
            'id': 'assumption_stale',
            'statement': 'Rates stay high',
            'days_since_verify': kKnowledgeAssumptionStaleDays + 1,
          },
          <String, Object?>{
            'id': 'assumption_fresh',
            'statement': 'Demand holds',
            'days_since_verify': 7,
          },
        ],
      },
      _ => throw StateError('unexpected tool $name'),
    };
  }
}

class _FallbackReader implements ReviewDueReader {
  _FallbackReader(this.result);

  final ReviewDueSnapshot result;
  var calls = 0;

  @override
  Future<ReviewDueSnapshot> read(AgentContext ctx) async {
    calls += 1;
    return result;
  }
}

Future<AgentRunResult> _runAgent(
  ProviderContainer container,
  ReviewAgent agent,
  DateTime now,
) {
  final probe = FutureProvider<AgentRunResult>(
    (ref) => agent.run(AgentContext(ref: ref, now: now)),
  );
  container.listen(probe, (_, _) {});
  return container.read(probe.future);
}

class _FixedReviewDueReader implements ReviewDueReader {
  const _FixedReviewDueReader(this.snapshot);

  final ReviewDueSnapshot snapshot;

  @override
  Future<ReviewDueSnapshot> read(AgentContext ctx) async => snapshot;
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
