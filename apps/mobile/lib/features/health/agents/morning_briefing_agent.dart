/// `morning_briefing` — first cross-domain autonomous agent
/// (`docs/healthos-domain.md` §8, `docs/lifeos-shell.md` §7.3, D-2.5).
///
/// Reads the last 24h of Finance + Health events from the cross-domain
/// event log and produces a short briefing: how the user slept, any
/// recovery signal flagged in the indexer (short/long sleep, notes),
/// and a count of overnight Finance events (trades opened, dividends,
/// proposals). Output is persisted as an episodic [MemoryRecord] so
/// the user can ask "what did the morning briefing say yesterday?"
/// and the next `build_context` call finds it.
///
/// MVP is **programmatic** — no LLM call. The intent is to ship the
/// agent runtime end-to-end first, then swap the synthesis step for
/// an LLM-driven version once D-2.2 brings in real data and we have
/// a corpus to evaluate against.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/contracts/event_record.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../data/health_metric_memory_indexer.dart';

const String kMorningBriefingAgentId = 'morning_briefing';
const String kMorningBriefingMemorySource = 'agent:morning_briefing';

class MorningBriefingAgent implements Agent {
  const MorningBriefingAgent();

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

    // Pull the last 24h slice from both domains. We don't filter by
    // source at the store level because finance events come from many
    // sources (options_trade_journal, future ones); we collect all
    // and partition by `source.startsWith('health')` vs. the rest.
    final recent = await runtime.recentEvents(
      ownerUserId: ownerUserId,
      window: const Duration(hours: 24),
      limit: 200,
    );

    return synthesize(
      events: recent,
      ownerUserId: ownerUserId,
      startedAt: start,
      finishedAt: DateTime.now().toUtc(),
      runtime: runtime,
    );
  }

  /// Pure synthesis step — exposed for unit tests so the briefing
  /// logic can run without a Drift database or wall clock.
  ///
  /// Writes one memory record on success and returns the result. When
  /// there are no health events at all we return `skipped` so the
  /// agent runner records a skip event and the user doesn't see an
  /// empty briefing.
  static Future<AgentRunResult> synthesize({
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
        .where((e) => !e.source.startsWith('health') &&
            e.source != 'agent_run' &&
            !e.source.startsWith('agent:'))
        .toList();

    if (healthEvents.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kMorningBriefingAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: 'no health signals in the last 24h',
      );
    }

    final sleepSummary = _summariseSleep(healthEvents);
    final hrvSummary = _summariseHrv(healthEvents);
    final financeSummary = _summariseFinance(financeEvents);

    final summaryText = StringBuffer();
    if (sleepSummary != null) {
      summaryText.write(sleepSummary);
    }
    if (hrvSummary != null) {
      if (summaryText.isNotEmpty) summaryText.write(' · ');
      summaryText.write(hrvSummary);
    }
    if (financeSummary != null) {
      if (summaryText.isNotEmpty) summaryText.write(' · ');
      summaryText.write(financeSummary);
    }
    if (summaryText.isEmpty) {
      // Health events existed but didn't carry usable signals (only
      // unknown kinds, perhaps). Skip rather than write an empty card.
      return AgentRunResult.skipped(
        agentId: kMorningBriefingAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: 'health events present but no usable signals',
      );
    }

    final dayKey = startedAt.toUtc().toIso8601String().substring(0, 10);
    final memoryId = '$kMorningBriefingMemorySource:$dayKey';
    final memory = MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      scope: '*',
      source: kMorningBriefingMemorySource,
      sourceId: dayKey,
      title: 'Morning briefing · $dayKey',
      summary: summaryText.toString(),
      payload: <String, Object?>{
        'context': 'morning briefing run at ${startedAt.toUtc().toIso8601String()}',
        'decision': null,
        'reasoning': null,
        'outcome': <String, Object?>{
          'health_event_count': healthEvents.length,
          'finance_event_count': financeEvents.length,
          'sleep_summary': ?sleepSummary,
          'hrv_summary': ?hrvSummary,
          'finance_summary': ?financeSummary,
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
      summary: summaryText.toString(),
      payload: <String, Object?>{
        'health_event_count': healthEvents.length,
        'finance_event_count': financeEvents.length,
      },
      memoryId: memoryId,
    );
  }

  /// Sleep: longest matching `sleep_session_ended` event in the window.
  /// Each event's payload has `value` + `unit`; we convert to hours
  /// and surface the most recent reading.
  static String? _summariseSleep(List<EventRecord> healthEvents) {
    EventRecord? latest;
    for (final e in healthEvents) {
      if (e.type != kEventSleepSessionEnded) continue;
      if (latest == null || e.timestamp.isAfter(latest.timestamp)) {
        latest = e;
      }
    }
    if (latest == null) return null;
    final value = latest.payload['value'];
    final unit = latest.payload['unit'];
    if (value is! num) return null;
    final hours = switch (unit) {
      's' => value / 3600.0,
      'min' => value / 60.0,
      'h' => value.toDouble(),
      _ => value / 3600.0,
    };
    final rounded = (hours * 10).round() / 10.0;
    final tag = (latest.entities.contains('short_sleep'))
        ? ' (short)'
        : latest.entities.contains('long_sleep')
            ? ' (long)'
            : '';
    return 'Slept ${rounded}h$tag';
  }

  /// HRV: most recent `hrv_recorded` value + ms unit.
  static String? _summariseHrv(List<EventRecord> healthEvents) {
    EventRecord? latest;
    for (final e in healthEvents) {
      if (e.type != kEventHrvRecorded) continue;
      if (latest == null || e.timestamp.isAfter(latest.timestamp)) {
        latest = e;
      }
    }
    if (latest == null) return null;
    final value = latest.payload['value'];
    if (value is! num) return null;
    return 'HRV ${value.toStringAsFixed(0)}ms';
  }

  /// Finance: count of events grouped by type for a one-line summary
  /// ("2 trades, 1 proposal"). Empty when nothing fired overnight.
  static String? _summariseFinance(List<EventRecord> financeEvents) {
    if (financeEvents.isEmpty) return null;
    final byType = <String, int>{};
    for (final e in financeEvents) {
      byType[e.type] = (byType[e.type] ?? 0) + 1;
    }
    final pieces = <String>[];
    byType.forEach((type, count) {
      pieces.add('$count ${type.replaceAll('_', ' ')}');
    });
    return 'Finance: ${pieces.join(', ')}';
  }
}

/// Riverpod-exposed singleton for bootstrap registration.
final morningBriefingAgentProvider = Provider<Agent>(
  (ref) => const MorningBriefingAgent(),
);
