/// Cross-domain agent contract (`docs/architecture/lifeos-shell.md` §7.3, D-2.5).
///
/// An [Agent] is an autonomous, scheduled piece of work that runs
/// without the user pressing a button — typically a daily briefing
/// or weekly review. It composes signals from multiple domains and
/// produces a durable artefact (memory record + optional notification).
///
/// The shell ships only the abstraction; concrete agents live in
/// domain modules (e.g. `features/health/agents/`) or app composition
/// (`app/agents/`) when they cross more than one domain.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_schedule.dart';

/// What an [Agent.run] gets: Riverpod access for the providers it
/// reads from + an injectable wall clock so tests are deterministic.
class AgentContext {
  const AgentContext({required this.ref, required this.now});

  /// Caller's Ref. Use `ref.read` only — agents are one-shot runs, not
  /// stateful subscriptions. Holding a stream subscription past
  /// [Agent.run] returning is a leak (the runner doesn't track it).
  final Ref ref;

  /// Wall time at the start of the run. Use this everywhere instead
  /// of `DateTime.now()` so the run is reproducible from a recorded
  /// `startedAt`.
  final DateTime now;
}

/// Status of one agent run.
enum AgentRunStatus {
  /// Agent ran end-to-end and emitted an artefact.
  completed,

  /// Agent ran but decided there was nothing to report (e.g. no new
  /// data since last run). Not a failure — the runner still records
  /// the skip so the schedule advances.
  skipped,

  /// Agent threw; the runner caught it. `error` carries the message.
  failed,
}

/// One agent run's outcome — what the runner persists.
class AgentRunResult {
  const AgentRunResult({
    required this.agentId,
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    this.summary,
    this.payload = const <String, Object?>{},
    this.memoryId,
    this.error,
  });

  factory AgentRunResult.skipped({
    required String agentId,
    required DateTime startedAt,
    required DateTime finishedAt,
    String? reason,
  }) => AgentRunResult(
    agentId: agentId,
    status: AgentRunStatus.skipped,
    startedAt: startedAt,
    finishedAt: finishedAt,
    summary: reason,
  );

  factory AgentRunResult.failed({
    required String agentId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required String error,
  }) => AgentRunResult(
    agentId: agentId,
    status: AgentRunStatus.failed,
    startedAt: startedAt,
    finishedAt: finishedAt,
    error: error,
  );

  /// `[Agent.id]` of the agent that produced this result. Stable
  /// identifier — UI surfaces ("show me last morning briefing") key
  /// off it.
  final String agentId;

  final AgentRunStatus status;
  final DateTime startedAt;
  final DateTime finishedAt;

  /// One-line human-readable verdict for the UI ("Brief day; recovery
  /// balanced.") or skip reason ("no new signals since last run").
  final String? summary;

  /// Structured payload the agent wants to persist alongside the
  /// summary. Free-form so each agent can shape its own output —
  /// Morning Briefing uses `{slept_hours, recovery_score, finance_delta, ...}`.
  final Map<String, Object?> payload;

  /// If the agent wrote a memory record, this is its id (so callers
  /// can re-read it). `null` for skipped / failed runs.
  final String? memoryId;

  final String? error;

  Duration get duration => finishedAt.difference(startedAt);
}

/// One scheduled agent. Concrete implementations live in domain
/// modules; they register via `agentRegistryProvider` overrides in
/// `bootstrap.dart`.
abstract class Agent {
  /// Stable opaque id (e.g. `'morning_briefing'`). Used as the
  /// memory / event back-pointer key — never rename without a
  /// migration.
  String get id;

  /// Display name shown in any "agent runs" UI surface ("Morning
  /// Briefing"). Free text.
  String get name;

  /// When this agent should fire — usually a fixed daily / weekly
  /// cadence.
  AgentSchedule get schedule;

  /// Execute one run.
  ///
  /// Implementations should:
  /// 1. Read whatever signals they need via `ctx.ref.read(...)`
  /// 2. Decide whether to produce output (use [AgentRunResult.skipped]
  ///    when there's nothing meaningful to report)
  /// 3. On success return an [AgentRunResult] with `completed` status;
  ///    the runner takes care of recording an `EventRecord` for the
  ///    run itself
  ///
  /// Throwing is allowed — the runner converts it into a `failed`
  /// result with the message.
  Future<AgentRunResult> run(AgentContext ctx);
}
