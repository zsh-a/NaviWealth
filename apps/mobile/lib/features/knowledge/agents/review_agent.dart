/// `knowledge_review` — weekly review agent
/// (`docs/domains/knowledgeos-domain.md` §5 + §7).
///
/// Runs Sunday 09:00 local. Surfaces "what needs review this week" —
/// both Decisions whose `review_date` has passed **and** active
/// Assumptions left unverified past [kAssumptionStaleDays]. Writes one episodic
/// memory; the Review tab reads the same repo, so the memory is a recall
/// affordance for AI chat, not a UI primary path.
library;

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '_agent_l10n.dart';
import '_agent_memory.dart';
import 'assumption_agent.dart' show kAssumptionStaleDays;

const String kKnowledgeReviewAgentId = 'knowledge_review';
const String kKnowledgeReviewMemorySource = 'agent:knowledge_review';

class ReviewAgent implements Agent {
  const ReviewAgent();

  @override
  String get id => kKnowledgeReviewAgentId;

  @override
  String get name => 'Weekly Review';

  /// "每周日 09:00 local". MVP fires on daily ticks at hour 9 and
  /// the underlying [AgentSchedule] gate keeps the cadence at ≥ 7d.
  @override
  AgentSchedule get schedule =>
      const AgentSchedule(interval: Duration(days: 7), preferredHourLocal: 9);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final start = ctx.now;
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final l10n = knowledgeAgentL10n(ctx.ref);

    final due = await repo.listDueReviews(
      ownerUserId: ownerUserId,
      asOf: start,
    );
    final open = await repo.listOpenAssumptions(ownerUserId: ownerUserId);
    final staleAssumptions = open
        .where((a) => a.daysSinceVerify(start) >= kAssumptionStaleDays)
        .toList(growable: false);
    final finished = DateTime.now().toUtc();

    if (due.isEmpty && staleAssumptions.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kKnowledgeReviewAgentId,
        startedAt: start,
        finishedAt: finished,
        reason: l10n.knowledgeAgentReviewNothingDue,
      );
    }

    final summary = _summarize(
      l10n: l10n,
      dueCount: due.length,
      staleCount: staleAssumptions.length,
      firstDue: due.isNotEmpty ? due.first.question : null,
      firstStale: staleAssumptions.isNotEmpty
          ? staleAssumptions.first.statement
          : null,
    );
    final built = buildAgentMemory(
      source: kKnowledgeReviewMemorySource,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      start: start,
      finished: finished,
      title: l10n.knowledgeAgentReviewTitle,
      summary: summary,
      payload: <String, Object?>{
        'context': 'weekly review tick at ${start.toUtc().toIso8601String()}',
        'due_decision_ids': due.map((d) => d.id).toList(growable: false),
        'stale_assumption_ids': staleAssumptions
            .map((a) => a.id)
            .toList(growable: false),
        'assumption_threshold_days': kAssumptionStaleDays,
      },
      entities: <String>{'knowledge_review', 'weekly_review'},
      importance: 0.7,
      confidence: 0.95,
    );
    await runtime.remember(built.record);

    return AgentRunResult(
      agentId: kKnowledgeReviewAgentId,
      status: AgentRunStatus.completed,
      startedAt: start,
      finishedAt: finished,
      summary: summary,
      payload: <String, Object?>{
        'due_count': due.length,
        'stale_assumption_count': staleAssumptions.length,
      },
      memoryId: built.memoryId,
    );
  }

  String _summarize({
    required AppLocalizations l10n,
    required int dueCount,
    required int staleCount,
    String? firstDue,
    String? firstStale,
  }) {
    final parts = <String>[];
    if (dueCount > 0) {
      parts.add(
        dueCount == 1
            ? l10n.knowledgeAgentReviewDecisionOne(firstDue ?? '')
            : l10n.knowledgeAgentReviewDecisionMany(dueCount, firstDue ?? ''),
      );
    }
    if (staleCount > 0) {
      parts.add(
        staleCount == 1
            ? l10n.knowledgeAgentReviewAssumptionOne(
                kAssumptionStaleDays,
                firstStale ?? '',
              )
            : l10n.knowledgeAgentReviewAssumptionMany(
                staleCount,
                kAssumptionStaleDays,
                firstStale ?? '',
              ),
      );
    }
    return parts.join('；');
  }
}
