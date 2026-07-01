/// Unit-tests for [ContradictionAgent] + its [ContradictionJudge] seam
/// (`docs/domains/knowledgeos-domain.md` §7 + §14.2 "ContradictionAgent cosine +
/// LLM judge 路径").
///
/// Covers:
/// - check-1 (assumption integrity) stays structural / deterministic —
///   it flags without ever consulting the judge;
/// - check-2 (principle drift) gates on the judge: a confirmed
///   contradiction flags with the LLM reason, a rejected mention or a
///   low-confidence verdict produces NO flag (the false-positive win);
/// - the cosine floor filters off-topic candidates before the judge;
/// - empty recall → the agent skips;
/// - the heuristic fallback + no-LLM provider parity;
/// - [FrbContradictionJudge] in isolation (parse / fallback paths).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime_step_runner.dart';
import 'package:naviwealth/app/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart'
    show memoryRuntimeProvider;
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/knowledge/agents/contradiction_agent.dart';
import 'package:naviwealth/features/knowledge/data/contradiction_judge.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_llm_client.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/llm_contradiction_judge.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _owner = 'u1';
final _now = DateTime.utc(2026, 5, 30, 12);
late SharedPreferences _prefs;

SyncMeta _meta() => SyncMeta(
  ownerUserId: _owner,
  updatedAt: _now,
  updatedByDevice: 'dev-test',
  hlc: Hlc.zero('dev-test'),
);

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Fake repository: only the three list methods the agent calls are
/// implemented; everything else routes through `noSuchMethod`.
class _FakeRepo implements KnowledgeRepository {
  _FakeRepo({
    this.decisions = const [],
    this.principles = const [],
    this.openAssumptions = const [],
  });

  final List<KnowledgeDecision> decisions;
  final List<KnowledgePrinciple> principles;
  final List<KnowledgeAssumption> openAssumptions;

  @override
  Future<List<KnowledgeDecision>> listDecisions({
    required String ownerUserId,
    Set<DecisionStatus>? statuses,
    int limit = 200,
    int offset = 0,
  }) async => decisions;

  @override
  Future<List<KnowledgePrinciple>> listActivePrinciples({
    required String ownerUserId,
  }) async => principles;

  @override
  Future<List<KnowledgeAssumption>> listOpenAssumptions({
    required String ownerUserId,
    double? confidenceMax,
  }) async => openAssumptions;

  // The agent never touches any other method.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// Fake runtime: serves canned recall hits per source and captures the
/// record the agent writes via `remember`.
class _FakeRuntime implements MemoryRuntime {
  _FakeRuntime(this.hitsBySource);

  /// `know:decisions` / `know:notes` → hits returned for any query.
  final Map<String, List<MemoryHit>> hitsBySource;
  MemoryRecord? remembered;

  @override
  Future<List<MemoryHit>> recall({
    required String ownerUserId,
    String? queryText,
    Set<String>? entityFilter,
    Set<MemoryKind>? kinds,
    String? scope,
    String? source,
    DateTime? validAt,
    int topK = 10,
    Duration recencyHalfLife = const Duration(days: 30),
  }) async {
    return hitsBySource[source] ?? const <MemoryHit>[];
  }

  @override
  Future<void> remember(MemoryRecord record) async {
    remembered = record;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// Programmable judge so each test pins the verdict for the candidate it
/// feeds in.
class _FixedJudge implements ContradictionJudge {
  _FixedJudge(this.verdict);
  final ContradictionVerdict verdict;
  int calls = 0;
  @override
  Future<ContradictionVerdict> judge({
    required String principleStatement,
    required String memoryText,
  }) async {
    calls++;
    return verdict;
  }
}

/// A judge that throws — proves check-1 never consults the judge.
class _ThrowingJudge implements ContradictionJudge {
  @override
  Future<ContradictionVerdict> judge({
    required String principleStatement,
    required String memoryText,
  }) async => throw StateError('boom');
}

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

KnowledgePrinciple _principle(String id, String statement) =>
    KnowledgePrinciple(
      id: id,
      statement: statement,
      rationaleMd: '',
      scope: '*',
      status: PrincipleStatus.active,
      declaredAt: _now,
      sync: _meta(),
    );

KnowledgeDecision _decision(
  String id, {
  required String question,
  List<String> assumptionIds = const [],
  DecisionStatus status = DecisionStatus.active,
  DateTime? decidedAt,
}) => KnowledgeDecision(
  id: id,
  question: question,
  options: const [],
  selectedLabel: '',
  rationaleMd: '',
  principleIds: const [],
  assumptionIds: assumptionIds,
  status: status,
  decidedAt: decidedAt ?? _now,
  sync: _meta(),
);

KnowledgeAssumption _assumption(String id, String statement) =>
    KnowledgeAssumption(
      id: id,
      statement: statement,
      confidence: 0.7,
      scope: '*',
      evidenceIds: const [],
      status: AssumptionStatus.active,
      declaredAt: _now,
      sync: _meta(),
    );

MemoryHit _hit(
  String sourceId,
  String title,
  String summary, {
  double cosine = 0.9,
}) => MemoryHit(
  record: MemoryRecord(
    id: 'know:decisions:episodic:$sourceId',
    kind: MemoryKind.episodic,
    ownerUserId: _owner,
    scope: '*',
    source: 'know:decisions',
    sourceId: sourceId,
    title: title,
    summary: summary,
    payload: const <String, Object?>{},
    entities: const <String>{},
    importance: 0.5,
    confidence: 0.85,
    createdAt: _now,
    updatedAt: _now,
  ),
  score: cosine,
  semanticSim: cosine,
  entityOverlap: 0.0,
  recency: 1.0,
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    _prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer makeContainer({
    required _FakeRepo repo,
    required _FakeRuntime runtime,
    bool heuristicProviderJudge = false,
  }) {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(_prefs),
        currentUserIdProvider.overrideWithValue(() async => _owner),
        knowledgeRepositoryProvider.overrideWith((ref) async => repo),
        memoryRuntimeProvider.overrideWith((ref) async => runtime),
        // The no-LLM provider path yields HeuristicContradictionJudge.
        // We pin that directly (rather than overriding deviceLlmClient to
        // null) so the test doesn't have to stand up the whole
        // llmCredentials provider graph — the agent still resolves the
        // judge via contradictionJudgeProvider, exercising the same
        // ctx.ref path the production no-LLM build takes.
        if (heuristicProviderJudge)
          contradictionJudgeProvider.overrideWith(
            (ref) async => const HeuristicContradictionJudge(),
          ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Run via a probe provider so `ctx.ref` is a real Riverpod Ref.
  Future<AgentRunResult> runAgent(ProviderContainer c, ContradictionAgent a) {
    final probe = FutureProvider<AgentRunResult>(
      (ref) => a.run(AgentContext(ref: ref, now: _now)),
    );
    c.listen(probe, (_, _) {});
    return c.read(probe.future);
  }

  test('check-1: active decision citing a falsified/retired assumption flags '
      '(no LLM involved)', () async {
    // a-stale is NOT in the open set -> invalidated. The judge throws to
    // prove check-1 never consults it.
    final repo = _FakeRepo(
      decisions: [
        _decision('d1', question: 'Hold NASDAQ?', assumptionIds: ['a-stale']),
      ],
      openAssumptions: [_assumption('a-open', 'Other still-open')],
    );
    final runtime = _FakeRuntime(const {});
    final container = makeContainer(repo: repo, runtime: runtime);

    final agent = ContradictionAgent(judgeOverride: _ThrowingJudge());
    final result = await runAgent(container, agent);

    expect(result.status, AgentRunStatus.completed);
    expect(result.payload['issue_count'], 1);
    final issues = runtime.remembered!.payload['issues']! as List<Object?>;
    final issue = issues.single! as Map<String, Object?>;
    expect(issue['kind'], 'assumption_invalidated');
    expect(issue['reference_id'], 'a-stale');
  });

  test('check-2: LLM judge confirms a real contradiction -> flag with the '
      'LLM reason', () async {
    final repo = _FakeRepo(principles: [_principle('p1', '长期持有,不做波段')]);
    final runtime = _FakeRuntime({
      'know:decisions': [_hit('d9', '是否频繁波段交易', '决定本月开始高频波段交易博取价差')],
    });
    final judge = _FixedJudge(
      const ContradictionVerdict(
        isContradiction: true,
        confidence: 0.92,
        reasonZh: '该决定主张频繁波段,与长期持有原则方向相反。',
      ),
    );
    final container = makeContainer(repo: repo, runtime: runtime);

    final agent = ContradictionAgent(judgeOverride: judge);
    final result = await runAgent(container, agent);

    expect(judge.calls, 1);
    expect(result.payload['issue_count'], 1);
    final issue =
        (runtime.remembered!.payload['issues']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(issue['kind'], 'principle_mismatch');
    expect(issue['reference_id'], 'p1');
    expect(issue['detail'], '该决定主张频繁波段,与长期持有原则方向相反。');
  });

  test('check-2: judge REJECTS a mere mention -> NO flag (false-positive '
      'suppression)', () async {
    final repo = _FakeRepo(principles: [_principle('p1', '长期持有,不做波段')]);
    final runtime = _FakeRuntime({
      'know:decisions': [
        // Mentions the principle verbatim but does not contradict it.
        _hit('d9', '复盘长期持有策略', '记录了长期持有不做波段的执行情况,一切正常'),
      ],
    });
    final judge = _FixedJudge(const ContradictionVerdict.none());
    final container = makeContainer(repo: repo, runtime: runtime);

    final agent = ContradictionAgent(judgeOverride: judge);
    final result = await runAgent(container, agent);

    expect(judge.calls, 1);
    expect(result.status, AgentRunStatus.skipped);
    expect(runtime.remembered, isNull);
  });

  test('check-2: low confidence (<0.6) -> no flag', () async {
    final repo = _FakeRepo(principles: [_principle('p1', '长期持有,不做波段')]);
    final runtime = _FakeRuntime({
      'know:decisions': [_hit('d9', 'q', '可能有点冲突但说不准')],
    });
    final judge = _FixedJudge(
      const ContradictionVerdict(
        isContradiction: true,
        confidence: 0.4,
        reasonZh: '不太确定',
      ),
    );
    final container = makeContainer(repo: repo, runtime: runtime);

    final agent = ContradictionAgent(judgeOverride: judge);
    final result = await runAgent(container, agent);

    expect(result.status, AgentRunStatus.skipped);
    expect(runtime.remembered, isNull);
  });

  test('candidate cosine floor: below-threshold hits are not judged', () async {
    final repo = _FakeRepo(principles: [_principle('p1', '长期持有,不做波段')]);
    // cosine 0.3 < _kCandidateCosineFloor (0.55) -> filtered before judge.
    final runtime = _FakeRuntime({
      'know:decisions': [_hit('d9', 'q', '高频波段', cosine: 0.3)],
    });
    final judge = _FixedJudge(
      const ContradictionVerdict(
        isContradiction: true,
        confidence: 0.99,
        reasonZh: 'should not be reached',
      ),
    );
    final container = makeContainer(repo: repo, runtime: runtime);

    final agent = ContradictionAgent(judgeOverride: judge);
    final result = await runAgent(container, agent);

    expect(judge.calls, 0);
    expect(result.status, AgentRunStatus.skipped);
  });

  test('no candidates (empty recall) -> agent skips', () async {
    final repo = _FakeRepo(principles: [_principle('p1', '长期持有')]);
    final runtime = _FakeRuntime(const {});
    final judge = _FixedJudge(const ContradictionVerdict.none());
    final container = makeContainer(repo: repo, runtime: runtime);

    final agent = ContradictionAgent(judgeOverride: judge);
    final result = await runAgent(container, agent);

    expect(judge.calls, 0);
    expect(result.status, AgentRunStatus.skipped);
    expect(result.summary, contains('No contradictions'));
  });

  group('FrbContradictionSourceReader', () {
    test('reads source rows through a three-step FRB tool plan', () async {
      final dispatcher = _ContradictionDispatcher();
      final bridge = _ToolPlanBridge();
      final traces = <AgentRuntimeNativeStepRunResult>[];
      final reader = FrbContradictionSourceReader(
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: bridge,
          toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
        ),
        catalog: _catalog(),
        recordTrace: (stepRun) async => traces.add(stepRun),
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.decisions.single.assumptionIds, <String>['a-frb']);
      expect(snapshot.principles.single.id, 'p-frb');
      expect(snapshot.openAssumptions.single.id, 'a-open');
      expect(dispatcher.calls.map((call) => call.name), <String>[
        'list_triage_decisions',
        'list_active_principles',
        'list_open_assumptions',
      ]);
      expect(
        bridge.startRequests.single.agentId,
        kKnowledgeContradictionAgentId,
      );
      expect(
        bridge.startRequests.single.request['metadata'],
        containsPair('surface', 'knowledge_contradiction'),
      );
      expect(traces.single.terminalStep['status'], 'completed');
      expect(traces.single.dispatchedToolCount, 3);
    });

    test('falls back when FRB source read fails', () async {
      final fallback = _FallbackSourceReader(
        ContradictionSourceSnapshot(
          decisions: <KnowledgeDecision>[
            _decision('fallback-decision', question: 'Fallback?'),
          ],
          principles: <KnowledgePrinciple>[
            _principle('fallback-principle', 'Fallback principle'),
          ],
          openAssumptions: <KnowledgeAssumption>[
            _assumption('fallback-assumption', 'Fallback assumption'),
          ],
        ),
      );
      final reader = FrbContradictionSourceReader(
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: _FailingBridge(),
          toolHost: AgentRuntimeToolHost(
            dispatcher: _ContradictionDispatcher(),
          ),
        ),
        catalog: _catalog(),
        fallback: fallback,
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.decisions.single.id, 'fallback-decision');
      expect(snapshot.principles.single.id, 'fallback-principle');
      expect(snapshot.openAssumptions.single.id, 'fallback-assumption');
      expect(fallback.calls, 1);
    });
  });

  group('fallback / parity', () {
    test(
      'HeuristicContradictionJudge: marker token -> contradiction',
      () async {
        const judge = HeuristicContradictionJudge();
        final v = await judge.judge(
          principleStatement: '长期持有',
          memoryText: '这个决定违反了长期持有原则',
        );
        expect(v.isContradiction, isTrue);
        expect(v.confidence, greaterThanOrEqualTo(0.6));
      },
    );

    test('HeuristicContradictionJudge: no marker -> none', () async {
      const judge = HeuristicContradictionJudge();
      final v = await judge.judge(
        principleStatement: '长期持有',
        memoryText: '复盘了长期持有的执行情况,一切正常',
      );
      expect(v.isContradiction, isFalse);
    });

    test('no-LLM path == heuristic judge (provider parity)', () async {
      // No judge injected + no deviceLlmClient -> the agent resolves
      // contradictionJudgeProvider, which yields HeuristicContradictionJudge.
      // The recalled memory carries a marker token so the heuristic flags it.
      final repo = _FakeRepo(principles: [_principle('p1', '长期持有,不做波段')]);
      final runtime = _FakeRuntime({
        'know:decisions': [_hit('d9', 'q', '该决定违反了长期持有的原则')],
      });
      final container = makeContainer(
        repo: repo,
        runtime: runtime,
        heuristicProviderJudge: true,
      );

      const agent = ContradictionAgent(); // resolves provider
      final result = await runAgent(container, agent);

      expect(result.status, AgentRunStatus.completed);
      final issue =
          (runtime.remembered!.payload['issues']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(issue['kind'], 'principle_mismatch');
      expect(issue['detail'], contains('违反'));
    });

    test(
      'FrbContradictionJudge parses a genuine contradiction verdict',
      () async {
        final bridge = _FakeLlmBridge(
          responseText:
              '{"is_contradiction": true, "confidence": 0.9, '
              '"reason_zh": "方向相反"}',
        );
        final judge = FrbContradictionJudge(llmClient: bridge);

        final v = await judge.judge(
          principleStatement: '长期持有',
          memoryText: '决定开始高频波段',
        );

        expect(bridge.calls, 1);
        expect(bridge.lastMessages.first['role'], 'system');
        expect(bridge.lastMessages.last['role'], 'user');
        expect(bridge.lastMetadata['surface'], 'knowledge_contradiction');
        expect(v.isContradiction, isTrue);
        expect(v.reasonZh, '方向相反');
      },
    );

    test(
      'FrbContradictionJudge falls back to heuristic on malformed JSON',
      () async {
        final judge = FrbContradictionJudge(
          llmClient: _FakeLlmBridge(responseText: 'not json'),
        );

        final v = await judge.judge(
          principleStatement: '长期持有',
          memoryText: '该决定违反了长期持有',
        );

        expect(v.isContradiction, isTrue); // heuristic caught the marker
      },
    );

    test(
      'FrbContradictionJudge falls back when FRB completion throws',
      () async {
        final judge = FrbContradictionJudge(
          llmClient: _FakeLlmBridge(error: StateError('native unavailable')),
        );

        final v = await judge.judge(
          principleStatement: '长期持有',
          memoryText: '该决定违反了长期持有',
        );

        expect(v.isContradiction, isTrue);
        expect(v.reasonZh, contains('违反'));
      },
    );

    test(
      'FrbContradictionJudge drops a low-confidence positive verdict',
      () async {
        final judge = FrbContradictionJudge(
          llmClient: _FakeLlmBridge(
            responseText:
                '{"is_contradiction": true, "confidence": 0.3, '
                '"reason_zh": "不确定"}',
          ),
        );

        final v = await judge.judge(
          principleStatement: '长期持有',
          memoryText: '一些无关内容',
        );

        expect(v.isContradiction, isFalse);
      },
    );
  });
}

AgentContext _context() {
  final container = ProviderContainer(
    overrides: [currentUserIdProvider.overrideWithValue(() async => _owner)],
  );
  addTearDown(container.dispose);
  final ref = container.read(_refProvider);
  return AgentContext(ref: ref, now: _now);
}

final _refProvider = Provider<Ref>((ref) => ref);

AgentRuntimeCatalog _catalog() {
  return AgentRuntimeCatalog(
    generatedAt: _now,
    activeDomains: const <String>['knowledge'],
    agents: const <AgentRuntimeAgentSpec>[
      AgentRuntimeAgentSpec(
        id: kKnowledgeContradictionAgentId,
        name: 'Contradiction Check',
        version: '0.1.0',
        schedule: AgentRuntimeScheduleSpec.interval(everySeconds: 21600),
        capabilities: <String>['scheduled_agent'],
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
    ],
    tools: const <AgentRuntimeToolSpec>[
      AgentRuntimeToolSpec(
        name: 'list_triage_decisions',
        description: 'List triage decisions',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
      AgentRuntimeToolSpec(
        name: 'list_active_principles',
        description: 'List active principles',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
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

class _ContradictionDispatcher implements DeviceToolDispatcher {
  final calls = <_ToolCall>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(_ToolCall(name, input));
    return switch (name) {
      'list_triage_decisions' => <String, Object?>{
        'decisions': <Object?>[
          <String, Object?>{
            'id': 'd-frb',
            'question': 'Should I hold BOXX?',
            'selected': 'yes',
            'status': 'active',
            'principle_ids': const <String>['p-frb'],
            'assumption_ids': const <String>['a-frb'],
            'decided_at': _now.toIso8601String(),
          },
        ],
      },
      'list_active_principles' => <String, Object?>{
        'principles': <Object?>[
          <String, Object?>{
            'id': 'p-frb',
            'statement': '长期持有',
            'rationale_md': '',
            'scope': '*',
            'declared_at': _now.toIso8601String(),
          },
        ],
      },
      'list_open_assumptions' => <String, Object?>{
        'assumptions': <Object?>[
          <String, Object?>{
            'id': 'a-open',
            'statement': 'Open assumption',
            'confidence': 0.7,
            'scope': '*',
            'last_verified_at': _now.toIso8601String(),
          },
        ],
      },
      _ => throw StateError('unexpected tool $name'),
    };
  }
}

class _ToolPlanBridge implements AgentRuntimeNativeBridge {
  final startRequests = <_StartRequest>[];
  var _plan = const <Object?>[];
  var _next = 0;
  final _responses = <Map<String, Object?>>[];

  @override
  Future<String> protocolVersion() async => 'agent.v1';

  @override
  Future<String> catalogVersion() async => 'agent_catalog.v1';

  @override
  Future<Map<String, Object?>> catalogSummary(
    Map<String, Object?> catalog,
  ) async {
    return catalog;
  }

  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    startRequests.add(_StartRequest(request: request, agentId: agentId));
    final input = request['input']! as Map<String, Object?>;
    _plan = input['tool_plan']! as List<Object?>;
    _next = 0;
    _responses.clear();
    return _toolCallStep(agentId);
  }

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
    required String agentId,
  }) async {
    _responses.add(<String, Object?>{
      'tool_call': previousStep['tool_call'],
      'tool_response': toolResponse,
    });
    _next += 1;
    if (_next < _plan.length) return _toolCallStep(agentId);
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': previousStep['run_id'],
      'agent_id': agentId,
      'status': 'completed',
      'output': <String, Object?>{
        'mode': 'frb_tool_loop',
        'tool_results': _responses
            .map(
              (response) => <String, Object?>{
                'tool_call': response['tool_call'],
                'tool_response': response['tool_response'],
              },
            )
            .toList(growable: false),
      },
    };
  }

  Map<String, Object?> _toolCallStep(String agentId) {
    final item = _plan[_next]! as Map<String, Object?>;
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'run_id': 'run_1',
      'agent_id': agentId,
      'status': 'tool_call_requested',
      'tool_call': <String, Object?>{
        'tool_call_id': 'call_${_next + 1}',
        'name': item['name'],
        'input': item['input'],
      },
    };
  }

  @override
  Future<Map<String, Object?>> completeMockLlm({
    required Map<String, Object?> request,
    required String responseText,
  }) async {
    return const <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> completeProfileLlm({
    required Map<String, Object?> request,
  }) async {
    return const <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> startProfileTurnStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
  }) async {
    return const <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> validateLlmRequest(
    Map<String, Object?> request,
  ) async {
    return request;
  }

  @override
  Future<Map<String, Object?>> validateLlmResponse(
    Map<String, Object?> response,
  ) async {
    return response;
  }

  @override
  Future<Map<String, Object?>> validateRunRequest(
    Map<String, Object?> request,
  ) async {
    return request;
  }

  @override
  Future<Map<String, Object?>> validateToolSpec(
    Map<String, Object?> tool,
  ) async {
    return tool;
  }

  @override
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace) async {
    return trace;
  }
}

class _FailingBridge extends _ToolPlanBridge {
  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    throw StateError('native unavailable');
  }
}

class _FallbackSourceReader implements ContradictionSourceReader {
  _FallbackSourceReader(this.result);

  final ContradictionSourceSnapshot result;
  var calls = 0;

  @override
  Future<ContradictionSourceSnapshot> read(AgentContext ctx) async {
    calls += 1;
    return result;
  }
}

class _StartRequest {
  const _StartRequest({required this.request, required this.agentId});

  final Map<String, Object?> request;
  final String agentId;
}

class _ToolCall {
  const _ToolCall(this.name, this.input);

  final String name;
  final Object? input;
}

class _FakeLlmBridge implements KnowledgeLlmProfileClient {
  _FakeLlmBridge({this.responseText, this.error});

  final String? responseText;
  final Object? error;
  var calls = 0;
  List<Map<String, Object?>> lastMessages = const <Map<String, Object?>>[];
  Map<String, Object?> lastMetadata = const <String, Object?>{};

  @override
  Future<Map<String, Object?>> completeProfile({
    required List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    double? temperature,
    int? maxOutputTokens,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    calls += 1;
    lastMessages = messages;
    lastMetadata = metadata;
    final e = error;
    if (e != null) throw e;
    return <String, Object?>{
      'provider': 'mock',
      'model': 'test-model',
      'content': responseText ?? '',
    };
  }
}
