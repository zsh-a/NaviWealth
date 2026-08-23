/// `weekly_summary` — produces a weekly health overview.
///
/// Runs every Sunday evening. Aggregates the week's sleep, HRV, steps,
/// and workout data into a concise summary memory record.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_presentation.dart';
import '../../../core/ai/agents/agent_intents.dart';
import '../../../core/ai/agents/agent_l10n.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/contracts/context_evidence.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_terminal_output.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/health_route_paths.dart';
import '../data/providers.dart';
import '../data/recovery_scorer.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

const String kWeeklySummaryAgentId = 'weekly_summary';
const String kWeeklySummaryMemorySource = 'agent:weekly_summary';

class WeeklySummaryAgent implements Agent {
  const WeeklySummaryAgent({
    this.summaryReader = const RepositoryWeeklySummaryReader(),
  });

  final WeeklySummaryReader summaryReader;

  @override
  String get id => kWeeklySummaryAgentId;

  @override
  String get name => 'Weekly Summary';

  @override
  AgentSchedule get schedule =>
      const AgentSchedule(interval: Duration(days: 7), preferredHourLocal: 20);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final start = ctx.now;
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final l10n = agentL10n(ctx.ref);

    final snapshot = await summaryReader.read(ctx);

    if (!snapshot.hasAnySignal) {
      return AgentRunResult.skipped(
        agentId: kWeeklySummaryAgentId,
        startedAt: start,
        finishedAt: DateTime.now().toUtc(),
        reason: l10n.healthAgentWeeklySkipNoData,
        traceId: snapshot.traceId,
      );
    }

    // Build summary.
    final parts = <String>[];
    final recoveryScore = snapshot.recoveryScore;
    final recoveryVerdict = snapshot.recoveryVerdict;
    if (recoveryScore != null && recoveryVerdict != null) {
      parts.add(
        l10n.healthAgentWeeklyPartRecovery(recoveryScore, recoveryVerdict),
      );
    }
    final avgSleep = snapshot.avgSleepHours;
    if (avgSleep != null) {
      parts.add(l10n.healthAgentWeeklyPartAvgSleep(_round(avgSleep)));
    }
    final weekSteps = snapshot.totalSteps;
    if (weekSteps > 0) {
      parts.add(l10n.healthAgentWeeklyPartSteps(_formatSteps(weekSteps)));
    }
    final weekWorkouts = snapshot.workoutCount;
    final weekWorkoutMin = snapshot.workoutMinutes;
    if (weekWorkouts > 0) {
      parts.add(
        l10n.healthAgentWeeklyPartWorkouts(
          weekWorkouts,
          _round(weekWorkoutMin),
        ),
      );
    }

    if (parts.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kWeeklySummaryAgentId,
        startedAt: start,
        finishedAt: DateTime.now().toUtc(),
        reason: l10n.healthAgentWeeklySkipNoActionable,
        traceId: snapshot.traceId,
      );
    }

    final summary = l10n.healthAgentWeeklySummary(parts.join(' · '));
    final dayKey = AppFormatters.utcDayKey(start);
    final memoryId = '$kWeeklySummaryMemorySource:$dayKey';
    final artifactId = '$kWeeklySummaryAgentId:$dayKey';

    final memory = MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      role: MemoryRole.pattern,
      authority: EvidenceAuthority.deterministicDerived,
      ownerUserId: ownerUserId,
      scope: '*',
      source: kWeeklySummaryMemorySource,
      sourceId: dayKey,
      title: l10n.healthAgentWeeklyMemoryTitle(dayKey),
      summary: summary,
      payload: <String, Object?>{
        'context': 'weekly summary at ${start.toUtc().toIso8601String()}',
        'outcome': <String, Object?>{
          'recovery_score': recoveryScore,
          'recovery_verdict': recoveryVerdict,
          'avg_sleep_hours': avgSleep == null ? null : _round(avgSleep),
          'total_steps': weekSteps,
          'workout_count': weekWorkouts,
          'workout_minutes': _round(weekWorkoutMin),
          if (snapshot.traceId != null) 'trace_id': snapshot.traceId,
        },
        'artifact_id': artifactId,
        if (snapshot.traceId != null) 'trace_id': snapshot.traceId,
      },
      entities: <String>{'weekly_summary', 'health', dayKey},
      importance: 0.6,
      confidence: 0.8,
      validFrom: start.toUtc(),
      createdAt: start.toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    await runtime.remember(memory);
    final artifactStore = await ctx.ref.read(
      agent_providers.agentArtifactStoreProvider.future,
    );
    await artifactStore.save(
      _artifact(
        id: artifactId,
        ownerUserId: ownerUserId,
        memoryId: memoryId,
        createdAt: start,
        snapshot: snapshot,
        summary: summary,
        traceId: snapshot.traceId,
        l10n: l10n,
      ),
    );

    return AgentRunResult(
      agentId: kWeeklySummaryAgentId,
      status: AgentRunStatus.completed,
      startedAt: start,
      finishedAt: DateTime.now().toUtc(),
      summary: summary,
      payload: <String, Object?>{
        'recovery_score': recoveryScore,
        'total_steps': weekSteps,
        'workout_count': weekWorkouts,
        if (snapshot.traceId != null) 'trace_id': snapshot.traceId,
      },
      memoryId: memoryId,
      artifactId: artifactId,
      traceId: snapshot.traceId,
    );
  }

  static AgentArtifact _artifact({
    required String id,
    required String ownerUserId,
    required String memoryId,
    required DateTime createdAt,
    required WeeklySummarySnapshot snapshot,
    required String summary,
    required String? traceId,
    required AppLocalizations l10n,
  }) {
    final recoveryScore = snapshot.recoveryScore;
    final severity = recoveryScore == null
        ? AgentArtifactSeverity.info
        : recoveryScore < 60
        ? AgentArtifactSeverity.warning
        : recoveryScore < 75
        ? AgentArtifactSeverity.attention
        : AgentArtifactSeverity.info;
    return AgentArtifact(
      id: id,
      ownerUserId: ownerUserId,
      agentId: kWeeklySummaryAgentId,
      domain: 'health',
      kind: AgentArtifactKind.review,
      severity: severity,
      title: l10n.healthAgentWeeklyTitle,
      summary: summary,
      metrics: <AgentMetric>[
        if (snapshot.recoveryScore != null)
          AgentMetric(
            label: l10n.healthAgentWeeklyInsightRecoveryTitle,
            value: '${snapshot.recoveryScore}/100',
            severity: severity == AgentArtifactSeverity.info ? null : severity,
          ),
        if (snapshot.avgSleepHours != null)
          AgentMetric(
            label: l10n.healthAgentWeeklyInsightSleepTitle,
            value: '${_round(snapshot.avgSleepHours!)}h',
          ),
        if (snapshot.totalSteps > 0)
          AgentMetric(
            label: l10n.healthAgentWeeklyInsightActivityTitle,
            value: _formatSteps(snapshot.totalSteps),
          ),
      ],
      insights: <AgentInsight>[
        if (snapshot.recoveryScore != null)
          AgentInsight(
            id: 'recovery',
            title: l10n.healthAgentWeeklyInsightRecoveryTitle,
            body: l10n.healthAgentWeeklyInsightRecoveryBody(
              snapshot.recoveryScore!,
              _verdictSuffix(l10n, snapshot.recoveryVerdict),
            ),
            severity: severity == AgentArtifactSeverity.info ? null : severity,
            route: HealthRoutes.trend,
            payload: <String, Object?>{
              'score': snapshot.recoveryScore,
              'verdict': snapshot.recoveryVerdict,
            },
          ),
        if (snapshot.avgSleepHours != null)
          AgentInsight(
            id: 'sleep',
            title: l10n.healthAgentWeeklyInsightSleepTitle,
            body: l10n.healthAgentWeeklyInsightSleepBody(
              _round(snapshot.avgSleepHours!),
            ),
            route: HealthRoutes.trend,
            payload: <String, Object?>{
              'avg_sleep_hours': _round(snapshot.avgSleepHours!),
            },
          ),
        if (snapshot.totalSteps > 0)
          AgentInsight(
            id: 'activity',
            title: l10n.healthAgentWeeklyInsightActivityTitle,
            body: l10n.healthAgentWeeklyInsightActivityBody(
              _formatSteps(snapshot.totalSteps),
            ),
            route: HealthRoutes.trend,
            payload: <String, Object?>{'total_steps': snapshot.totalSteps},
          ),
        if (snapshot.workoutCount > 0)
          AgentInsight(
            id: 'workouts',
            title: l10n.healthAgentWeeklyInsightWorkoutsTitle,
            body: l10n.healthAgentWeeklyInsightWorkoutsBody(
              snapshot.workoutCount,
              _round(snapshot.workoutMinutes),
            ),
            route: HealthRoutes.trend,
            payload: <String, Object?>{
              'workout_count': snapshot.workoutCount,
              'workout_minutes': _round(snapshot.workoutMinutes),
            },
          ),
      ],
      evidence: <AgentEvidenceRef>[
        AgentEvidenceRef(
          type: 'health_week',
          id: id,
          label: l10n.healthAgentWeeklyEvidenceLabel,
          route: HealthRoutes.trend,
          payload: <String, Object?>{
            'recovery_score': snapshot.recoveryScore,
            'recovery_verdict': snapshot.recoveryVerdict,
            'avg_sleep_hours': snapshot.avgSleepHours == null
                ? null
                : _round(snapshot.avgSleepHours!),
            'total_steps': snapshot.totalSteps,
            'workout_count': snapshot.workoutCount,
            'workout_minutes': _round(snapshot.workoutMinutes),
          },
        ),
      ],
      actions: <AgentAction>[
        AgentAction(
          kind: 'review',
          label: l10n.healthAgentWeeklyAction,
          intent: kAgentExplainResultIntent,
          objectType: kAgentArtifactObjectType,
          objectId: id,
          route: HealthRoutes.trend,
        ),
      ],
      methodology: localAgentMethodology(
        l10n,
        sourceLabel: l10n.healthAgentWeeklyEvidenceLabel,
      ),
      memoryId: memoryId,
      traceId: traceId,
      createdAt: createdAt.toUtc(),
      expiresAt: createdAt.toUtc().add(const Duration(days: 14)),
    );
  }

  static double _sumInWindow(
    List<HealthMetric> rows,
    DateTime from,
    DateTime to,
  ) {
    var sum = 0.0;
    for (final m in rows) {
      if (m.capturedAt.isBefore(from) || m.capturedAt.isAfter(to)) continue;
      sum += m.value;
    }
    return sum;
  }

  static int _countInWindow(
    List<HealthMetric> rows,
    DateTime from,
    DateTime to,
  ) {
    var n = 0;
    for (final m in rows) {
      if (m.capturedAt.isBefore(from) || m.capturedAt.isAfter(to)) continue;
      n++;
    }
    return n;
  }

  static double _sumWorkoutMinutes(
    List<HealthMetric> rows,
    DateTime from,
    DateTime to,
  ) {
    var sum = 0.0;
    for (final m in rows) {
      if (m.capturedAt.isBefore(from) || m.capturedAt.isAfter(to)) continue;
      sum += switch (m.unit) {
        's' => m.value / 60.0,
        'min' => m.value,
        'h' => m.value * 60.0,
        _ => m.value / 60.0,
      };
    }
    return sum;
  }

  static double? _avgSleepHours(
    List<HealthMetric> rows,
    DateTime from,
    DateTime to,
  ) {
    var sum = 0.0;
    var n = 0;
    for (final m in rows) {
      if (m.capturedAt.isBefore(from) || m.capturedAt.isAfter(to)) continue;
      sum += switch (m.unit) {
        's' => m.value / 3600.0,
        'min' => m.value / 60.0,
        'h' => m.value,
        _ => m.value / 3600.0,
      };
      n++;
    }
    return n == 0 ? null : sum / n;
  }

  static String _formatSteps(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.round().toString();
  }

  static double _round(double v) => (v * 100).round() / 100.0;
}

String _verdictSuffix(AppLocalizations l10n, String? verdict) {
  if (verdict == null || verdict.isEmpty) return '';
  return agentLocaleIsZh(l10n) ? '（$verdict）' : ' ($verdict)';
}

abstract class WeeklySummaryReader {
  Future<WeeklySummarySnapshot> read(AgentContext ctx);
}

class RepositoryWeeklySummaryReader implements WeeklySummaryReader {
  const RepositoryWeeklySummaryReader();

  @override
  Future<WeeklySummarySnapshot> read(AgentContext ctx) async {
    final repo = await ctx.ref.read(healthMetricRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();

    final data = await repo.listByKinds(
      ownerUserId: ownerUserId,
      kinds: const {
        HealthMetricKind.hrvDaily,
        HealthMetricKind.sleepSession,
        HealthMetricKind.rhrDaily,
        HealthMetricKind.stepsDaily,
        HealthMetricKind.workoutSession,
        HealthMetricKind.vo2Max,
      },
      limit: 14,
    );

    final hrv = data[HealthMetricKind.hrvDaily] ?? const [];
    final sleep = data[HealthMetricKind.sleepSession] ?? const [];
    final rhr = data[HealthMetricKind.rhrDaily] ?? const [];
    final steps = data[HealthMetricKind.stepsDaily] ?? const [];
    final workouts = data[HealthMetricKind.workoutSession] ?? const [];
    const scorer = RecoveryScorer();
    final recovery = scorer.score(hrv: hrv, sleep: sleep, rhr: rhr);
    final now = ctx.now;
    final weekFrom = now.subtract(const Duration(days: 7));
    return WeeklySummarySnapshot(
      hasHealthData: hrv.isNotEmpty || sleep.isNotEmpty || steps.isNotEmpty,
      recoveryScore: recovery.hasScore ? recovery.score : null,
      recoveryVerdict: recovery.hasScore ? recovery.verdict : null,
      avgSleepHours: WeeklySummaryAgent._avgSleepHours(sleep, weekFrom, now),
      totalSteps: WeeklySummaryAgent._sumInWindow(steps, weekFrom, now),
      workoutCount: WeeklySummaryAgent._countInWindow(workouts, weekFrom, now),
      workoutMinutes: WeeklySummaryAgent._sumWorkoutMinutes(
        workouts,
        weekFrom,
        now,
      ),
    );
  }
}

class FrbWeeklySummaryReader implements WeeklySummaryReader {
  const FrbWeeklySummaryReader({
    required AgentRuntimeEffectPlanBinding runtime,
    this.fallback = const RepositoryWeeklySummaryReader(),
  }) : _runtime = runtime;

  final AgentRuntimeEffectPlanBinding _runtime;
  final WeeklySummaryReader fallback;

  @override
  Future<WeeklySummarySnapshot> read(AgentContext ctx) async {
    return _runtime.readFromEffectPlan(
      effectPlan: const <AgentRuntimeEffect>[
        AgentRuntimeEffect.tool(name: 'get_recovery_signal'),
        AgentRuntimeEffect.tool(
          name: 'get_recent_sleep_summary',
          input: <String, Object?>{'days_back': 7},
        ),
        AgentRuntimeEffect.tool(
          name: 'get_activity_summary',
          input: <String, Object?>{'days_back': 7},
        ),
      ],
      maxEffectSteps: 3,
      fallback: () => fallback.read(ctx),
      decode: (stepRun) => weeklySummarySnapshotFromTerminalStep(
        stepRun.terminalStep,
        traceId: stepRun.traceId,
      ),
    );
  }
}

class WeeklySummarySnapshot {
  const WeeklySummarySnapshot({
    required this.hasHealthData,
    this.recoveryScore,
    this.recoveryVerdict,
    this.avgSleepHours,
    required this.totalSteps,
    required this.workoutCount,
    required this.workoutMinutes,
    this.traceId,
  });

  final bool hasHealthData;
  final int? recoveryScore;
  final String? recoveryVerdict;
  final double? avgSleepHours;
  final double totalSteps;
  final int workoutCount;
  final double workoutMinutes;
  final String? traceId;

  bool get hasAnySignal =>
      hasHealthData ||
      recoveryScore != null ||
      avgSleepHours != null ||
      totalSteps > 0 ||
      workoutCount > 0;
}

WeeklySummarySnapshot? weeklySummarySnapshotFromTerminalStep(
  Map<String, Object?> step, {
  String? traceId,
}) {
  final byTool = agentRuntimeTerminalEffectResultsByToolName(step);
  final recovery = byTool['get_recovery_signal'];
  final sleep = byTool['get_recent_sleep_summary'];
  final activity = byTool['get_activity_summary'];
  if (recovery == null || sleep == null || activity == null) return null;

  final sleepSummary = _asObject(sleep['summary']);
  final activitySummary = _asObject(activity['summary']);
  if (sleepSummary == null || activitySummary == null) return null;
  final sessions = sleep['sessions'];
  final days = activity['days'];
  if (sessions is! List || days is! List) return null;
  final recoveryScore = _intValue(recovery['score']);
  final recoveryVerdict = recovery['verdict'];
  final avgSleep = _doubleValue(sleepSummary['average_hours']);
  final totalSteps = _doubleValue(activitySummary['total_steps']);
  final workoutCount = _intValue(activitySummary['workout_count']);
  final workoutMinutes = _doubleValue(activitySummary['workout_total_minutes']);
  if (totalSteps == null || workoutCount == null || workoutMinutes == null) {
    return null;
  }
  return WeeklySummarySnapshot(
    hasHealthData:
        sessions.isNotEmpty ||
        days.isNotEmpty ||
        recoveryScore != null ||
        avgSleep != null ||
        totalSteps > 0 ||
        workoutCount > 0,
    recoveryScore: recoveryScore,
    recoveryVerdict: recoveryVerdict is String ? recoveryVerdict : null,
    avgSleepHours: avgSleep == 0 ? null : avgSleep,
    totalSteps: totalSteps,
    workoutCount: workoutCount,
    workoutMinutes: workoutMinutes,
    traceId: traceId,
  );
}

int? _intValue(Object? value) {
  if (value is num) return value.toInt();
  return null;
}

double? _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  return null;
}

Map<String, Object?>? _asObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

/// Riverpod-exposed agent.
final weeklySummaryAgentProvider = Provider<Agent>(
  (ref) => const WeeklySummaryAgent(),
);
