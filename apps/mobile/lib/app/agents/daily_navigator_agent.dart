/// App-owned cross-domain Agent that turns fresh deterministic Life signals
/// into one evidence-backed judgment and at most one review action.
library;

import '../../core/ai/agents/agent.dart';
import '../../core/ai/agents/agent_artifact.dart';
import '../../core/ai/agents/agent_artifact_store.dart';
import '../../core/ai/agents/agent_finding_store.dart';
import '../../core/ai/agents/agent_l10n.dart';
import '../../core/ai/agents/agent_schedule.dart';
import '../../core/ai/agents/providers.dart' as agent_providers;
import '../../core/ai/attention/attention.dart';
import '../../core/ai/attention/attention_store.dart';
import '../../core/ai/attention/providers.dart' as attention_providers;
import '../../core/auth/current_user.dart';
import '../../core/lifeos/life_context.dart';
import '../../core/notifications/notification_preferences.dart';
import '../../core/shell/entity_route_resolver.dart';
import '../../features/life/ui/life_event_l10n.dart';
import '../../l10n/gen/app_localizations.dart';
import '../life_context_composition.dart';
import 'daily_navigator_synthesizer.dart';

const String kDailyNavigatorAgentId = 'daily_navigator';
const String kDailyNavigatorFindingId = 'daily_navigator:primary';

class DailyNavigatorAgent implements Agent {
  const DailyNavigatorAgent({
    this.synthesizer = const ProgrammaticDailyNavigatorSynthesizer(),
    this.hourLocal = 7,
  });

  final DailyNavigatorSynthesizer synthesizer;
  final int hourLocal;

  @override
  String get id => kDailyNavigatorAgentId;

  @override
  String get name => 'Daily Navigator';

  @override
  AgentSchedule get schedule => AgentSchedule.daily(hourLocal: hourLocal);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final context = await ctx.ref.read(lifeContextSnapshotProvider.future);
    return synthesizeAndPersist(
      context: context,
      ownerUserId: ownerUserId,
      startedAt: ctx.now,
      finishedAt: DateTime.now().toUtc(),
      synthesizer: synthesizer,
      findingStore: await ctx.ref.read(
        agent_providers.agentFindingStoreProvider.future,
      ),
      attentionService: await ctx.ref.read(
        attention_providers.attentionDecisionServiceProvider.future,
      ),
      notificationsAllowed: ctx.ref.read(notificationsEnabledProvider),
      artifactStore: await ctx.ref.read(
        agent_providers.agentArtifactStoreProvider.future,
      ),
      resolveRoute: ctx.ref.read(sourceRouteResolverProvider),
      l10n: agentL10n(ctx.ref),
    );
  }

  static Future<AgentRunResult> synthesizeAndPersist({
    required LifeContextSnapshot context,
    required String ownerUserId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required DailyNavigatorSynthesizer synthesizer,
    required AgentFindingStore findingStore,
    required AttentionDecisionService attentionService,
    required bool notificationsAllowed,
    required AgentArtifactStore artifactStore,
    required SourceRouteResolver resolveRoute,
    required AppLocalizations l10n,
  }) async {
    final evaluatedDecision = evaluateDailyNavigatorContext(context);
    if (evaluatedDecision == null) {
      await findingStore.reconcile(
        ownerUserId: ownerUserId,
        agentId: kDailyNavigatorAgentId,
        findings: const <AgentFinding>[],
        observedAt: finishedAt,
      );
      return AgentRunResult.skipped(
        agentId: kDailyNavigatorAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: 'No fresh material cross-domain signal.',
      );
    }

    final decision = DailyNavigatorDecision(
      signals: List.unmodifiable(
        evaluatedDecision.signals.where(
          (signal) => signal.evidence.any(
            (source) => resolveRoute(source.rowFamily, source.rowId) != null,
          ),
        ),
      ),
    );
    if (decision.signals.isEmpty) {
      await findingStore.reconcile(
        ownerUserId: ownerUserId,
        agentId: kDailyNavigatorAgentId,
        findings: const <AgentFinding>[],
        observedAt: finishedAt,
      );
      return AgentRunResult.skipped(
        agentId: kDailyNavigatorAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: 'Material signal has no resolvable active-domain evidence.',
      );
    }
    final evidence = _resolveEvidence(decision, resolveRoute);

    final finding = AgentFinding(
      id: kDailyNavigatorFindingId,
      ownerUserId: ownerUserId,
      agentId: kDailyNavigatorAgentId,
      domain: 'life',
      kind: 'daily_judgment',
      severity: AgentArtifactSeverity.attention,
      confidence: 0.85,
      payload: decision.materialJson(context),
    );
    final reconcile = await findingStore.reconcile(
      ownerUserId: ownerUserId,
      agentId: kDailyNavigatorAgentId,
      findings: <AgentFinding>[finding],
      observedAt: finishedAt,
    );
    final fingerprint = finding.evidenceFingerprint;
    final attention = await attentionService.evaluate(
      ownerUserId: ownerUserId,
      candidate: AttentionCandidate(
        id: kDailyNavigatorFindingId,
        agentId: kDailyNavigatorAgentId,
        findingFingerprint: fingerprint,
        severity: finding.severity,
        confidence: finding.confidence,
        actionable: true,
        fresh: true,
        evidenceComplete: evidence.isNotEmpty,
        observedAt: finishedAt,
      ),
      novel: reconcile.changedIds.contains(kDailyNavigatorFindingId),
      suppressed: !reconcile.openIds.contains(kDailyNavigatorFindingId),
      notificationsAllowed: notificationsAllowed,
      decidedAt: finishedAt,
    );
    if (attention.level == AttentionLevel.silent) {
      return AgentRunResult.skipped(
        agentId: kDailyNavigatorAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: 'Attention policy kept the material judgment silent.',
        payload: <String, Object?>{
          'attention_decision_id': attention.id,
          'attention_reasons': attention.reasons,
        },
      );
    }

    final strings = l10n;
    final output = await synthesizer.synthesize(
      context: context,
      decision: decision,
      l10n: strings,
    );
    final artifactId =
        '$kDailyNavigatorAgentId:${fingerprint.substring(0, 16)}';
    final primary = decision.primary;
    final primaryRoute = primary.evidence
        .map((source) => resolveRoute(source.rowFamily, source.rowId))
        .whereType<String>()
        .firstOrNull;
    await artifactStore.save(
      AgentArtifact(
        id: artifactId,
        ownerUserId: ownerUserId,
        agentId: kDailyNavigatorAgentId,
        domain: 'life',
        kind: AgentArtifactKind.briefing,
        severity: AgentArtifactSeverity.attention,
        title: strings.lifeHeroHeadlineAttention,
        summary: output.summary,
        insights: <AgentInsight>[
          for (final signal in decision.signals)
            AgentInsight(
              id: signal.id,
              title: signal.localizedTitle(strings),
              body: signal.localizedSubtitle(strings),
              severity: AgentArtifactSeverity.attention,
              route: signal.routePath,
              evidenceIds: <String>[
                for (final source in signal.evidence)
                  if (resolveRoute(source.rowFamily, source.rowId) != null)
                    '${source.rowFamily}:${source.rowId}',
              ],
            ),
        ],
        evidence: evidence,
        actions: <AgentAction>[
          AgentAction(
            kind: 'review',
            label: output.recommendation,
            route: primaryRoute ?? primary.routePath,
            payload: <String, Object?>{
              'life_context_fingerprint': context.fingerprint,
              'finding_fingerprint': fingerprint,
              'attention_decision_id': attention.id,
            },
          ),
        ],
        methodology: AgentMethodology(
          title: 'Personal Intelligence Loop',
          body:
              'Fresh deterministic domain signals were prioritized before '
              'cross-domain synthesis. No business data was changed.',
          details: <AgentMetric>[
            AgentMetric(label: 'Context', value: context.fingerprint),
            AgentMetric(label: 'Synthesis', value: output.source.name),
            AgentMetric(label: 'Attention', value: attention.level.name),
          ],
        ),
        traceId: output.traceId,
        createdAt: finishedAt,
        expiresAt: finishedAt.add(const Duration(days: 2)),
      ),
    );
    return AgentRunResult(
      agentId: kDailyNavigatorAgentId,
      status: AgentRunStatus.completed,
      startedAt: startedAt,
      finishedAt: finishedAt,
      summary: output.summary,
      payload: <String, Object?>{
        'life_context_fingerprint': context.fingerprint,
        'finding_fingerprint': fingerprint,
        'synthesis_source': output.source.name,
        'attention_decision_id': attention.id,
        'attention_level': attention.level.name,
      },
      artifactId: artifactId,
      traceId: output.traceId,
    );
  }
}

List<AgentEvidenceRef> _resolveEvidence(
  DailyNavigatorDecision decision,
  SourceRouteResolver resolveRoute,
) {
  final refs = <AgentEvidenceRef>[];
  final seen = <String>{};
  for (final signal in decision.signals) {
    for (final source in signal.evidence) {
      final route = resolveRoute(source.rowFamily, source.rowId);
      if (route == null) continue;
      final id = '${source.rowFamily}:${source.rowId}';
      if (!seen.add(id)) continue;
      refs.add(
        AgentEvidenceRef(
          type: 'life_signal_source',
          id: id,
          label: signal.id,
          route: route,
          payload: <String, Object?>{
            'source_identity': source.toJson(),
            'signal_template': signal.template.name,
          },
        ),
      );
    }
  }
  return List<AgentEvidenceRef>.unmodifiable(refs);
}
