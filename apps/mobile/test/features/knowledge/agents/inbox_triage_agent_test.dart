/// Unit-tests for [InboxTriageAgent] + its [InboxTriageClassifier] seam
/// (`docs/knowledgeos-domain.md` §7 + §14.2).
///
/// Two layers are covered:
///
/// 1. [LlmInboxTriageClassifier] in isolation — driven by a
///    [_FakeDeviceLlmClient] returning scripted Anthropic-shaped `content`
///    blocks. Covers the happy path (all three proposal kinds), the
///    confidence gate, and the silent degradation to the heuristic on
///    every failure mode (throw / timeout / malformed JSON).
/// 2. The agent end-to-end against an in-memory Drift DB — exercising the
///    classifier seam, the per-run cap ([kInboxTriageMaxNotesPerRun]),
///    the dismissed-kind protection, and the no-LLM == heuristic parity
///    (the heuristic produces identical proposals whether the agent runs
///    with the heuristic classifier or with an LLM client that fails).
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_client.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/llm_stream_event.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/knowledge/agents/inbox_triage_agent.dart';
import 'package:naviwealth/features/knowledge/data/inbox_triage_classifier.dart';
import 'package:naviwealth/features/knowledge/data/inbox_triage_repository.dart';
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

// ---------------------------------------------------------------------------
// Fake DeviceLlmClient (same shape as llm_capture_classifier_test.dart).
// ---------------------------------------------------------------------------

class _FakeConfig implements DeviceLlmConfig {
  const _FakeConfig();
  @override
  String get model => 'test-model';
}

class _FakeDeviceLlmClient implements DeviceLlmClient {
  _FakeDeviceLlmClient({required this.behavior});
  final _Behavior behavior;
  int calls = 0;

  @override
  DeviceLlmConfig get config => const _FakeConfig();

  @override
  Stream<LlmStreamEvent> streamMessages(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<AnthropicCompletion> complete(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    return behavior.run();
  }
}

abstract class _Behavior {
  Future<AnthropicCompletion> run();
}

class _ReturnsText extends _Behavior {
  _ReturnsText(this.text);
  final String text;
  @override
  Future<AnthropicCompletion> run() async => AnthropicCompletion(
    content: <Object?>[
      <String, Object?>{'type': 'text', 'text': text},
    ],
  );
}

class _Throws extends _Behavior {
  _Throws(this.error);
  final Object error;
  @override
  Future<AnthropicCompletion> run() async => throw error;
}

class _Hangs extends _Behavior {
  @override
  Future<AnthropicCompletion> run() => Completer<AnthropicCompletion>().future;
}

void main() {
  group('LlmInboxTriageClassifier', () {
    test('parses all three proposal kinds from one JSON envelope', () async {
      final fake = _FakeDeviceLlmClient(
        behavior: _ReturnsText('''
{
  "classification": {"kind":"decision_candidate","confidence":0.82,
                     "reason_zh":"在权衡两个方案"},
  "tags": {"tags":["fire","options"],"confidence":0.75,"reason_zh":"含期权/FIRE"},
  "link_to_decision": {"decision_ids":["dec1"],"confidence":0.7,
                       "reason_zh":"与该决策相关"}
}'''),
      );
      final c = LlmInboxTriageClassifier(client: fake);
      final note = _note(id: 'n1', title: 'QQQ vs BOXX', body: '该不该升级对冲?');
      final out = await c.triage(note, [
        _decision(id: 'dec1', question: '该不该升级动态对冲?'),
      ]);

      expect(fake.calls, 1, reason: '≤ 1 round-trip per note');
      expect(out, hasLength(3));
      final byKind = {for (final p in out) p.kind: p};
      expect(
        byKind[InboxProposalKind.classification]!.payload['kind'],
        'decision_candidate',
      );
      expect(
        byKind[InboxProposalKind.tags]!.payload['tags'],
        containsAll(<String>['fire', 'options']),
      );
      expect(
        byKind[InboxProposalKind.linkToDecision]!
            .payload['related_decision_ids'],
        <String>['dec1'],
      );
    });

    test('drops proposals below the 0.6 confidence gate', () async {
      final fake = _FakeDeviceLlmClient(
        behavior: _ReturnsText('''
{
  "classification": {"kind":"concept_candidate","confidence":0.4,"reason_zh":"勉强"},
  "tags": {"tags":["fire"],"confidence":0.55,"reason_zh":"勉强"},
  "link_to_decision": null
}'''),
      );
      final c = LlmInboxTriageClassifier(client: fake);
      final out = await c.triage(
        _note(id: 'n1', title: 't', body: 'b'),
        const [],
      );
      expect(out, isEmpty, reason: 'both < 0.6 → dropped, no fallback noise');
    });

    test('an empty (but well-formed) verdict yields no proposals', () async {
      final fake = _FakeDeviceLlmClient(
        behavior: _ReturnsText(
          '{"classification":null,"tags":null,"link_to_decision":null}',
        ),
      );
      final c = LlmInboxTriageClassifier(client: fake);
      // Note that the heuristic WOULD propose a concept for (short body),
      // proving the empty LLM verdict suppresses heuristic noise.
      final out = await c.triage(
        _note(id: 'n1', title: 'X', body: 'short'),
        const [],
      );
      expect(out, isEmpty);
    });

    test('ignores hallucinated decision ids (not in candidate set)', () async {
      final fake = _FakeDeviceLlmClient(
        behavior: _ReturnsText(
          '''
{"classification":null,"tags":null,
 "link_to_decision":{"decision_ids":["ghost"],"confidence":0.9,"reason_zh":"x"}}''',
        ),
      );
      final c = LlmInboxTriageClassifier(client: fake);
      final out = await c.triage(_note(id: 'n1', title: 't', body: 'b'), [
        _decision(id: 'dec1', question: 'real one'),
      ]);
      expect(out, isEmpty, reason: '"ghost" not in candidates → dropped');
    });

    test('respects already-tagged notes (no tag proposal)', () async {
      final fake = _FakeDeviceLlmClient(
        behavior: _ReturnsText('''
{"classification":null,
 "tags":{"tags":["fire"],"confidence":0.9,"reason_zh":"x"},
 "link_to_decision":null}'''),
      );
      final c = LlmInboxTriageClassifier(client: fake);
      final out = await c.triage(
        _note(id: 'n1', title: 't', body: 'b', tags: const ['existing']),
        const [],
      );
      expect(out, isEmpty, reason: 'user already tagged → skip tags');
    });

    group('silent fallback to heuristic', () {
      test('client throws → heuristic kicks in', () async {
        final fake = _FakeDeviceLlmClient(
          behavior: _Throws(
            const LlmRequestException(statusCode: 500, message: 'boom'),
          ),
        );
        final c = LlmInboxTriageClassifier(client: fake);
        // Short body + title with no question → heuristic concept_candidate.
        final out = await c.triage(
          _note(id: 'n1', title: 'edge-first', body: 'short def'),
          const [],
        );
        expect(out, hasLength(1));
        expect(out.single.payload['kind'], 'concept_candidate');
      });

      test('timeout → heuristic kicks in', () async {
        final fake = _FakeDeviceLlmClient(behavior: _Hangs());
        final c = LlmInboxTriageClassifier(
          client: fake,
          requestTimeout: const Duration(milliseconds: 50),
        );
        final out = await c.triage(
          _note(id: 'n1', title: 'edge-first', body: 'short def'),
          const [],
        );
        expect(out, hasLength(1));
        expect(out.single.payload['kind'], 'concept_candidate');
      });

      test('malformed JSON → heuristic kicks in', () async {
        final fake = _FakeDeviceLlmClient(
          behavior: _ReturnsText('I think this is a concept but no JSON.'),
        );
        final c = LlmInboxTriageClassifier(client: fake);
        final out = await c.triage(
          _note(id: 'n1', title: 'edge-first', body: 'short def'),
          const [],
        );
        expect(out, hasLength(1));
        expect(out.single.payload['kind'], 'concept_candidate');
      });
    });
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

    test('LLM path persists the proposals the classifier returned', () async {
      final c = container();
      await repo.upsertNote(
        _note(id: 'n1', title: 'QQQ vs BOXX', body: '该不该升级?'),
      );
      final fake = _FakeDeviceLlmClient(
        behavior: _ReturnsText('''
{"classification":{"kind":"decision_candidate","confidence":0.9,"reason_zh":"x"},
 "tags":null,"link_to_decision":null}'''),
      );
      final agent = InboxTriageAgent(
        classifier: LlmInboxTriageClassifier(client: fake),
      );

      final res = await runAgent(c, agent);
      expect(res.status, AgentRunStatus.completed);

      final rec = await triage.findForNote('n1');
      expect(rec, isNotNull);
      expect(rec!.proposals, hasLength(1));
      expect(rec.proposals.single.kind, InboxProposalKind.classification);
      expect(rec.proposals.single.payload['kind'], 'decision_candidate');
    });

    test('no-LLM path == heuristic path (parity)', () async {
      // Two identical notes; one agent runs the heuristic classifier
      // directly, the other runs an LLM client that always throws (so it
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

      // Reset and re-run with the failing LLM classifier.
      db = makeTestDatabase();
      repo = KnowledgeRepository(db: db, outbox: InMemoryOutboxStore());
      triage = InboxTriageRepository(db: db);
      final c2 = container();
      await repo.upsertNote(
        _note(id: 'n1', title: 'edge-first', body: 'short'),
      );
      final fallbackAgent = InboxTriageAgent(
        classifier: LlmInboxTriageClassifier(
          client: _FakeDeviceLlmClient(
            behavior: _Throws(
              const LlmRequestException(statusCode: 500, message: 'down'),
            ),
          ),
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
