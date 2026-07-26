/// `knowledge_assumption` — monthly assumption agent
/// (`docs/domains/knowledgeos-domain.md` §7).
///
/// Fires monthly (or sooner if a cross-domain event tickles it; the
/// MVP keeps the cadence interval-based — event-driven invalidation
/// arrives once the indexer wires `know:*` events). Surfaces every
/// active assumption that hasn't been verified in > 90 days into the
/// Review tab via an episodic memory.
library;

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_presentation.dart';
import '../../../core/ai/agents/agent_intents.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_terminal_output.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_agent_l10n.dart';
import '_agent_memory.dart';

const String kKnowledgeAssumptionAgentId = 'knowledge_assumption';
const String kKnowledgeAssumptionMemorySource = 'agent:knowledge_assumption';

/// Threshold beyond which an active assumption is considered "stale" —
/// surfaced into the Review tab so the user gets nudged to either
/// re-verify it or change its status.

class AssumptionAgent implements Agent {
  const AssumptionAgent({
    this.assumptionReader = const RepositoryAssumptionReviewReader(),
  });

  final AssumptionReviewReader assumptionReader;

  @override
  String get id => kKnowledgeAssumptionAgentId;

  @override
  String get name => 'Assumption Review';

  /// 月初。30d interval keeps cadence honest; no preferred hour so the
  /// agent fires whenever the runner ticks after the window opens.
  @override
  AgentSchedule get schedule =>
      const AgentSchedule(interval: Duration(days: 30));

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final start = ctx.now;
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final l10n = knowledgeAgentL10n(ctx.ref);

    final snapshot = await assumptionReader.listOpen(ctx);
    final open = snapshot.open;
    final stale = open
        .where((a) => a.daysSinceVerify >= kKnowledgeAssumptionStaleDays)
        .toList(growable: false);
    final finished = DateTime.now().toUtc();

    if (stale.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kKnowledgeAssumptionAgentId,
        startedAt: start,
        finishedAt: finished,
        reason: l10n.knowledgeAgentAssumptionNoStale,
        traceId: snapshot.traceId,
      );
    }

    final summary = _summarize(l10n, stale.length, stale.first.statement);
    final dayKey = AppFormatters.utcDayKey(start);
    final artifactId = '$kKnowledgeAssumptionAgentId:$dayKey';
    final built = buildAgentMemory(
      source: kKnowledgeAssumptionMemorySource,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      start: start,
      finished: finished,
      title: l10n.knowledgeAgentAssumptionTitle,
      summary: summary,
      payload: <String, Object?>{
        'stale_assumption_ids': stale.map((a) => a.id).toList(growable: false),
        'threshold_days': kKnowledgeAssumptionStaleDays,
        'artifact_id': artifactId,
        if (snapshot.traceId != null) 'trace_id': snapshot.traceId,
      },
      entities: <String>{'knowledge_assumption', 'assumption_review'},
      importance: 0.6,
      confidence: 0.9,
    );
    await runtime.remember(built.record);
    final artifactStore = await ctx.ref.read(
      agent_providers.agentArtifactStoreProvider.future,
    );
    await artifactStore.save(
      _buildArtifact(
        id: artifactId,
        ownerUserId: ownerUserId,
        createdAt: finished,
        summary: summary,
        memoryId: built.memoryId,
        stale: stale,
        traceId: snapshot.traceId,
        l10n: l10n,
      ),
    );

    return AgentRunResult(
      agentId: kKnowledgeAssumptionAgentId,
      status: AgentRunStatus.completed,
      startedAt: start,
      finishedAt: finished,
      summary: summary,
      payload: <String, Object?>{
        'stale_count': stale.length,
        if (snapshot.traceId != null) 'trace_id': snapshot.traceId,
      },
      memoryId: built.memoryId,
      artifactId: artifactId,
      traceId: snapshot.traceId,
    );
  }

  AgentArtifact _buildArtifact({
    required String id,
    required String ownerUserId,
    required DateTime createdAt,
    required String summary,
    required String memoryId,
    required List<AssumptionReviewItem> stale,
    required String? traceId,
    required AppLocalizations l10n,
  }) {
    return AgentArtifact(
      id: id,
      ownerUserId: ownerUserId,
      agentId: kKnowledgeAssumptionAgentId,
      domain: 'knowledge',
      kind: AgentArtifactKind.review,
      severity: AgentArtifactSeverity.attention,
      title: l10n.knowledgeAgentAssumptionArtifactTitle,
      summary: summary,
      metrics: <AgentMetric>[
        AgentMetric(
          label: l10n.knowledgeAgentAssumptionInsightTitle,
          value: stale.length.toString(),
          severity: AgentArtifactSeverity.attention,
        ),
      ],
      insights: <AgentInsight>[
        AgentInsight(
          id: 'stale_assumptions',
          title: l10n.knowledgeAgentAssumptionInsightTitle,
          body: l10n.knowledgeAgentAssumptionInsightBody(
            stale.length,
            stale.length == 1 ? '' : 's',
            kKnowledgeAssumptionStaleDays,
          ),
          severity: AgentArtifactSeverity.attention,
          evidenceIds: <String>[for (final item in stale) item.id],
          route: KnowledgeRoutes.review,
          payload: <String, Object?>{
            'count': stale.length,
            'threshold_days': kKnowledgeAssumptionStaleDays,
            'first_id': stale.first.id,
          },
        ),
      ],
      evidence: <AgentEvidenceRef>[
        for (final assumption in stale)
          AgentEvidenceRef(
            type: 'knowledge_assumption',
            id: assumption.id,
            label: assumption.statement,
            route: KnowledgeRoutes.object('assumption', assumption.id),
            payload: <String, Object?>{
              'reason': 'stale_assumption',
              'days_since_verify': assumption.daysSinceVerify,
            },
          ),
      ],
      actions: <AgentAction>[
        AgentAction(
          kind: 'open_object',
          label: l10n.knowledgeAgentAssumptionAction,
          intent: kKnowledgeReviewDueItemsIntent,
          objectType: kAgentArtifactObjectType,
          objectId: id,
          route: KnowledgeRoutes.review,
        ),
      ],
      methodology: localAgentMethodology(
        l10n,
        sourceLabel: l10n.knowledgeAgentAssumptionArtifactTitle,
      ),
      memoryId: memoryId,
      traceId: traceId,
      createdAt: createdAt.toUtc(),
      expiresAt: createdAt.toUtc().add(const Duration(days: 14)),
    );
  }

  String _summarize(AppLocalizations l10n, int count, String first) {
    if (count == 1) {
      return l10n.knowledgeAgentAssumptionSummaryOne(
        kKnowledgeAssumptionStaleDays,
        first,
      );
    }
    return l10n.knowledgeAgentAssumptionSummaryMany(
      count,
      kKnowledgeAssumptionStaleDays,
      first,
    );
  }
}

abstract class AssumptionReviewReader {
  Future<AssumptionReviewSnapshot> listOpen(AgentContext ctx);
}

class RepositoryAssumptionReviewReader implements AssumptionReviewReader {
  const RepositoryAssumptionReviewReader();

  @override
  Future<AssumptionReviewSnapshot> listOpen(AgentContext ctx) async {
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final open = await repo.listOpenAssumptions(ownerUserId: ownerUserId);
    return AssumptionReviewSnapshot(
      open: open
          .map((a) => AssumptionReviewItem.fromAssumption(a, now: ctx.now))
          .toList(growable: false),
    );
  }
}

class FrbAssumptionReviewReader implements AssumptionReviewReader {
  const FrbAssumptionReviewReader({
    required AgentRuntimeEffectPlanBinding runtime,
    this.fallback = const RepositoryAssumptionReviewReader(),
  }) : _runtime = runtime;

  final AgentRuntimeEffectPlanBinding _runtime;
  final AssumptionReviewReader fallback;

  @override
  Future<AssumptionReviewSnapshot> listOpen(AgentContext ctx) async {
    return _runtime.readFromEffectPlan(
      effectPlan: const <AgentRuntimeEffect>[
        AgentRuntimeEffect.tool(
          name: 'list_open_assumptions',
          input: <String, Object?>{'limit': 50},
        ),
      ],
      maxEffectSteps: 1,
      fallback: () => fallback.listOpen(ctx),
      decode: (stepRun) {
        final result = agentRuntimeTerminalEffectResultForTool(
          stepRun.terminalStep,
          'list_open_assumptions',
        );
        final items = assumptionReviewItemsFromToolResult(result);
        if (items == null) return null;
        return AssumptionReviewSnapshot(open: items, traceId: stepRun.traceId);
      },
    );
  }
}

class AssumptionReviewSnapshot {
  const AssumptionReviewSnapshot({required this.open, this.traceId});

  final List<AssumptionReviewItem> open;
  final String? traceId;
}

class AssumptionReviewItem {
  const AssumptionReviewItem({
    required this.id,
    required this.statement,
    required this.daysSinceVerify,
  });

  factory AssumptionReviewItem.fromAssumption(
    KnowledgeAssumption assumption, {
    required DateTime now,
  }) {
    return AssumptionReviewItem(
      id: assumption.id,
      statement: assumption.statement,
      daysSinceVerify: assumption.daysSinceVerify(now),
    );
  }

  final String id;
  final String statement;
  final int daysSinceVerify;
}

List<AssumptionReviewItem>? assumptionReviewItemsFromToolResult(
  Map<String, Object?>? result,
) {
  final rawAssumptions = result?['assumptions'];
  if (rawAssumptions is! List) return null;
  final items = <AssumptionReviewItem>[];
  for (final raw in rawAssumptions) {
    final assumption = _asObject(raw);
    final id = assumption?['id'];
    final statement = assumption?['statement'];
    final daysSinceVerify = assumption?['days_since_verify'];
    if (id is! String || statement is! String || daysSinceVerify is! num) {
      return null;
    }
    items.add(
      AssumptionReviewItem(
        id: id,
        statement: statement,
        daysSinceVerify: daysSinceVerify.toInt(),
      ),
    );
  }
  return items;
}

Map<String, Object?>? _asObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}
