/// `knowledge_assumption` — monthly assumption agent
/// (`docs/knowledgeos-domain.md` §7).
///
/// Fires monthly (or sooner if a cross-domain event tickles it; the
/// MVP keeps the cadence interval-based — event-driven invalidation
/// arrives once the indexer wires `know:*` events). Surfaces every
/// active assumption that hasn't been verified in > 90 days into the
/// Review tab via an episodic memory.
library;

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../data/providers.dart';
import '_agent_memory.dart';

const String kKnowledgeAssumptionAgentId = 'knowledge_assumption';
const String kKnowledgeAssumptionMemorySource = 'agent:knowledge_assumption';

/// Threshold beyond which an active assumption is considered "stale" —
/// surfaced into the Review tab so the user gets nudged to either
/// re-verify it or change its status.
const int kAssumptionStaleDays = 90;

class AssumptionAgent implements Agent {
  const AssumptionAgent();

  @override
  String get id => kKnowledgeAssumptionAgentId;

  @override
  String get name => 'Assumption Review';

  /// 月初。30d interval keeps cadence honest; no preferred hour so the
  /// agent fires whenever the runner ticks after the window opens.
  @override
  AgentSchedule get schedule => const AgentSchedule(
    interval: Duration(days: 30),
  );

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final start = ctx.now;
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);

    final open = await repo.listOpenAssumptions(ownerUserId: ownerUserId);
    final stale = open
        .where((a) => a.daysSinceVerify(start) >= kAssumptionStaleDays)
        .toList(growable: false);
    final finished = DateTime.now().toUtc();

    if (stale.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kKnowledgeAssumptionAgentId,
        startedAt: start,
        finishedAt: finished,
        reason: 'no stale active assumptions',
      );
    }

    final summary = _summarize(stale.length, stale.first.statement);
    final built = buildAgentMemory(
      source: kKnowledgeAssumptionMemorySource,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      start: start,
      finished: finished,
      title: '本月待校验假设',
      summary: summary,
      payload: <String, Object?>{
        'stale_assumption_ids':
            stale.map((a) => a.id).toList(growable: false),
        'threshold_days': kAssumptionStaleDays,
      },
      entities: <String>{'knowledge_assumption', 'assumption_review'},
      importance: 0.6,
      confidence: 0.9,
    );
    await runtime.remember(built.record);

    return AgentRunResult(
      agentId: kKnowledgeAssumptionAgentId,
      status: AgentRunStatus.completed,
      startedAt: start,
      finishedAt: finished,
      summary: summary,
      payload: <String, Object?>{'stale_count': stale.length},
      memoryId: built.memoryId,
    );
  }

  String _summarize(int count, String first) {
    if (count == 1) return '1 条 active 假设 > $kAssumptionStaleDays 天未校验:$first';
    return '$count 条 active 假设 > $kAssumptionStaleDays 天未校验,首条:$first';
  }
}
