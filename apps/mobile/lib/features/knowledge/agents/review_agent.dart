/// `knowledge_review` — weekly review agent
/// (`docs/knowledgeos-domain.md` §7).
///
/// Runs Sunday 09:00 local. Pulls every Decision whose `review_date`
/// has passed and writes an episodic memory summarising "what needs
/// review this week". The Review tab in the IA shell reads the same
/// underlying repo, so the memory is a recall affordance for AI chat,
/// not a UI primary path.
library;

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../data/providers.dart';
import '_agent_memory.dart';

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
  AgentSchedule get schedule => const AgentSchedule(
    interval: Duration(days: 7),
    preferredHourLocal: 9,
  );

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final start = ctx.now;
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);

    final due = await repo.listDueReviews(
      ownerUserId: ownerUserId,
      asOf: start,
    );
    final finished = DateTime.now().toUtc();

    if (due.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kKnowledgeReviewAgentId,
        startedAt: start,
        finishedAt: finished,
        reason: 'no decisions due for review',
      );
    }

    final summary = _summarize(due.length, due.first.question);
    final built = buildAgentMemory(
      source: kKnowledgeReviewMemorySource,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      start: start,
      finished: finished,
      title: '本周 Decision 复盘',
      summary: summary,
      payload: <String, Object?>{
        'context': 'weekly review tick at ${start.toUtc().toIso8601String()}',
        'due_decision_ids': due.map((d) => d.id).toList(growable: false),
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
      payload: <String, Object?>{'due_count': due.length},
      memoryId: built.memoryId,
    );
  }

  String _summarize(int count, String firstQuestion) {
    if (count == 1) {
      return '1 个 decision 到期可复盘:$firstQuestion';
    }
    return '$count 个 decision 到期可复盘,首条:$firstQuestion';
  }
}
