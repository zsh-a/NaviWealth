/// `weekly_summary` — produces a weekly health overview.
///
/// Runs every Sunday evening. Aggregates the week's sleep, HRV, steps,
/// and workout data into a concise summary memory record.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_terminal_output.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
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

    final snapshot = await summaryReader.read(ctx);

    if (!snapshot.hasAnySignal) {
      return AgentRunResult.skipped(
        agentId: kWeeklySummaryAgentId,
        startedAt: start,
        finishedAt: DateTime.now().toUtc(),
        reason: 'no health data this week',
      );
    }

    // Build summary.
    final parts = <String>[];
    final recoveryScore = snapshot.recoveryScore;
    final recoveryVerdict = snapshot.recoveryVerdict;
    if (recoveryScore != null && recoveryVerdict != null) {
      parts.add('Recovery $recoveryScore/100 ($recoveryVerdict)');
    }
    final avgSleep = snapshot.avgSleepHours;
    if (avgSleep != null) {
      parts.add('avg sleep ${_round(avgSleep)}h');
    }
    final weekSteps = snapshot.totalSteps;
    if (weekSteps > 0) {
      parts.add('${_formatSteps(weekSteps)} steps');
    }
    final weekWorkouts = snapshot.workoutCount;
    final weekWorkoutMin = snapshot.workoutMinutes;
    if (weekWorkouts > 0) {
      parts.add('$weekWorkouts workouts (${_round(weekWorkoutMin)} min)');
    }

    if (parts.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kWeeklySummaryAgentId,
        startedAt: start,
        finishedAt: DateTime.now().toUtc(),
        reason: 'no actionable signals this week',
      );
    }

    final summary = 'This week: ${parts.join(' · ')}.';
    final dayKey = AppFormatters.utcDayKey(start);
    final memoryId = '$kWeeklySummaryMemorySource:$dayKey';

    final memory = MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      scope: '*',
      source: kWeeklySummaryMemorySource,
      sourceId: dayKey,
      title: 'Weekly Summary · $dayKey',
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
        },
      },
      entities: <String>{'weekly_summary', 'health', dayKey},
      importance: 0.6,
      confidence: 0.8,
      validFrom: start.toUtc(),
      createdAt: start.toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    await runtime.remember(memory);

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
      },
      memoryId: memoryId,
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
      decode: weeklySummarySnapshotFromTerminalStep,
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
  });

  final bool hasHealthData;
  final int? recoveryScore;
  final String? recoveryVerdict;
  final double? avgSleepHours;
  final double totalSteps;
  final int workoutCount;
  final double workoutMinutes;

  bool get hasAnySignal =>
      hasHealthData ||
      recoveryScore != null ||
      avgSleepHours != null ||
      totalSteps > 0 ||
      workoutCount > 0;
}

WeeklySummarySnapshot? weeklySummarySnapshotFromTerminalStep(
  Map<String, Object?> step,
) {
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
