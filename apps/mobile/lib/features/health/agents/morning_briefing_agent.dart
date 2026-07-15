/// `morning_briefing` — first cross-domain autonomous agent
/// (`docs/domains/healthos-domain.md` §8, `docs/architecture/lifeos-shell.md` §7.3, D-2.5 +
/// D-2.5b).
///
/// Reads the last 24h of Finance + Health events from the cross-domain
/// event log and produces a short briefing: how the user slept, any
/// recovery signal flagged in the indexer, and a count of overnight
/// Finance events. Output is persisted as an episodic [MemoryRecord]
/// so the user can ask "what did the morning briefing say yesterday?"
/// and the next `build_context` call finds it.
///
/// D-2.5b layers in:
///  * [BriefingSynthesizer] injection — production wiring picks FRB-backed
///    LLM synthesis when the profile runtime is available, programmatic
///    otherwise (programmatic is also the FRB path's auto-fallback).
///  * Optional [NotificationService] hook — fires a local notification
///    after a successful run so the user sees the briefing without
///    opening the app.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_presentation.dart';
import '../../../core/ai/agents/agent_artifact_store.dart';
import '../../../core/ai/agents/agent_intents.dart';
import '../../../core/ai/agents/agent_l10n.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/contracts/event_record.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/health_route_paths.dart';
import '../data/morning_briefing_preferences.dart';
import 'briefing_synthesizer.dart';
import 'health_notifications.dart';

const String kMorningBriefingAgentId = 'morning_briefing';
const String kMorningBriefingMemorySource = 'agent:morning_briefing';

class MorningBriefingAgent implements Agent {
  const MorningBriefingAgent({
    this.synthesizer = const ProgrammaticBriefingSynthesizer(),
    this.notifier,
    this.hourLocal = kDefaultMorningBriefingHourLocal,
  });

  /// Pluggable synthesis step. `bootstrap.dart` injects
  /// [FrbBriefingSynthesizer] when the FRB profile runtime is available;
  /// otherwise the programmatic default ships.
  final BriefingSynthesizer synthesizer;

  /// Optional local-notification hook. When supplied and the platform
  /// has granted permission, the agent posts a one-shot toast with
  /// the briefing summary after each successful run.
  final NotificationService? notifier;

  /// User-configurable preferred local-time hour (0–23). Sourced from
  /// [morningBriefingHourProvider] via the bootstrap override.
  final int hourLocal;

  @override
  String get id => kMorningBriefingAgentId;

  @override
  String get name => 'Morning Briefing';

  @override
  AgentSchedule get schedule => AgentSchedule.daily(hourLocal: hourLocal);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final start = ctx.now;
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();

    final recent = await runtime.recentEvents(
      ownerUserId: ownerUserId,
      window: const Duration(hours: 24),
      limit: 200,
    );

    final result = await _synthesizeAndPersist(
      events: recent,
      ownerUserId: ownerUserId,
      startedAt: start,
      finishedAt: DateTime.now().toUtc(),
      runtime: runtime,
      artifactStore: await ctx.ref.read(
        agent_providers.agentArtifactStoreProvider.future,
      ),
      l10n: agentL10n(ctx.ref),
    );

    if (result.status == AgentRunStatus.completed && notifier != null) {
      await _maybeNotify(
        ctx,
        ownerUserId,
        start.toLocal(),
        result.summary ?? '',
        agentL10n(ctx.ref),
      );
    }
    return result;
  }

  /// Pure execution path — exposed as a static so tests can drive the
  /// agent without a Riverpod ref (just inject the runtime + events).
  static Future<AgentRunResult> synthesize({
    required List<EventRecord> events,
    required String ownerUserId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required MemoryRuntime runtime,
    BriefingSynthesizer synthesizer = const ProgrammaticBriefingSynthesizer(),
    AgentArtifactStore? artifactStore,
    AppLocalizations? l10n,
  }) {
    final agent = MorningBriefingAgent(synthesizer: synthesizer);
    return agent._synthesizeAndPersist(
      events: events,
      ownerUserId: ownerUserId,
      startedAt: startedAt,
      finishedAt: finishedAt,
      runtime: runtime,
      artifactStore: artifactStore,
      l10n: l10n ?? defaultAgentL10n(),
    );
  }

  Future<AgentRunResult> _synthesizeAndPersist({
    required List<EventRecord> events,
    required String ownerUserId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required MemoryRuntime runtime,
    AgentArtifactStore? artifactStore,
    AppLocalizations? l10n,
  }) async {
    final strings = l10n ?? defaultAgentL10n();
    final healthEvents = events
        .where((e) => e.source.startsWith('health'))
        .toList();
    final financeEvents = events
        .where(
          (e) =>
              !e.source.startsWith('health') &&
              e.source != 'agent_run' &&
              !e.source.startsWith('agent:'),
        )
        .toList();

    if (healthEvents.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kMorningBriefingAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: strings.healthAgentMorningSkipNoHealth,
      );
    }

    final dayKey = AppFormatters.utcDayKey(startedAt);
    final inputs = BriefingInputs(
      dayKey: dayKey,
      healthEvents: healthEvents,
      financeEvents: financeEvents,
      l10n: strings,
    );
    final output = await synthesizer.synthesize(inputs);

    if (output.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kMorningBriefingAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: strings.healthAgentMorningSkipNoUsable,
      );
    }

    final memoryId = '$kMorningBriefingMemorySource:$dayKey';
    final artifactId = '$kMorningBriefingAgentId:$dayKey';
    final memory = MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      scope: '*',
      source: kMorningBriefingMemorySource,
      sourceId: dayKey,
      title: strings.healthAgentMorningMemoryTitle(dayKey),
      summary: output.summary,
      payload: <String, Object?>{
        'context':
            'morning briefing run at ${startedAt.toUtc().toIso8601String()}',
        'decision': null,
        'reasoning': null,
        'outcome': <String, Object?>{
          'health_event_count': healthEvents.length,
          'finance_event_count': financeEvents.length,
          'sleep_summary': ?output.sleepLine,
          'hrv_summary': ?output.hrvLine,
          'finance_summary': ?output.financeLine,
          'synthesis_source': output.source.name,
          if (output.traceId != null) 'trace_id': output.traceId,
        },
        'artifact_id': artifactId,
        if (output.traceId != null) 'trace_id': output.traceId,
      },
      entities: <String>{'morning_briefing', 'briefing', dayKey},
      importance: 0.6,
      confidence: 0.75,
      validFrom: startedAt.toUtc(),
      createdAt: startedAt.toUtc(),
      updatedAt: finishedAt.toUtc(),
    );
    await runtime.remember(memory);
    await artifactStore?.save(
      _artifact(
        id: artifactId,
        ownerUserId: ownerUserId,
        memoryId: memoryId,
        createdAt: startedAt,
        output: output,
        healthEvents: healthEvents,
        financeEvents: financeEvents,
        l10n: strings,
      ),
    );

    return AgentRunResult(
      agentId: kMorningBriefingAgentId,
      status: AgentRunStatus.completed,
      startedAt: startedAt,
      finishedAt: finishedAt,
      summary: output.summary,
      payload: <String, Object?>{
        'health_event_count': healthEvents.length,
        'finance_event_count': financeEvents.length,
        'synthesis_source': output.source.name,
      },
      memoryId: memoryId,
      artifactId: artifactStore == null ? null : artifactId,
      traceId: output.traceId,
    );
  }

  static AgentArtifact _artifact({
    required String id,
    required String ownerUserId,
    required String memoryId,
    required DateTime createdAt,
    required BriefingOutput output,
    required List<EventRecord> healthEvents,
    required List<EventRecord> financeEvents,
    required AppLocalizations l10n,
  }) {
    final shortSleep = healthEvents.any(
      (event) => event.entities.contains('short_sleep'),
    );
    return AgentArtifact(
      id: id,
      ownerUserId: ownerUserId,
      agentId: kMorningBriefingAgentId,
      domain: 'health',
      kind: AgentArtifactKind.briefing,
      severity: shortSleep
          ? AgentArtifactSeverity.attention
          : AgentArtifactSeverity.info,
      title: l10n.healthAgentMorningTitle,
      summary: output.summary,
      metrics: <AgentMetric>[
        AgentMetric(
          label: l10n.healthAgentMorningInsightSleepTitle,
          value: healthEvents.length.toString(),
          context: l10n.healthAgentMorningTitle,
          severity: shortSleep ? AgentArtifactSeverity.attention : null,
        ),
        if (financeEvents.isNotEmpty)
          AgentMetric(
            label: l10n.healthAgentMorningInsightFinanceTitle,
            value: financeEvents.length.toString(),
          ),
      ],
      insights: <AgentInsight>[
        if (output.sleepLine != null)
          AgentInsight(
            id: 'sleep',
            title: l10n.healthAgentMorningInsightSleepTitle,
            body: output.sleepLine!,
            severity: shortSleep
                ? AgentArtifactSeverity.attention
                : AgentArtifactSeverity.info,
            route: HealthRoutes.trend,
          ),
        if (output.hrvLine != null)
          AgentInsight(
            id: 'hrv',
            title: l10n.healthAgentMorningInsightHrvTitle,
            body: output.hrvLine!,
            route: HealthRoutes.trend,
          ),
        if (output.financeLine != null)
          AgentInsight(
            id: 'finance',
            title: l10n.healthAgentMorningInsightFinanceTitle,
            body: output.financeLine!,
            route: HealthRoutes.today,
          ),
      ],
      evidence: <AgentEvidenceRef>[
        for (final event in healthEvents.take(8))
          AgentEvidenceRef(
            type: 'health_event',
            id: event.id,
            label: event.summary,
            route: HealthRoutes.trend,
            payload: <String, Object?>{
              'event_type': event.type,
              'source': event.source,
            },
          ),
        for (final event in financeEvents.take(5))
          AgentEvidenceRef(
            type: 'finance_event',
            id: event.id,
            label: event.summary,
            route: HealthRoutes.today,
            payload: <String, Object?>{
              'event_type': event.type,
              'source': event.source,
            },
          ),
      ],
      actions: <AgentAction>[
        AgentAction(
          kind: 'review',
          label: l10n.healthAgentMorningAction,
          intent: kAgentExplainResultIntent,
          objectType: kAgentArtifactObjectType,
          objectId: id,
          route: HealthRoutes.today,
        ),
      ],
      methodology: localAgentMethodology(
        l10n,
        sourceLabel: l10n.healthAgentMorningTitle,
        modelAssisted: output.traceId != null,
      ),
      memoryId: memoryId,
      traceId: output.traceId,
      createdAt: createdAt.toUtc(),
      expiresAt: createdAt.toUtc().add(const Duration(days: 7)),
    );
  }

  Future<void> _maybeNotify(
    AgentContext ctx,
    String ownerUserId,
    DateTime localDay,
    String summary,
    AppLocalizations l10n,
  ) async {
    final n = notifier!;
    try {
      final preferenceStore = await ctx.ref.read(
        agent_providers.agentPreferenceStoreProvider.future,
      );
      final notificationsEnabled = await preferenceStore
          .areNotificationsEnabled(
            ownerUserId: ownerUserId,
            agentId: kMorningBriefingAgentId,
          );
      if (!notificationsEnabled) return;
      if (!await n.hasPermissions()) return;
      await n.showNow(
        id: HealthNotifications.idForBriefing(localDay),
        title: l10n.healthAgentMorningTitle,
        body: summary,
        payload: 'morning_briefing',
        channel: kHealthBriefingNotificationChannel,
      );
    } on Object {
      // Best-effort — never let a notification failure mark the agent
      // run as failed.
    }
  }
}

/// Riverpod-exposed agent. Bootstrap can override with
/// [FrbBriefingSynthesizer] when the FRB profile runtime is available.
final morningBriefingAgentProvider = Provider<Agent>(
  (ref) => const MorningBriefingAgent(),
);
