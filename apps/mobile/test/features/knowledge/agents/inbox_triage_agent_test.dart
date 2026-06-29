/// Unit-tests for [InboxTriageAgent] + its [InboxTriageClassifier] seam
/// (`docs/domains/knowledgeos-domain.md` §7 + §14.2).
///
/// Two layers are covered:
///
/// 1. [FrbInboxTriageClassifier] in isolation — driven by a fake FRB LLM
///    bridge returning scripted profile completion content. Covers the happy
///    path and fallback behavior.
/// 2. The agent end-to-end against an in-memory Drift DB — exercising the
///    classifier seam, the per-run cap ([kInboxTriageMaxNotesPerRun]),
///    the dismissed-kind protection, and the no-LLM == heuristic parity
///    (the heuristic produces identical proposals whether the agent runs
///    with the heuristic classifier or with an FRB completion that fails).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/agents/inbox_triage_agent.dart';
import 'package:naviwealth/features/knowledge/data/inbox_triage_classifier.dart';
import 'package:naviwealth/features/knowledge/data/inbox_triage_repository.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_llm_client.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/llm_inbox_triage_classifier.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

import '../../../core/persistence/test_database.dart';

const _owner = 'u-test';
final _created = DateTime.utc(2026, 1, 1);

SyncMeta _meta() => SyncMeta(
  ownerUserId: _owner,
  updatedAt: _created,
  updatedByDevice: 'dev-test',
  hlc: Hlc.zero('dev-test'),
);

KnowledgeNote _note({
  required String id,
  String title = '',
  String body = '',
  List<String> tags = const <String>[],
}) => KnowledgeNote(
  id: id,
  title: title,
  bodyMd: body,
  tags: tags,
  createdAt: _created,
  sync: _meta(),
);

KnowledgeDecision _decision({required String id, required String question}) =>
    KnowledgeDecision(
      id: id,
      question: question,
      options: const [],
      selectedLabel: '',
      rationaleMd: '',
      principleIds: const [],
      assumptionIds: const [],
      status: DecisionStatus.active,
      decidedAt: _created,
      sync: _meta(),
    );

class _FixedInboxTriageClassifier implements InboxTriageClassifier {
  const _FixedInboxTriageClassifier({required this.proposals});

  final List<InboxProposal> proposals;

  @override
  Future<List<InboxProposal>> triage(
    KnowledgeNote note,
    List<KnowledgeDecision> decisions,
  ) async {
    return proposals;
  }
}

void main() {
  group('FrbInboxTriageClassifier', () {
    test('parses all proposal kinds from FRB profile completion', () async {
      final bridge = _FakeLlmBridge(
        responseText: '''
{
  "classification": {"kind":"decision_candidate","confidence":0.82,
                     "reason_zh":"在权衡两个方案"},
  "tags": {"tags":["fire","options"],"confidence":0.75,"reason_zh":"含期权/FIRE"},
  "link_to_decision": {"decision_ids":["dec1"],"confidence":0.7,
                       "reason_zh":"与该决策相关"}
}''',
      );
      final c = FrbInboxTriageClassifier(llmClient: bridge);
      final note = _note(id: 'n1', title: 'QQQ vs BOXX', body: '该不该升级对冲?');

      final out = await c.triage(note, [
        _decision(id: 'dec1', question: '该不该升级动态对冲?'),
      ]);

      expect(bridge.calls, 1);
      expect(bridge.lastMessages.first['role'], 'system');
      expect(bridge.lastMessages.last['role'], 'user');
      expect(bridge.lastMetadata['surface'], 'knowledge_inbox_triage');
      expect(out, hasLength(3));
      final byKind = {for (final p in out) p.kind: p};
      expect(
        byKind[InboxProposalKind.classification]!.payload['kind'],
        'decision_candidate',
      );
      expect(
        byKind[InboxProposalKind.linkToDecision]!
            .payload['related_decision_ids'],
        <String>['dec1'],
      );
    });

    test('falls back to heuristic when FRB completion fails', () async {
      final bridge = _FakeLlmBridge(error: StateError('native unavailable'));
      final c = FrbInboxTriageClassifier(llmClient: bridge);

      final out = await c.triage(
        _note(id: 'n1', title: 'edge-first', body: 'short def'),
        const [],
      );

      expect(bridge.calls, 1);
      expect(out.single.kind, InboxProposalKind.classification);
      expect(out.single.payload['kind'], 'concept_candidate');
    });

    test('drops low-confidence proposals without heuristic noise', () async {
      final bridge = _FakeLlmBridge(
        responseText: '''
{
  "classification": {"kind":"concept_candidate","confidence":0.4,"reason_zh":"勉强"},
  "tags": {"tags":["fire"],"confidence":0.55,"reason_zh":"勉强"},
  "link_to_decision": null
}''',
      );
      final c = FrbInboxTriageClassifier(llmClient: bridge);

      final out = await c.triage(
        _note(id: 'n1', title: 't', body: 'b'),
        const [],
      );

      expect(out, isEmpty, reason: 'both < 0.6 -> dropped, no fallback noise');
    });

    test('well-formed empty verdict suppresses heuristic proposals', () async {
      final bridge = _FakeLlmBridge(
        responseText:
            '{"classification":null,"tags":null,"link_to_decision":null}',
      );
      final c = FrbInboxTriageClassifier(llmClient: bridge);

      final out = await c.triage(
        _note(id: 'n1', title: 'X', body: 'short'),
        const [],
      );

      expect(out, isEmpty);
    });

    test(
      'ignores hallucinated decision ids and already-tagged notes',
      () async {
        final bridge = _FakeLlmBridge(
          responseText: '''
{"classification":null,
 "tags":{"tags":["fire"],"confidence":0.9,"reason_zh":"x"},
 "link_to_decision":{"decision_ids":["ghost"],"confidence":0.9,"reason_zh":"x"}}''',
        );
        final c = FrbInboxTriageClassifier(llmClient: bridge);

        final out = await c.triage(
          _note(id: 'n1', title: 't', body: 'b', tags: const ['existing']),
          [_decision(id: 'dec1', question: 'real one')],
        );

        expect(out, isEmpty);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Agent end-to-end against an in-memory DB.
  // -------------------------------------------------------------------------

  group('InboxTriageAgent', () {
    late AppDatabase db;
    late KnowledgeRepository repo;
    late InboxTriageRepository triage;

    setUp(() {
      db = makeTestDatabase();
      repo = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
      triage = InboxTriageRepository(db: db);
    });
    tearDown(() async => db.close());

    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue(() async => _owner),
          knowledgeRepositoryProvider.overrideWith((ref) async => repo),
          inboxTriageRepositoryProvider.overrideWith((ref) async => triage),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<AgentRunResult> runAgent(
      ProviderContainer c,
      InboxTriageAgent agent,
    ) {
      final probe = FutureProvider<AgentRunResult>(
        (ref) => agent.run(AgentContext(ref: ref, now: _created)),
      );
      c.listen(probe, (_, _) {});
      return c.read(probe.future);
    }

    test('classifier seam persists returned proposals', () async {
      final c = container();
      await repo.upsertNote(
        _note(id: 'n1', title: 'QQQ vs BOXX', body: '该不该升级?'),
      );
      final agent = InboxTriageAgent(
        classifier: _FixedInboxTriageClassifier(
          proposals: <InboxProposal>[
            InboxProposal(
              kind: InboxProposalKind.classification,
              summaryZh: '看起来像在权衡某个选项 — 建议升级为 Decision draft',
              payload: const <String, Object?>{
                'note_id': 'n1',
                'kind': 'decision_candidate',
                'confidence': 0.9,
                'reason': 'x',
              },
              status: InboxProposalStatus.pending,
            ),
          ],
        ),
      );

      final res = await runAgent(c, agent);
      expect(res.status, AgentRunStatus.completed);

      final rec = await triage.findForNote('n1');
      expect(rec, isNotNull);
      expect(rec!.proposals, hasLength(1));
      expect(rec.proposals.single.kind, InboxProposalKind.classification);
      expect(rec.proposals.single.payload['kind'], 'decision_candidate');
    });

    test(
      'snooze hides pending proposals until due and stores feedback',
      () async {
        await triage.upsert(
          InboxTriageRecord(
            noteId: 'n1',
            ownerUserId: _owner,
            lastTriagedAt: _created,
            proposals: <InboxProposal>[
              InboxProposal(
                kind: InboxProposalKind.classification,
                summaryZh: 'old',
                payload: const <String, Object?>{'note_id': 'n1'},
                status: InboxProposalStatus.pending,
              ),
            ],
          ),
        );

        await triage.snooze(
          noteId: 'n1',
          kind: InboxProposalKind.classification,
          until: DateTime.now().toUtc().add(const Duration(days: 2)),
        );
        await triage.recordFeedback(
          noteId: 'n1',
          kind: InboxProposalKind.classification,
          feedback: InboxProposalFeedback.negative,
        );

        expect(await triage.listPending(ownerUserId: _owner), isEmpty);
        var rec = await triage.findForNote('n1');
        expect(rec!.proposals.single.feedback, InboxProposalFeedback.negative);

        await triage.snooze(
          noteId: 'n1',
          kind: InboxProposalKind.classification,
          until: DateTime.now().toUtc().subtract(const Duration(days: 1)),
        );
        final visible = await triage.listPending(ownerUserId: _owner);
        expect(visible, hasLength(1));
        rec = visible.single;
        expect(rec.pending.single.kind, InboxProposalKind.classification);
      },
    );

    test('no-LLM path == heuristic path (parity)', () async {
      // Two identical notes; one agent runs the heuristic classifier
      // directly, the other runs the FRB classifier with a failing bridge (so it
      // silently falls back to the heuristic). The persisted proposals
      // must match.
      final c = container();
      await repo.upsertNote(
        _note(id: 'n1', title: 'edge-first', body: 'short'),
      );

      const heuristicAgent = InboxTriageAgent(
        classifier: HeuristicInboxTriageClassifier(),
      );
      await runAgent(c, heuristicAgent);
      final heuristicRec = await triage.findForNote('n1');

      // Reset and re-run with the failing FRB classifier.
      db = makeTestDatabase();
      repo = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
      triage = InboxTriageRepository(db: db);
      final c2 = container();
      await repo.upsertNote(
        _note(id: 'n1', title: 'edge-first', body: 'short'),
      );
      final fallbackAgent = InboxTriageAgent(
        classifier: FrbInboxTriageClassifier(
          llmClient: _FakeLlmBridge(error: StateError('native unavailable')),
        ),
      );
      await runAgent(c2, fallbackAgent);
      final fallbackRec = await triage.findForNote('n1');

      expect(
        heuristicRec!.proposals.map((p) => p.kind),
        fallbackRec!.proposals.map((p) => p.kind),
      );
      expect(
        heuristicRec.proposals.single.payload['kind'],
        fallbackRec.proposals.single.payload['kind'],
      );
      expect(
        heuristicRec.proposals.single.payload['kind'],
        'concept_candidate',
      );
    });

    test('honours kInboxTriageMaxNotesPerRun', () async {
      final c = container();
      // One more than the cap; each is a short concept candidate so the
      // heuristic always emits exactly one proposal.
      for (var i = 0; i < kInboxTriageMaxNotesPerRun + 3; i++) {
        await repo.upsertNote(_note(id: 'n$i', title: 't$i', body: 'short'));
      }
      const agent = InboxTriageAgent(
        classifier: HeuristicInboxTriageClassifier(),
      );
      final res = await runAgent(c, agent);
      expect(res.payload['scanned_notes'], kInboxTriageMaxNotesPerRun);

      final triagedIds = await triage.triagedNoteIds(ownerUserId: _owner);
      expect(triagedIds, hasLength(kInboxTriageMaxNotesPerRun));
    });

    test('reads triage source through FRB tool plan', () async {
      final dispatcher = _InboxTriageDispatcher();
      final bridge = _ToolPlanBridge();
      final traces = <AgentRuntimeNativeStepRunResult>[];
      final reader = FrbInboxTriageSourceReader(
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: bridge,
          toolHost: AgentRuntimeToolHost(dispatcher: dispatcher),
        ),
        catalog: _catalog(),
        recordTrace: (stepRun) async => traces.add(stepRun),
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.untriagedNotes.single.id, 'n-frb');
      expect(snapshot.decisions.single.id, 'd-frb');
      expect(dispatcher.calls.map((call) => call.name), <String>[
        'list_inbox_triage_candidates',
        'list_triage_decisions',
      ]);
      expect(bridge.startRequests.single.agentId, kKnowledgeInboxTriageAgentId);
      expect(
        bridge.startRequests.single.request['metadata'],
        containsPair('surface', 'knowledge_inbox_triage'),
      );
      expect(traces.single.terminalStep['status'], 'completed');
      expect(traces.single.dispatchedToolCount, 2);
    });

    test('falls back when FRB triage source read fails', () async {
      final fallback = _FallbackSourceReader(
        InboxTriageSourceSnapshot(
          untriagedNotes: <KnowledgeNote>[
            _note(id: 'fallback-note', title: 'fallback', body: 'short'),
          ],
          decisions: <KnowledgeDecision>[
            _decision(id: 'fallback-decision', question: 'Fallback decision'),
          ],
        ),
      );
      final reader = FrbInboxTriageSourceReader(
        stepRunner: AgentRuntimeNativeStepRunner(
          bridge: _FailingBridge(),
          toolHost: AgentRuntimeToolHost(dispatcher: _InboxTriageDispatcher()),
        ),
        catalog: _catalog(),
        fallback: fallback,
      );

      final snapshot = await reader.read(_context());

      expect(snapshot.untriagedNotes.single.id, 'fallback-note');
      expect(snapshot.decisions.single.id, 'fallback-decision');
      expect(fallback.calls, 1);
    });

    test('does not re-propose a dismissed kind', () async {
      final c = container();
      await repo.upsertNote(
        _note(id: 'n1', title: 'edge-first', body: 'short'),
      );

      // Seed an existing record where the classification proposal was
      // dismissed by the user.
      await triage.upsert(
        InboxTriageRecord(
          noteId: 'n1',
          ownerUserId: _owner,
          lastTriagedAt: _created,
          proposals: <InboxProposal>[
            InboxProposal(
              kind: InboxProposalKind.classification,
              summaryZh: 'old',
              payload: const <String, Object?>{'note_id': 'n1'},
              status: InboxProposalStatus.dismissed,
            ),
          ],
        ),
      );

      // The note already has a triage row, so the agent skips it entirely
      // (triagedNoteIds contains it) — the dismissed verdict is preserved.
      const agent = InboxTriageAgent(
        classifier: HeuristicInboxTriageClassifier(),
      );
      final res = await runAgent(c, agent);
      expect(
        res.status,
        AgentRunStatus.skipped,
        reason: 'the only note is already triaged',
      );

      final rec = await triage.findForNote('n1');
      expect(
        rec!.proposals.single.status,
        InboxProposalStatus.dismissed,
        reason: 'dismissed verdict untouched',
      );
    });
  });
}

AgentContext _context() {
  final container = ProviderContainer(
    overrides: [currentUserIdProvider.overrideWithValue(() async => _owner)],
  );
  addTearDown(container.dispose);
  final ref = container.read(_refProvider);
  return AgentContext(ref: ref, now: _created);
}

final _refProvider = Provider<Ref>((ref) => ref);

AgentRuntimeCatalog _catalog() {
  return AgentRuntimeCatalog(
    generatedAt: _created,
    activeDomains: const <String>['knowledge'],
    agents: const <AgentRuntimeAgentSpec>[
      AgentRuntimeAgentSpec(
        id: kKnowledgeInboxTriageAgentId,
        name: 'Inbox Triage',
        version: '0.1.0',
        schedule: AgentRuntimeScheduleSpec.interval(everySeconds: 900),
        capabilities: <String>['scheduled_agent'],
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
    ],
    tools: const <AgentRuntimeToolSpec>[
      AgentRuntimeToolSpec(
        name: 'list_inbox_triage_candidates',
        description: 'List inbox triage candidates',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
      AgentRuntimeToolSpec(
        name: 'list_triage_decisions',
        description: 'List triage decisions',
        inputSchema: <String, Object?>{'type': 'object'},
        risk: 'read',
        metadata: <String, Object?>{'domain': 'knowledge'},
      ),
    ],
    proposalKinds: const <AgentRuntimeProposalKindSpec>[],
    promptBlocks: const <AgentRuntimePromptBlockSpec>[],
  );
}

class _InboxTriageDispatcher implements DeviceToolDispatcher {
  final calls = <_ToolCall>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    calls.add(_ToolCall(name, input));
    return switch (name) {
      'list_inbox_triage_candidates' => <String, Object?>{
        'notes': <Object?>[
          <String, Object?>{
            'id': 'n-frb',
            'title': 'QQQ vs BOXX',
            'body_md': '该不该升级?',
            'tags': const <String>[],
            'project_tag': null,
            'created_at': _created.toIso8601String(),
          },
        ],
      },
      'list_triage_decisions' => <String, Object?>{
        'decisions': <Object?>[
          <String, Object?>{
            'id': 'd-frb',
            'question': 'Should I hold BOXX?',
            'selected': 'yes',
            'status': 'active',
            'decided_at': _created.toIso8601String(),
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

class _FallbackSourceReader implements InboxTriageSourceReader {
  _FallbackSourceReader(this.result);

  final InboxTriageSourceSnapshot result;
  var calls = 0;

  @override
  Future<InboxTriageSourceSnapshot> read(AgentContext ctx) async {
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
