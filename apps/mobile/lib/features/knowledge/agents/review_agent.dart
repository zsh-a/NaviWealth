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
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_intents.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_terminal_output.dart';
import '../../../core/auth/current_user.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_agent_l10n.dart';
import '_agent_memory.dart';
import 'assumption_agent.dart' show kAssumptionStaleDays;

const String kKnowledgeReviewAgentId = 'knowledge_review';
const String kKnowledgeReviewMemorySource = 'agent:knowledge_review';

class ReviewAgent implements Agent {
  const ReviewAgent({this.dueReader = const RepositoryReviewDueReader()});

  final ReviewDueReader dueReader;

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
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final l10n = knowledgeAgentL10n(ctx.ref);

    final dueSnapshot = await dueReader.read(ctx);
    final due = dueSnapshot.dueReviews;
    final staleAssumptions = dueSnapshot.staleAssumptions;
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
        if (dueSnapshot.traceId != null) 'trace_id': dueSnapshot.traceId,
      },
      entities: <String>{'knowledge_review', 'weekly_review'},
      importance: 0.7,
      confidence: 0.95,
    );
    await runtime.remember(built.record);
    final artifactStore = await ctx.ref.read(
      agent_providers.agentArtifactStoreProvider.future,
    );
    final artifact = _buildArtifact(
      ownerUserId: ownerUserId,
      start: start,
      finished: finished,
      summary: summary,
      memoryId: built.memoryId,
      due: due,
      staleAssumptions: staleAssumptions,
      traceId: dueSnapshot.traceId,
    );
    await artifactStore.save(artifact);

    return AgentRunResult(
      agentId: kKnowledgeReviewAgentId,
      status: AgentRunStatus.completed,
      startedAt: start,
      finishedAt: finished,
      summary: summary,
      payload: <String, Object?>{
        'due_count': due.length,
        'stale_assumption_count': staleAssumptions.length,
        if (dueSnapshot.traceId != null) 'trace_id': dueSnapshot.traceId,
      },
      memoryId: built.memoryId,
      artifactId: artifact.id,
      traceId: dueSnapshot.traceId,
    );
  }

  AgentArtifact _buildArtifact({
    required String ownerUserId,
    required DateTime start,
    required DateTime finished,
    required String summary,
    required String memoryId,
    required List<ReviewDecisionItem> due,
    required List<ReviewAssumptionItem> staleAssumptions,
    required String? traceId,
  }) {
    final dayKey = start.toUtc().toIso8601String().substring(0, 10);
    final hasStaleAssumptions = staleAssumptions.isNotEmpty;
    final artifactId = '$kKnowledgeReviewAgentId:$dayKey';
    return AgentArtifact(
      id: artifactId,
      ownerUserId: ownerUserId,
      agentId: kKnowledgeReviewAgentId,
      domain: 'knowledge',
      kind: AgentArtifactKind.review,
      severity: hasStaleAssumptions
          ? AgentArtifactSeverity.attention
          : AgentArtifactSeverity.info,
      title: 'Weekly Knowledge Review',
      summary: summary,
      insights: <AgentInsight>[
        if (due.isNotEmpty)
          AgentInsight(
            title: 'Decisions due',
            body:
                '${due.length} decision review${due.length == 1 ? '' : 's'}'
                ' need attention.',
            severity: AgentArtifactSeverity.info,
            payload: <String, Object?>{
              'count': due.length,
              'first_id': due.first.id,
            },
          ),
        if (staleAssumptions.isNotEmpty)
          AgentInsight(
            title: 'Stale assumptions',
            body:
                '${staleAssumptions.length} assumption${staleAssumptions.length == 1 ? '' : 's'}'
                ' crossed the $kAssumptionStaleDays day verification window.',
            severity: AgentArtifactSeverity.attention,
            payload: <String, Object?>{
              'count': staleAssumptions.length,
              'threshold_days': kAssumptionStaleDays,
              'first_id': staleAssumptions.first.id,
            },
          ),
      ],
      evidence: <AgentEvidenceRef>[
        for (final decision in due)
          AgentEvidenceRef(
            type: 'knowledge_decision',
            id: decision.id,
            label: decision.question,
            payload: const <String, Object?>{'reason': 'review_due'},
          ),
        for (final assumption in staleAssumptions)
          AgentEvidenceRef(
            type: 'knowledge_assumption',
            id: assumption.id,
            label: assumption.statement,
            payload: const <String, Object?>{'reason': 'stale_assumption'},
          ),
      ],
      actions: <AgentAction>[
        AgentAction(
          kind: 'open_object',
          label: 'Review knowledge items',
          intent: kKnowledgeReviewDueItemsIntent,
          objectType: kAgentArtifactObjectType,
          objectId: artifactId,
        ),
      ],
      memoryId: memoryId,
      traceId: traceId,
      createdAt: finished.toUtc(),
      expiresAt: finished.toUtc().add(const Duration(days: 14)),
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

abstract class ReviewDueReader {
  Future<ReviewDueSnapshot> read(AgentContext ctx);
}

class RepositoryReviewDueReader implements ReviewDueReader {
  const RepositoryReviewDueReader();

  @override
  Future<ReviewDueSnapshot> read(AgentContext ctx) async {
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final due = await repo.listDueReviews(
      ownerUserId: ownerUserId,
      asOf: ctx.now,
    );
    final open = await repo.listOpenAssumptions(ownerUserId: ownerUserId);
    final staleAssumptions = open
        .where((a) => a.daysSinceVerify(ctx.now) >= kAssumptionStaleDays)
        .map(ReviewAssumptionItem.fromAssumption)
        .toList(growable: false);
    return ReviewDueSnapshot(
      dueReviews: due
          .map(ReviewDecisionItem.fromDecision)
          .toList(growable: false),
      staleAssumptions: staleAssumptions,
    );
  }
}

class FrbReviewDueReader implements ReviewDueReader {
  const FrbReviewDueReader({
    required AgentRuntimeEffectPlanBinding runtime,
    this.fallback = const RepositoryReviewDueReader(),
  }) : _runtime = runtime;

  final AgentRuntimeEffectPlanBinding _runtime;
  final ReviewDueReader fallback;

  @override
  Future<ReviewDueSnapshot> read(AgentContext ctx) async {
    final asOf = ctx.now.toUtc().toIso8601String();
    return _runtime.readFromEffectPlan(
      effectPlan: <AgentRuntimeEffect>[
        AgentRuntimeEffect.tool(
          name: 'list_due_reviews',
          input: <String, Object?>{'as_of': asOf, 'limit': 50},
        ),
        const AgentRuntimeEffect.tool(
          name: 'list_open_assumptions',
          input: <String, Object?>{'limit': 50},
        ),
      ],
      maxEffectSteps: 2,
      fallback: () => fallback.read(ctx),
      decode: (stepRun) => reviewDueSnapshotFromTerminalStep(
        stepRun.terminalStep,
        now: ctx.now,
        traceId: stepRun.traceId,
      ),
    );
  }
}

class ReviewDueSnapshot {
  const ReviewDueSnapshot({
    required this.dueReviews,
    required this.staleAssumptions,
    this.traceId,
  });

  final List<ReviewDecisionItem> dueReviews;
  final List<ReviewAssumptionItem> staleAssumptions;
  final String? traceId;
}

class ReviewDecisionItem {
  const ReviewDecisionItem({required this.id, required this.question});

  factory ReviewDecisionItem.fromDecision(KnowledgeDecision decision) {
    return ReviewDecisionItem(id: decision.id, question: decision.question);
  }

  final String id;
  final String question;
}

class ReviewAssumptionItem {
  const ReviewAssumptionItem({required this.id, required this.statement});

  factory ReviewAssumptionItem.fromAssumption(KnowledgeAssumption assumption) {
    return ReviewAssumptionItem(
      id: assumption.id,
      statement: assumption.statement,
    );
  }

  final String id;
  final String statement;
}

ReviewDueSnapshot? reviewDueSnapshotFromTerminalStep(
  Map<String, Object?> step, {
  required DateTime now,
  String? traceId,
}) {
  final byTool = agentRuntimeTerminalEffectResultsByToolName(step);
  final reviews = reviewDecisionItemsFromToolResult(byTool['list_due_reviews']);
  final openAssumptions = _reviewAssumptionItemsFromToolResult(
    byTool['list_open_assumptions'],
    now: now,
  );
  if (reviews == null || openAssumptions == null) return null;
  final staleAssumptions = openAssumptions
      .where((a) => a.daysSinceVerify >= kAssumptionStaleDays)
      .map((a) => ReviewAssumptionItem(id: a.id, statement: a.statement))
      .toList(growable: false);
  return ReviewDueSnapshot(
    dueReviews: reviews,
    staleAssumptions: staleAssumptions,
    traceId: traceId,
  );
}

List<ReviewDecisionItem>? reviewDecisionItemsFromToolResult(
  Map<String, Object?>? result,
) {
  final rawDecisions = result?['decisions'];
  if (rawDecisions is! List) return null;
  final items = <ReviewDecisionItem>[];
  for (final raw in rawDecisions) {
    final decision = _asObject(raw);
    final id = decision?['id'];
    final question = decision?['question'];
    if (id is! String || question is! String) return null;
    items.add(ReviewDecisionItem(id: id, question: question));
  }
  return items;
}

List<_ReviewOpenAssumptionItem>? _reviewAssumptionItemsFromToolResult(
  Map<String, Object?>? result, {
  required DateTime now,
}) {
  final rawAssumptions = result?['assumptions'];
  if (rawAssumptions is! List) return null;
  final items = <_ReviewOpenAssumptionItem>[];
  for (final raw in rawAssumptions) {
    final assumption = _asObject(raw);
    final id = assumption?['id'];
    final statement = assumption?['statement'];
    final daysSinceVerify = assumption?['days_since_verify'];
    if (id is! String || statement is! String || daysSinceVerify is! num) {
      return null;
    }
    items.add(
      _ReviewOpenAssumptionItem(
        id: id,
        statement: statement,
        daysSinceVerify: daysSinceVerify.toInt(),
      ),
    );
  }
  return items;
}

class _ReviewOpenAssumptionItem {
  const _ReviewOpenAssumptionItem({
    required this.id,
    required this.statement,
    required this.daysSinceVerify,
  });

  final String id;
  final String statement;
  final int daysSinceVerify;
}

Map<String, Object?>? _asObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}
