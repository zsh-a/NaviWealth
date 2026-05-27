/// `morning_briefing` — first cross-domain autonomous agent
/// (`docs/healthos-domain.md` §8, `docs/lifeos-shell.md` §7.3, D-2.5 +
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
///  * [BriefingSynthesizer] injection — agent picks LLM-driven
///    synthesis when an LLM client is configured, programmatic
///    otherwise (programmatic is also the LLM path's auto-fallback).
///  * Optional [NotificationService] hook — fires a local notification
///    after a successful run so the user sees the briefing without
///    opening the app.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/contracts/event_record.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/notifications/notification_service.dart';
import 'briefing_synthesizer.dart';

const String kMorningBriefingAgentId = 'morning_briefing';
const String kMorningBriefingMemorySource = 'agent:morning_briefing';

class MorningBriefingAgent implements Agent {
  const MorningBriefingAgent({
    this.synthesizer = const ProgrammaticBriefingSynthesizer(),
    this.notifier,
  });

  /// Pluggable synthesis step. `bootstrap.dart` injects
  /// [LlmBriefingSynthesizer] when the user has configured an LLM
  /// profile; otherwise the programmatic default ships.
  final BriefingSynthesizer synthesizer;

  /// Optional local-notification hook. When supplied and the platform
  /// has granted permission, the agent posts a one-shot toast with
  /// the briefing summary after each successful run.
  final NotificationService? notifier;

  @override
  String get id => kMorningBriefingAgentId;

  @override
  String get name => 'Morning Briefing';

  @override
  AgentSchedule get schedule => AgentSchedule.daily(hourLocal: 7);

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
    );

    if (result.status == AgentRunStatus.completed && notifier != null) {
      await _maybeNotify(start.toLocal(), result.summary ?? '');
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
  }) {
    final agent = MorningBriefingAgent(synthesizer: synthesizer);
    return agent._synthesizeAndPersist(
      events: events,
      ownerUserId: ownerUserId,
      startedAt: startedAt,
      finishedAt: finishedAt,
      runtime: runtime,
    );
  }

  Future<AgentRunResult> _synthesizeAndPersist({
    required List<EventRecord> events,
    required String ownerUserId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required MemoryRuntime runtime,
  }) async {
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
        reason: 'no health signals in the last 24h',
      );
    }

    final dayKey = startedAt.toUtc().toIso8601String().substring(0, 10);
    final inputs = BriefingInputs(
      dayKey: dayKey,
      healthEvents: healthEvents,
      financeEvents: financeEvents,
    );
    final output = await synthesizer.synthesize(inputs);

    if (output.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kMorningBriefingAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: 'health events present but no usable signals',
      );
    }

    final memoryId = '$kMorningBriefingMemorySource:$dayKey';
    final memory = MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      scope: '*',
      source: kMorningBriefingMemorySource,
      sourceId: dayKey,
      title: 'Morning briefing · $dayKey',
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
        },
      },
      entities: <String>{'morning_briefing', 'briefing', dayKey},
      importance: 0.6,
      confidence: 0.75,
      validFrom: startedAt.toUtc(),
      createdAt: startedAt.toUtc(),
      updatedAt: finishedAt.toUtc(),
    );
    await runtime.remember(memory);

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
    );
  }

  Future<void> _maybeNotify(DateTime localDay, String summary) async {
    final n = notifier!;
    try {
      if (!await n.hasPermissions()) return;
      await n.showNow(
        id: HealthNotifications.idForBriefing(localDay),
        title: 'Morning Briefing',
        body: summary,
        payload: 'morning_briefing',
      );
    } on Object {
      // Best-effort — never let a notification failure mark the agent
      // run as failed.
    }
  }
}

/// Riverpod-exposed agent. Bootstrap can override with
/// [LlmBriefingSynthesizer] when an LLM profile is configured.
final morningBriefingAgentProvider = Provider<Agent>(
  (ref) => const MorningBriefingAgent(),
);
