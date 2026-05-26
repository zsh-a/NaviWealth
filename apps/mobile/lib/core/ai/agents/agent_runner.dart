/// Agent runner (`docs/lifeos-shell.md` §7.3, D-2.5).
///
/// Drives one or more [Agent]s. Two entry points:
///
/// - [runOnce] — fire a specific agent immediately (manual trigger,
///   "Run morning briefing now" Settings link)
/// - [tick] — called periodically by the platform driver; fires every
///   agent whose [AgentSchedule.shouldFire] returns true
///
/// Each completed run is recorded as an `EventRecord` (source
/// `'agent_run'`) so the cross-domain timeline shows agent activity
/// alongside domain events. The agent itself is responsible for
/// writing whatever richer artefact (memory record, briefing card)
/// belongs in its own surface.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/current_user.dart';
import '../contracts/event_record.dart';
import '../local/memory/memory_runtime.dart';
import '../local/memory/providers.dart';
import 'agent.dart';

/// Source label used for the `EventRecord` of every agent run.
const String kAgentRunEventSource = 'agent_run';
const String kAgentRunEventTypeCompleted = 'agent_run_completed';
const String kAgentRunEventTypeSkipped = 'agent_run_skipped';
const String kAgentRunEventTypeFailed = 'agent_run_failed';

class AgentRunner {
  AgentRunner({required this.runtime, required this.ownerUserId});

  final MemoryRuntime runtime;
  final String ownerUserId;

  /// Tracks each agent's last successful run so [tick] can apply the
  /// schedule's interval gate. Lives in-memory because cron persistence
  /// is platform-side (D-2.5 follow-up); MVP relies on the app being
  /// open at the schedule moment.
  final Map<String, DateTime> _lastRunAt = <String, DateTime>{};

  /// Fire [agent] right now, regardless of schedule. Used by manual
  /// "Run X now" affordances and by tests.
  Future<AgentRunResult> runOnce(Agent agent, AgentContext ctx) async {
    final start = ctx.now;
    AgentRunResult result;
    try {
      result = await agent.run(ctx);
    } catch (e) {
      result = AgentRunResult.failed(
        agentId: agent.id,
        startedAt: start,
        finishedAt: DateTime.now().toUtc(),
        error: e.toString(),
      );
    }
    if (result.status == AgentRunStatus.completed) {
      _lastRunAt[agent.id] = result.startedAt;
    }
    await _recordRunEvent(agent, result);
    return result;
  }

  /// Periodic tick. Iterate the registered agents and fire each whose
  /// schedule says "yes" given [now] and our in-memory last-run map.
  ///
  /// Returns the list of run results for the agents that fired (may
  /// be empty when none of the schedules matched).
  Future<List<AgentRunResult>> tick({
    required List<Agent> agents,
    required AgentContext context,
  }) async {
    final results = <AgentRunResult>[];
    for (final agent in agents) {
      final last = _lastRunAt[agent.id];
      if (!agent.schedule.shouldFire(now: context.now, lastRunAt: last)) {
        continue;
      }
      final result = await runOnce(agent, context);
      results.add(result);
    }
    return results;
  }

  /// When the last successful run was. Returns `null` if the agent
  /// hasn't run in this process.
  DateTime? lastRunAt(String agentId) => _lastRunAt[agentId];

  Future<void> _recordRunEvent(Agent agent, AgentRunResult result) async {
    final type = switch (result.status) {
      AgentRunStatus.completed => kAgentRunEventTypeCompleted,
      AgentRunStatus.skipped => kAgentRunEventTypeSkipped,
      AgentRunStatus.failed => kAgentRunEventTypeFailed,
    };
    final event = EventRecord(
      id: '$kAgentRunEventSource:${agent.id}:${result.startedAt.toUtc().toIso8601String()}',
      type: type,
      timestamp: result.finishedAt.toUtc(),
      source: kAgentRunEventSource,
      ownerUserId: ownerUserId,
      title: '${agent.name} · ${result.status.name}',
      summary: result.summary ??
          (result.status == AgentRunStatus.failed
              ? (result.error ?? 'agent failed')
              : '${agent.name} ${result.status.name}'),
      payload: <String, Object?>{
        'agent_id': agent.id,
        'agent_name': agent.name,
        'status': result.status.name,
        'duration_ms': result.duration.inMilliseconds,
        if (result.memoryId != null) 'memory_id': result.memoryId,
        if (result.error != null) 'error': result.error,
        ...result.payload,
      },
      entities: <String>{'agent', agent.id},
      importance: switch (result.status) {
        AgentRunStatus.completed => 0.6,
        AgentRunStatus.skipped => 0.35,
        AgentRunStatus.failed => 0.7,
      },
    );
    await runtime.recordEvent(event);
  }
}

/// Riverpod wiring. The runner is single-instance per logged-in user;
/// when the user changes the provider is invalidated and a new runner
/// (with a fresh `_lastRunAt` map) is built.
final agentRunnerProvider = FutureProvider<AgentRunner>((ref) async {
  final runtime = await ref.watch(memoryRuntimeProvider.future);
  final ownerUserId = await ref.read(currentUserIdProvider)();
  return AgentRunner(runtime: runtime, ownerUserId: ownerUserId);
});
