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

  /// A fresh run for the same owner + agent is already active.
  ///
  /// Busy results are returned to the caller only. They must not be persisted
  /// as skipped/no-finding runs because they should not advance schedules.
  busy,
}

/// Product-facing status for a finished [AgentRunResult].
///
/// This intentionally excludes `running`: an [AgentRunResult] is emitted only
/// after a run has finished, while the persistent run store owns in-flight
/// lifecycle rows.
enum AgentRunUserVisibleStatus { ready, noFinding, failed }

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
    this.artifactId,
    this.traceId,
    this.error,
  });

  factory AgentRunResult.skipped({
    required String agentId,
    required DateTime startedAt,
    required DateTime finishedAt,
    String? reason,
    String? traceId,
    Map<String, Object?> payload = const <String, Object?>{},
  }) => AgentRunResult(
    agentId: agentId,
    status: AgentRunStatus.skipped,
    startedAt: startedAt,
    finishedAt: finishedAt,
    summary: reason,
    traceId: traceId,
    payload: payload,
  );

  factory AgentRunResult.failed({
    required String agentId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required String error,
    String? traceId,
  }) => AgentRunResult(
    agentId: agentId,
    status: AgentRunStatus.failed,
    startedAt: startedAt,
    finishedAt: finishedAt,
    error: error,
    traceId: traceId,
  );

  factory AgentRunResult.busy({
    required String agentId,
    required DateTime startedAt,
    required DateTime finishedAt,
    String? reason,
  }) => AgentRunResult(
    agentId: agentId,
    status: AgentRunStatus.busy,
    startedAt: startedAt,
    finishedAt: finishedAt,
    summary: reason,
  );

  /// `[Agent.id]` of the agent that produced this result. Stable
  /// identifier — UI surfaces ("show me the latest Daily Navigator") key
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
  /// Daily Navigator uses structured active-domain context and evidence.
  final Map<String, Object?> payload;

  /// If the agent wrote a memory record, this is its id (so callers
  /// can re-read it). `null` for skipped / failed runs.
  final String? memoryId;

  /// If the agent produced a user-visible artifact, this is its id.
  /// `null` for skipped / failed runs and for legacy agents that only
  /// write memory/events.
  final String? artifactId;

  /// AI/runtime trace associated with this run, when the agent used the
  /// runtime trace recorder.
  final String? traceId;

  final String? error;

  Duration get duration => finishedAt.difference(startedAt);

  AgentRunUserVisibleStatus get userVisibleStatus => switch (status) {
    AgentRunStatus.completed => AgentRunUserVisibleStatus.ready,
    AgentRunStatus.skipped => AgentRunUserVisibleStatus.noFinding,
    AgentRunStatus.failed => AgentRunUserVisibleStatus.failed,
    AgentRunStatus.busy => throw StateError(
      'busy agent results are transient and cannot be persisted',
    ),
  };
}

/// One named Agent use case. Domain analyzers register through DomainPack;
/// app-owned cross-domain synthesis registers through app composition.
abstract class Agent {
  /// Stable opaque id (e.g. `'daily_navigator'`) used by runs, findings,
  /// artifacts, feedback, and attention decisions.
  String get id;

  /// Display name shown in Agent run surfaces. Free text.
  String get name;

  /// Schedule fallback. Signal-driven dispatch uses `AgentTriggerSpec` before
  /// entering the runner and records its own run provenance.
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
