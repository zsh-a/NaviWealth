import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/context_pack_memory.dart';
import 'package:naviwealth/core/ai/contracts/event_record.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/ai/contracts/source_identity.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/context_builder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_answer_quality_eval.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';

import '../../../../core/persistence/test_database.dart';

const _owner = 'quality-user';
final _now = DateTime.utc(2026, 7, 1);

MemoryRecord _memory({
  required String id,
  required MemoryKind kind,
  required String scope,
  required String summary,
  Set<String> entities = const <String>{},
  DateTime? validUntil,
}) => MemoryRecord(
  id: id,
  kind: kind,
  ownerUserId: _owner,
  title: id,
  summary: summary,
  payload: const <String, Object?>{},
  entities: entities,
  scope: scope,
  importance: 0.9,
  confidence: 0.95,
  createdAt: DateTime.utc(2026, 6, 1),
  updatedAt: DateTime.utc(2026, 6, 20),
  validUntil: validUntil,
);

const _corpus = <MemoryAnswerQualityCase>[
  MemoryAnswerQualityCase(
    id: 'options-before-earnings',
    question: 'Should I keep the NVDA short put through earnings?',
    intent: ContextIntent(
      freeText: 'NVDA short put earnings decision',
      entities: {'NVDA'},
      scope: 'options_trading',
    ),
    requiredFacts: [
      'close before earnings',
      'cap loss at 20%',
      'NVDA put was reduced',
    ],
    forbiddenFacts: ['hold through earnings'],
    expectedEvidenceIds: {
      'options-rule',
      'options-decision',
      'event-nvda-reduced',
    },
    forbiddenEvidenceIds: {'options-stale'},
  ),
  MemoryAnswerQualityCase(
    id: 'fire-surplus',
    question: 'Can I reduce this month’s FIRE contribution?',
    intent: ContextIntent(
      freeText: 'FIRE contribution and emergency reserve',
      entities: {'FIRE'},
      scope: 'fire',
    ),
    requiredFacts: ['12-month emergency reserve', 'protect planned surplus'],
    forbiddenFacts: ['6-month reserve'],
    expectedEvidenceIds: {'fire-preference', 'fire-rule'},
    forbiddenEvidenceIds: {'unrelated-options'},
  ),
];

void main() {
  test(
    'fixed questions pass on required facts and expected evidence',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final runtime = MemoryRuntime(
        embedder: StubEmbedder(),
        memoryStore: SqliteMemoryStore(db: db),
        eventStore: SqliteEventStore(db: db),
        clock: () => _now,
      );
      final builder = ContextBuilder(runtime: runtime);

      await runtime.remember(
        _memory(
          id: 'options-rule',
          kind: MemoryKind.procedural,
          scope: 'options_trading',
          summary: 'Close before earnings and cap loss at 20%.',
          entities: const {'NVDA'},
        ),
      );
      await runtime.remember(
        _memory(
          id: 'options-decision',
          kind: MemoryKind.episodic,
          scope: 'options_trading',
          summary: 'The prior NVDA put was reduced after risk increased.',
          entities: const {'NVDA'},
        ),
      );
      await runtime.remember(
        _memory(
          id: 'options-stale',
          kind: MemoryKind.episodic,
          scope: 'options_trading',
          summary: 'Old guidance said to hold through earnings.',
          entities: const {'NVDA'},
          validUntil: DateTime.utc(2026, 5, 1),
        ),
      );
      await runtime.recordEvent(
        EventRecord(
          id: 'event-nvda-reduced',
          domain: DomainScope.finance,
          kind: EventKind.domain(DomainScope.finance, 'position_reduced'),
          occurredAt: DateTime.utc(2026, 6, 28),
          observedAt: DateTime.utc(2026, 6, 28),
          sourceIdentity: const SourceIdentity(
            domain: DomainScope.finance,
            rowFamily: 'fin:options_trade_journal',
            rowId: 'nvda-reduced',
            fingerprint: 'fixture-nvda-reduced',
          ),
          ownerUserId: _owner,
          summary: 'NVDA put was reduced.',
          facts: const <String, Object?>{},
          entities: const {'NVDA'},
        ),
      );
      await runtime.remember(
        _memory(
          id: 'fire-preference',
          kind: MemoryKind.semantic,
          scope: 'fire',
          summary: 'Keep a 12-month emergency reserve.',
          entities: const {'FIRE'},
        ),
      );
      await runtime.remember(
        _memory(
          id: 'fire-rule',
          kind: MemoryKind.procedural,
          scope: 'fire',
          summary: 'Protect planned surplus before discretionary spending.',
          entities: const {'FIRE'},
        ),
      );
      await runtime.remember(
        _memory(
          id: 'unrelated-options',
          kind: MemoryKind.semantic,
          scope: 'options_trading',
          summary: 'Unrelated options preference.',
          entities: const {'NVDA'},
        ),
      );

      final answers = <String, String>{
        'options-before-earnings': 'Close before earnings. Cap loss at 20%. The prior NVDA put was reduced.',
        'fire-surplus':
            'Keep the 12-month emergency reserve and protect planned surplus.',
      };
      final results = <String, MemoryAnswerQualityResult>{};
      for (final evalCase in _corpus) {
        final context = await builder.build(
          ownerUserId: _owner,
          intent: evalCase.intent,
        );
        final result = scoreMemoryAnswerQuality(
          evalCase: evalCase,
          answer: answers[evalCase.id]!,
          context: context,
        );
        results[evalCase.id] = result;
        expect(
          result.passed,
          isTrue,
          reason:
              '${evalCase.id}: score=${result.score}, '
              'missingFacts=${result.missingFacts}, '
              'missingEvidence=${result.missingEvidenceIds}, '
              'forbiddenEvidence=${result.forbiddenEvidenceIdsFound}',
        );
      }
      final report = MemoryAnswerQualityReport.fromResults(results);
      // CI JSON reporters retain this privacy-safe aggregate without answers,
      // questions, facts, evidence ids, or retrieved user content.
      // ignore: avoid_print
      print('[memory-answer-quality] ${jsonEncode(report.toJson())}');
      expect(report.passed, isTrue);
      expect(report.forbiddenClaimFailures, 0);
      expect(report.forbiddenEvidenceFailures, 0);
      expect(
        report.toJson().keys,
        unorderedEquals(<String>{
          'case_count',
          'passed_case_count',
          'pass_rate',
          'forbidden_claim_failures',
          'forbidden_evidence_failures',
          'missing_fact_failures',
          'missing_evidence_failures',
          'failed_case_ids',
          'passed',
        }),
      );
    },
  );

  test('stale claim and missing evidence fail with deterministic reasons', () {
    final evalCase = _corpus.first;
    const empty = ContextPackMemory(
      userPreferences: [],
      recentEvents: [],
      relatedDecisions: [],
      relatedEpisodes: [],
      derivedPatterns: [],
      derivedGuidance: [],
      applicableRules: [],
      relatedEvents: [],
    );
    final result = scoreMemoryAnswerQuality(
      evalCase: evalCase,
      answer: 'Hold through earnings.',
      context: empty,
    );

    expect(result.passed, isFalse);
    expect(result.missingFacts, hasLength(3));
    expect(result.forbiddenFactsFound, ['hold through earnings']);
    expect(result.missingEvidenceIds, evalCase.expectedEvidenceIds);
    expect(result.score, 0);
    final report = MemoryAnswerQualityReport.fromResults(
      <String, MemoryAnswerQualityResult>{evalCase.id: result},
    );
    expect(report.passed, isFalse);
    expect(report.forbiddenClaimFailures, 1);
    expect(report.forbiddenEvidenceFailures, 0);
    expect(report.failedCaseIds, <String>['options-before-earnings']);
    expect(
      jsonEncode(report.toJson()),
      isNot(contains('hold through earnings')),
    );
  });
}
