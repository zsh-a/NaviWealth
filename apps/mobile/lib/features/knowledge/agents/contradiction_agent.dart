/// `knowledge_contradiction` — value-alignment / fact-conflict agent
/// (`docs/knowledgeos-domain.md` §7).
///
/// Looks at every Decision authored in the last cadence window and
/// compares each against the user's active Principles + referenced
/// Assumptions. Two independent checks emit a `kind='semantic'` memory
/// (the Review tab + AI chat surface it; the underlying Decision is never
/// overwritten):
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
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../data/contradiction_judge.dart';
import '../data/knowledge_object_memory_indexers.dart'
    show kKnowledgeDecisionMemorySource, kKnowledgeNoteMemorySource;
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_agent_memory.dart';

const String kKnowledgeContradictionAgentId = 'knowledge_contradiction';
const String kKnowledgeContradictionMemorySource =
    'agent:knowledge_contradiction';

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
  const ContradictionAgent({this.judgeOverride});

  /// Test seam — when null the agent resolves the judge from
  /// [contradictionJudgeProvider] per run (the production path, same
  /// constraint as [InboxTriageAgent]: the agent list is sync-constructed
  /// but the LLM client is async).
  final ContradictionJudge? judgeOverride;

  @override
  String get id => kKnowledgeContradictionAgentId;

  @override
  String get name => 'Contradiction Check';

  /// §7 says "每次新 Decision / Note 落库". MVP fires on a 6-hour
  /// cadence; once `know:*` events land in `EventStore` this becomes
  /// an event-driven listener.
  @override
  AgentSchedule get schedule => AgentSchedule.everyHours(6);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final start = ctx.now;
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final ContradictionJudge activeJudge =
        judgeOverride ??
        await ctx.ref.read(contradictionJudgeProvider.future);

    final decisions = await repo.listDecisions(
      ownerUserId: ownerUserId,
      limit: 200,
    );
    final principles =
        await repo.listActivePrinciples(ownerUserId: ownerUserId);
    final openAssumptions =
        await repo.listOpenAssumptions(ownerUserId: ownerUserId);

    final issues = <_Contradiction>[];

    // ── Check 1: assumption integrity (structural, deterministic) ──
    // A still-active Decision that cites an assumption no longer in the
    // active set. This is a structural truth, not ambiguous text, so it
    // never touches the LLM judge. Scoped to recent decisions (last 90d).
    final window = start.subtract(const Duration(days: 90));
    final activeAssumptionIds = openAssumptions.map((a) => a.id).toSet();
    for (final d in decisions) {
      if (d.decidedAt.isBefore(window)) continue;
      if (d.status == DecisionStatus.superseded ||
          d.status == DecisionStatus.falsified) {
        continue;
      }
      for (final aid in d.assumptionIds) {
        if (activeAssumptionIds.contains(aid)) continue;
        issues.add(
          _Contradiction(
            decisionId: d.id,
            decisionQuestion: d.question,
            kind: 'assumption_invalidated',
            referenceId: aid,
            detail:
                '决策仍引用 assumption $aid,但该假设当前不在 active 集合(可能已 falsified/retired)。',
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
    if (issues.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kKnowledgeContradictionAgentId,
        startedAt: start,
        finishedAt: finished,
        reason: 'no contradictions detected in last 90d window',
      );
    }

    final firstIssue = issues.first;
    final summary = issues.length == 1
        ? '检出 1 处 ${firstIssue.kind}:${firstIssue.detail}'
        : '检出 ${issues.length} 处冲突,首条:${firstIssue.kind} → ${firstIssue.detail}';

    final built = buildAgentMemory(
      source: kKnowledgeContradictionMemorySource,
      kind: MemoryKind.semantic,
      ownerUserId: ownerUserId,
      start: start,
      finished: finished,
      title: 'Decision contradictions detected',
      summary: summary,
      payload: <String, Object?>{
        'issues': issues
            .map(
              (i) => <String, Object?>{
                'decision_id': i.decisionId,
                'decision_question': i.decisionQuestion,
                'kind': i.kind,
                'reference_id': i.referenceId,
                'detail': i.detail,
              },
            )
            .toList(growable: false),
      },
      entities: <String>{
        'knowledge_contradiction',
        ...issues.map((i) => i.decisionId),
      },
      importance: 0.7,
      confidence: 0.6,
    );
    await runtime.remember(built.record);

    return AgentRunResult(
      agentId: kKnowledgeContradictionAgentId,
      status: AgentRunStatus.completed,
      startedAt: start,
      finishedAt: finished,
      summary: summary,
      payload: <String, Object?>{'issue_count': issues.length},
      memoryId: built.memoryId,
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
            decisionId: cand.referenceId,
            decisionQuestion: cand.question,
            kind: 'principle_mismatch',
            referenceId: p.id,
            detail: verdict.reasonZh,
          ),
        );
      }
    }
    return out;
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

class _Contradiction {
  const _Contradiction({
    required this.decisionId,
    required this.decisionQuestion,
    required this.kind,
    required this.referenceId,
    required this.detail,
  });
  final String decisionId;
  final String decisionQuestion;
  final String kind;
  final String referenceId;
  final String detail;
}

/// A cosine-recalled candidate memory for check-2, pre-judge.
class _Candidate {
  const _Candidate({
    required this.referenceId,
    required this.question,
    required this.text,
    required this.cosine,
    required this.overlap,
  });
  final String referenceId;
  final String question;
  final String text;
  final double cosine;
  final double overlap;
}
