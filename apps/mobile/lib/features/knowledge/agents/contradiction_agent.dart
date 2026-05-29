/// `knowledge_contradiction` — value-alignment / fact-conflict agent
/// (`docs/knowledgeos-domain.md` §7).
///
/// Looks at every Decision authored in the last cadence window and
/// compares each against the user's active Principles + referenced
/// Assumptions. When a Decision's rationale contradicts an assumption
/// (status=falsified) or no longer aligns with an active Principle
/// (text match), a `kind='semantic'` memory is written so the Review
/// tab + AI chat both surface the conflict. Never overwrites the
/// underlying Decision.
///
/// MVP heuristic detection only — the §7 "cosine + LLM judge" path
/// arrives when the Memory indexer for `know:*` is wired and the LLM
/// runtime is configured.
library;

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_agent_memory.dart';

const String kKnowledgeContradictionAgentId = 'knowledge_contradiction';
const String kKnowledgeContradictionMemorySource =
    'agent:knowledge_contradiction';

class ContradictionAgent implements Agent {
  const ContradictionAgent();

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

    final decisions = await repo.listDecisions(
      ownerUserId: ownerUserId,
      limit: 200,
    );
    final principles =
        await repo.listActivePrinciples(ownerUserId: ownerUserId);
    final openAssumptions =
        await repo.listOpenAssumptions(ownerUserId: ownerUserId);

    final issues = <_Contradiction>[];

    // Scan window — recent decisions only, last 90d.
    final window = start.subtract(const Duration(days: 90));
    for (final d in decisions) {
      if (d.decidedAt.isBefore(window)) continue;
      if (d.status == DecisionStatus.superseded ||
          d.status == DecisionStatus.falsified) {
        continue;
      }
      // Principle mismatch — naïve textual: principle marked active
      // but rationale contains a literal "violates"/"counters"/"avoid"
      // alongside the principle's statement. Surface, don't auto-block.
      for (final p in principles) {
        final stmtLower = p.statement.toLowerCase();
        if (stmtLower.isEmpty) continue;
        final rationaleLower = d.rationaleMd.toLowerCase();
        if (!rationaleLower.contains(stmtLower)) continue;
        if (_anyContradictionToken(rationaleLower)) {
          issues.add(
            _Contradiction(
              decisionId: d.id,
              decisionQuestion: d.question,
              kind: 'principle_mismatch',
              referenceId: p.id,
              detail:
                  '决策 rationale 提到了 active principle "${p.statement}",但同时出现否定/规避词。',
            ),
          );
        }
      }
      // Assumption integrity — Decision cites assumptions that are no
      // longer in the active set (open list = active).
      final activeIds = openAssumptions.map((a) => a.id).toSet();
      for (final aid in d.assumptionIds) {
        if (activeIds.contains(aid)) continue;
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

  static bool _anyContradictionToken(String text) {
    const tokens = <String>['违反', '冲突', 'counter', 'violate', 'avoid', '规避'];
    for (final t in tokens) {
      if (text.contains(t)) return true;
    }
    return false;
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
