/// `knowledge_contradiction` — value-alignment / fact-conflict agent
/// (`docs/domains/knowledgeos-domain.md` §7).
///
/// Looks at every Decision authored in the last cadence window and
/// compares each against the user's active Principles + referenced
/// Assumptions. Two independent checks emit a transient Agent Artifact and
/// durable finding identity; the underlying Decision is never overwritten.
///
/// - **Check 1 — assumption integrity (structural, deterministic).** A
///   still-active Decision that cites an assumption no longer in the
///   active set is a *structural* truth, not ambiguous text — so it stays
///   a pure deterministic check, no LLM, no judge.
/// - **Check 2 — principle ↔ recent-memory drift (cosine + LLM judge).**
///   Upgraded 2026-05-30 from a verbatim `contains` heuristic. For each
///   active Principle we recall the most semantically-similar recent
///   memories (`know:decisions` / `know:notes`, EmbeddingGemma cosine,
///   token-overlap re-rank — the same hybrid `find_similar_knowledge`
///   uses) so paraphrased drift is found, not just literal restatements.
///   Each bounded top-K candidate is then routed through a
///   [ContradictionJudge]: the LLM judge confirms genuine value/fact
///   drift (≥ 0.6 confidence) vs. a mere mention/restatement — the latter
///   produces NO flag, which is the false-positive-suppression win. The
///   judge degrades silently to the marker heuristic when no LLM is
///   configured or the round-trip fails, so the no-LLM path stays
///   deterministic.
library;

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_presentation.dart';
import '../../../core/ai/agents/agent_finding_store.dart';
import '../../../core/ai/agents/agent_intents.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_terminal_output.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/contradiction_judge.dart';
import '../data/knowledge_object_memory_indexers.dart'
    show kKnowledgeDecisionMemorySource, kKnowledgeNoteMemorySource;
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_agent_l10n.dart';

part 'contradiction_agent_models.dart';
part 'contradiction_agent_source_reader.dart';

const String kKnowledgeContradictionAgentId = 'knowledge_contradiction';

/// How many cosine-nearest recent memories to consider per Principle
/// before the LLM judge. Small so the per-run LLM call count stays cheap
/// (principles × K). 4 covers the realistic "this principle clashes with
/// a recent decision" case without ballooning cost.
const int _kCandidatesPerPrinciple = 4;

/// Cosine floor for a memory to count as a candidate. Below this the two
/// texts are not even on-topic, so judging them only burns tokens. Looser
/// than `find_similar`'s 0.82 dedupe bar because a *contradiction* lives
/// where the topics overlap but the stance differs — not at near-identity.
const double _kCandidateCosineFloor = 0.55;

class ContradictionAgent implements Agent {
  const ContradictionAgent({
    this.judgeOverride,
    this.sourceReader = const RepositoryContradictionSourceReader(),
  });

  /// Test seam — when null the agent resolves the judge from
  /// [contradictionJudgeProvider] per run (the production path, same
  /// constraint as [InboxTriageAgent]: the agent list is sync-constructed
  /// but the LLM client is async).
  final ContradictionJudge? judgeOverride;
  final ContradictionSourceReader sourceReader;

  @override
  String get id => kKnowledgeContradictionAgentId;

  @override
  String get name => 'Contradiction Check';

  /// Periodic fallback. KnowledgeRepository also debounces Note, Decision,
  /// Principle, and Assumption writes into an immediate event-triggered run.
  @override
  AgentSchedule get schedule => AgentSchedule.everyHours(6);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final start = ctx.now;
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final l10n = knowledgeAgentL10n(ctx.ref);
    final ContradictionJudge activeJudge =
        judgeOverride ?? await ctx.ref.read(contradictionJudgeProvider.future);

    final source = await sourceReader.read(ctx);
    final decisions = source.decisions;
    final principles = source.principles;
    final openAssumptions = source.openAssumptions;

    final issues = <_Contradiction>[];

    // ── Check 1: assumption integrity (structural, deterministic) ──
    // A still-active Decision that cites an assumption no longer in the
    // active set. This is a structural truth, not ambiguous text, so it
    // never touches the LLM judge. All still-active Decisions remain in
    // scope: an old long-lived decision can become unsafe today when one of
    // its assumptions is invalidated.
    final activeAssumptionIds = openAssumptions.map((a) => a.id).toSet();
    for (final d in decisions) {
      if (d.status == DecisionStatus.superseded ||
          d.status == DecisionStatus.falsified) {
        continue;
      }
      for (final aid in d.assumptionIds) {
        if (activeAssumptionIds.contains(aid)) continue;
        issues.add(
          _Contradiction(
            findingId: _findingId(
              kind: 'assumption_invalidated',
              referenceId: aid,
              subjectKind: KnowledgeEntryKind.decision.name,
              subjectId: d.id,
            ),
            subjectKind: KnowledgeEntryKind.decision.name,
            decisionId: d.id,
            decisionQuestion: d.question,
            kind: 'assumption_invalidated',
            referenceId: aid,
            detail: l10n.knowledgeAgentContradictionInvalidatedAssumption(aid),
            confidence: 1,
          ),
        );
      }
    }

    // ── Check 2: principle ↔ recent-memory drift (cosine + LLM judge) ──
    // For each active Principle, recall the cosine-nearest recent
    // memories (decisions + notes mirrored under `know:*`), re-rank by
    // token overlap, bound to top-K, then ask the judge whether each is a
    // genuine contradiction. The LLM judge rejecting a mere mention is
    // the false-positive-suppression win over the old `contains` + marker
    // heuristic. Falls back to the marker heuristic with no LLM.
    issues.addAll(
      await _principleDriftIssues(
        runtime: runtime,
        judge: activeJudge,
        ownerUserId: ownerUserId,
        principles: principles,
      ),
    );

    final finished = DateTime.now().toUtc();
    final findingStore = await ctx.ref.read(
      agent_providers.agentFindingStoreProvider.future,
    );
    await findingStore.reconcile(
      ownerUserId: ownerUserId,
      agentId: kKnowledgeContradictionAgentId,
      observedAt: finished,
      findings: <AgentFinding>[
        for (final issue in issues)
          AgentFinding(
            id: issue.findingId,
            ownerUserId: ownerUserId,
            agentId: kKnowledgeContradictionAgentId,
            domain: 'knowledge',
            kind: issue.kind,
            severity: issue.kind == 'assumption_invalidated'
                ? AgentArtifactSeverity.warning
                : AgentArtifactSeverity.attention,
            confidence: issue.confidence,
            payload: <String, Object?>{
              'subject_kind': issue.subjectKind,
              'subject_id': issue.decisionId,
              'subject_label': issue.decisionQuestion,
              'reference_id': issue.referenceId,
              'detail': issue.detail,
            },
          ),
      ],
    );
    if (issues.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kKnowledgeContradictionAgentId,
        startedAt: start,
        finishedAt: finished,
        reason: l10n.knowledgeAgentContradictionNone,
        traceId: source.traceId,
      );
    }

    final firstIssue = issues.first;
    final summary = issues.length == 1
        ? l10n.knowledgeAgentContradictionSummaryOne(
            firstIssue.detail,
            firstIssue.kind,
          )
        : l10n.knowledgeAgentContradictionSummaryMany(
            issues.length,
            firstIssue.detail,
            firstIssue.kind,
          );

    final dayKey = AppFormatters.utcDayKey(start);
    final artifactId = '$kKnowledgeContradictionAgentId:$dayKey';
    final artifactStore = await ctx.ref.read(
      agent_providers.agentArtifactStoreProvider.future,
    );
    await artifactStore.save(
      _buildArtifact(
        id: artifactId,
        ownerUserId: ownerUserId,
        createdAt: finished,
        summary: summary,
        issues: issues,
        traceId: source.traceId,
        l10n: l10n,
      ),
    );

    return AgentRunResult(
      agentId: kKnowledgeContradictionAgentId,
      status: AgentRunStatus.completed,
      startedAt: start,
      finishedAt: finished,
      summary: summary,
      payload: <String, Object?>{
        'issue_count': issues.length,
        'issues': <Object?>[
          for (final issue in issues)
            <String, Object?>{
              'finding_id': issue.findingId,
              'subject_kind': issue.subjectKind,
              'subject_id': issue.decisionId,
              'kind': issue.kind,
              'reference_id': issue.referenceId,
              'detail': issue.detail,
              'confidence': issue.confidence,
              if (issue.semanticSimilarity != null)
                'semantic_similarity': issue.semanticSimilarity,
              if (issue.tokenOverlap != null)
                'token_overlap': issue.tokenOverlap,
            },
        ],
        if (source.traceId != null) 'trace_id': source.traceId,
      },
      artifactId: artifactId,
      traceId: source.traceId,
    );
  }

  AgentArtifact _buildArtifact({
    required String id,
    required String ownerUserId,
    required DateTime createdAt,
    required String summary,
    required List<_Contradiction> issues,
    required String? traceId,
    required AppLocalizations l10n,
  }) {
    final structural = issues
        .where((issue) => issue.kind == 'assumption_invalidated')
        .toList(growable: false);
    final principle = issues
        .where((issue) => issue.kind == 'principle_mismatch')
        .toList(growable: false);
    return AgentArtifact(
      id: id,
      ownerUserId: ownerUserId,
      agentId: kKnowledgeContradictionAgentId,
      domain: 'knowledge',
      kind: AgentArtifactKind.alert,
      severity: AgentArtifactSeverity.warning,
      title: l10n.knowledgeAgentContradictionArtifactTitle,
      summary: summary,
      metrics: <AgentMetric>[
        AgentMetric(
          label: l10n.knowledgeAgentContradictionInsightInvalidatedTitle,
          value: structural.length.toString(),
          severity: structural.isEmpty ? null : AgentArtifactSeverity.warning,
        ),
        AgentMetric(
          label: l10n.knowledgeAgentContradictionInsightPrincipleTitle,
          value: principle.length.toString(),
          severity: principle.isEmpty ? null : AgentArtifactSeverity.attention,
        ),
      ],
      insights: <AgentInsight>[
        if (structural.isNotEmpty)
          AgentInsight(
            id: structural.first.findingId,
            title: l10n.knowledgeAgentContradictionInsightInvalidatedTitle,
            body: l10n.knowledgeAgentContradictionInsightInvalidatedBody(
              structural.length,
              structural.length == 1 ? '' : 's',
            ),
            severity: AgentArtifactSeverity.warning,
            evidenceIds: <String>[
              for (final item in structural) item.decisionId,
            ],
            route: KnowledgeRoutes.review,
            payload: <String, Object?>{
              'count': structural.length,
              'first_decision_id': structural.first.decisionId,
              'finding_ids': structural
                  .map((issue) => issue.findingId)
                  .toList(growable: false),
            },
          ),
        if (principle.isNotEmpty)
          AgentInsight(
            id: principle.first.findingId,
            title: l10n.knowledgeAgentContradictionInsightPrincipleTitle,
            body: l10n.knowledgeAgentContradictionInsightPrincipleBody(
              principle.length,
              principle.length == 1 ? '' : 's',
            ),
            severity: AgentArtifactSeverity.attention,
            evidenceIds: <String>[
              for (final item in principle) item.decisionId,
            ],
            route: KnowledgeRoutes.review,
            payload: <String, Object?>{
              'count': principle.length,
              'first_reference_id': principle.first.referenceId,
              'finding_ids': principle
                  .map((issue) => issue.findingId)
                  .toList(growable: false),
            },
          ),
      ],
      evidence: <AgentEvidenceRef>[
        for (final issue in issues)
          AgentEvidenceRef(
            type: 'knowledge_${issue.subjectKind}',
            id: issue.decisionId,
            label: issue.decisionQuestion,
            route: issue.subjectKind == KnowledgeEntryKind.decision.name
                ? KnowledgeRoutes.decision(issue.decisionId)
                : KnowledgeRoutes.object(issue.subjectKind, issue.decisionId),
            payload: <String, Object?>{
              'finding_id': issue.findingId,
              'kind': issue.kind,
              'reference_id': issue.referenceId,
              'detail': issue.detail,
              'confidence': issue.confidence,
              if (issue.semanticSimilarity != null)
                'semantic_similarity': issue.semanticSimilarity,
              if (issue.tokenOverlap != null)
                'token_overlap': issue.tokenOverlap,
            },
          ),
      ],
      actions: <AgentAction>[
        AgentAction(
          kind: 'open_object',
          label: l10n.knowledgeAgentContradictionAction,
          intent: kKnowledgeReviewDueItemsIntent,
          objectType: kAgentArtifactObjectType,
          objectId: id,
          route: KnowledgeRoutes.review,
        ),
      ],
      methodology: localAgentMethodology(
        l10n,
        sourceLabel: l10n.knowledgeAgentContradictionArtifactTitle,
        modelAssisted: traceId != null,
      ),
      traceId: traceId,
      createdAt: createdAt.toUtc(),
      expiresAt: createdAt.toUtc().add(const Duration(days: 14)),
    );
  }

  /// Cosine pre-filter + judge for check-2. Reuses the
  /// `find_similar_knowledge` hybrid (EmbeddingGemma cosine, token-overlap
  /// tie-break) to find candidate memories per Principle, bounds them to
  /// [_kCandidatesPerPrinciple], then routes each through [judge].
  Future<List<_Contradiction>> _principleDriftIssues({
    required MemoryRuntime runtime,
    required ContradictionJudge judge,
    required String ownerUserId,
    required List<KnowledgePrinciple> principles,
  }) async {
    final out = <_Contradiction>[];
    // Recall against the recent decisions + notes that were mirrored into
    // memory by the `know:*` indexers (§15.2). Other knowledge types are
    // not "recent activity" in the §7 sense, so we scope to these two.
    // Source strings come from the indexer catalogue (they're plural,
    // e.g. `know:decisions`) so a future rename stays in one place.
    const sources = <String>[
      kKnowledgeDecisionMemorySource,
      kKnowledgeNoteMemorySource,
    ];

    for (final p in principles) {
      final statement = p.statement.trim();
      if (statement.isEmpty) continue;
      final queryTokens = _tokenize(statement);

      // Gather + de-dup cosine candidates across the two sources.
      final scored = <_Candidate>[];
      final seen = <String>{};
      for (final source in sources) {
        final List<MemoryHit> hits = await runtime.recall(
          ownerUserId: ownerUserId,
          queryText: statement,
          source: source,
          topK: _kCandidatesPerPrinciple * 2,
        );
        for (final h in hits) {
          final cosine = h.semanticSim ?? 0.0;
          if (cosine < _kCandidateCosineFloor) continue;
          final record = h.record;
          final sourceId = record.sourceId;
          final dedupKey = sourceId ?? record.id;
          if (!seen.add('$source:$dedupKey')) continue;
          final text = '${record.title} ${record.summary}'.trim();
          if (text.isEmpty) continue;
          final overlap = _tokenOverlap(queryTokens, _tokenize(text));
          scored.add(
            _Candidate(
              referenceId: sourceId ?? record.id,
              subjectKind: source == kKnowledgeNoteMemorySource
                  ? KnowledgeEntryKind.note.name
                  : KnowledgeEntryKind.decision.name,
              question: record.title,
              text: text,
              cosine: cosine,
              overlap: overlap,
            ),
          );
        }
      }

      // Re-rank: cosine first, token overlap as the tie-break (a literal
      // near-match wins) — same ordering as find_similar_knowledge.
      scored.sort((a, b) {
        final c = b.cosine.compareTo(a.cosine);
        if (c != 0) return c;
        return b.overlap.compareTo(a.overlap);
      });

      for (final cand in scored.take(_kCandidatesPerPrinciple)) {
        final verdict = await judge.judge(
          principleStatement: statement,
          memoryText: cand.text,
        );
        if (!verdict.isContradiction || verdict.confidence < 0.6) continue;
        out.add(
          _Contradiction(
            findingId: _findingId(
              kind: 'principle_mismatch',
              referenceId: p.id,
              subjectKind: cand.subjectKind,
              subjectId: cand.referenceId,
            ),
            subjectKind: cand.subjectKind,
            decisionId: cand.referenceId,
            decisionQuestion: cand.question,
            kind: 'principle_mismatch',
            referenceId: p.id,
            detail: verdict.reasonZh,
            confidence: verdict.confidence,
            semanticSimilarity: cand.cosine,
            tokenOverlap: cand.overlap,
          ),
        );
      }
    }
    return out;
  }

  static String _findingId({
    required String kind,
    required String referenceId,
    required String subjectKind,
    required String subjectId,
  }) {
    String part(String value) => Uri.encodeComponent(value);
    return 'knowledge_finding:${part(kind)}:${part(referenceId)}:'
        '${part(subjectKind)}:${part(subjectId)}';
  }

  /// Lowercased word/CJK-bigram token set. Mirrors
  /// `find_similar_knowledge`'s tokenizer so the re-rank behaves the same.
  static Set<String> _tokenize(String s) {
    final lower = s.toLowerCase();
    final tokens = <String>{};
    for (final word in lower.split(RegExp(r'[^a-z0-9一-鿿]+'))) {
      if (word.isEmpty) continue;
      if (RegExp(r'[一-鿿]').hasMatch(word)) {
        if (word.length == 1) {
          tokens.add(word);
        } else {
          for (var i = 0; i < word.length - 1; i++) {
            tokens.add(word.substring(i, i + 2));
          }
        }
      } else {
        tokens.add(word);
      }
    }
    return tokens;
  }

  /// Jaccard overlap of two token sets, 0 when either is empty.
  static double _tokenOverlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final inter = a.where(b.contains).length;
    final union = (<String>{...a, ...b}).length;
    return union == 0 ? 0 : inter / union;
  }
}
