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
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../data/providers.dart';
import '../data/recovery_scorer.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

const String kWeeklySummaryAgentId = 'weekly_summary';
const String kWeeklySummaryMemorySource = 'agent:weekly_summary';

class WeeklySummaryAgent implements Agent {
  const WeeklySummaryAgent();

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

    if (hrv.isEmpty && sleep.isEmpty && steps.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kWeeklySummaryAgentId,
        startedAt: start,
        finishedAt: DateTime.now().toUtc(),
        reason: 'no health data this week',
      );
    }

    // Compute recovery.
    const scorer = RecoveryScorer();
    final recovery = scorer.score(hrv: hrv, sleep: sleep, rhr: rhr);

    // Aggregate weekly stats.
    final now = ctx.now;
    final weekFrom = now.subtract(const Duration(days: 7));
    final weekSteps = _sumInWindow(steps, weekFrom, now);
    final weekWorkouts = _countInWindow(workouts, weekFrom, now);
    final weekWorkoutMin = _sumWorkoutMinutes(workouts, weekFrom, now);
    final avgSleep = _avgSleepHours(sleep, weekFrom, now);

    // Build summary.
    final parts = <String>[];
    if (recovery.hasScore) {
      parts.add('Recovery ${recovery.score}/100 (${recovery.verdict})');
    }
    if (avgSleep != null) {
      parts.add('avg sleep ${_round(avgSleep)}h');
    }
    if (weekSteps > 0) {
      parts.add('${_formatSteps(weekSteps)} steps');
    }
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
          'recovery_score': recovery.score,
          'recovery_verdict': recovery.verdict,
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
        'recovery_score': recovery.score,
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

/// Riverpod-exposed agent.
final weeklySummaryAgentProvider = Provider<Agent>(
  (ref) => const WeeklySummaryAgent(),
);
