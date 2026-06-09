/// `recovery_alert` — fires when HRV shows a sustained decline.
///
/// Runs daily after the Morning Briefing. Reads the last 7 days of HRV
/// data and checks for 3+ consecutive days below the rolling average.
/// When triggered, writes an episodic memory and optionally sends a
/// local notification recommending lighter activity.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../../../core/notifications/notification_service.dart';
import '../data/providers.dart';
import '../domain/health_metric_kind.dart';

const String kRecoveryAlertAgentId = 'recovery_alert';
const String kRecoveryAlertMemorySource = 'agent:recovery_alert';

/// Minimum consecutive below-average days to trigger an alert.
const int kDeclineThresholdDays = 3;

class RecoveryAlertAgent implements Agent {
  const RecoveryAlertAgent({this.notifier});

  final NotificationService? notifier;

  @override
  String get id => kRecoveryAlertAgentId;

  @override
  String get name => 'Recovery Alert';

  @override
  AgentSchedule get schedule => const AgentSchedule.daily(hourLocal: 8);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final start = ctx.now;
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final repo = await ctx.ref.read(healthMetricRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();

    // Fetch last 10 days of HRV to have enough for a rolling average.
    final rows = await repo.listByKind(
      ownerUserId: ownerUserId,
      kind: HealthMetricKind.hrvDaily,
      limit: 10,
    );

    if (rows.length < 4) {
      return AgentRunResult.skipped(
        agentId: kRecoveryAlertAgentId,
        startedAt: start,
        finishedAt: DateTime.now().toUtc(),
        reason: 'insufficient HRV data (${rows.length} points)',
      );
    }

    // Sort oldest-first for chronological analysis.
    final sorted = rows.toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

    // Compute rolling average of all but the last 3 days.
    final baseline = sorted.take(sorted.length - kDeclineThresholdDays);
    final avgBaseline =
        baseline.map((m) => m.value).reduce((a, b) => a + b) / baseline.length;

    // Check if the last N days are all below the baseline.
    final recent = sorted.skip(sorted.length - kDeclineThresholdDays).toList();
    final allBelow = recent.every((m) => m.value < avgBaseline);

    if (!allBelow) {
      return AgentRunResult.skipped(
        agentId: kRecoveryAlertAgentId,
        startedAt: start,
        finishedAt: DateTime.now().toUtc(),
        reason: 'no sustained HRV decline detected',
      );
    }

    // Compute the decline magnitude.
    final avgRecent =
        recent.map((m) => m.value).reduce((a, b) => a + b) / recent.length;
    final declinePct = ((avgBaseline - avgRecent) / avgBaseline) * 100;

    final dayKey = AppFormatters.utcDayKey(start);
    final summary =
        'HRV has been below your baseline for ${recent.length} days '
        '(${_round(avgRecent)} ms vs ${_round(avgBaseline)} ms average, '
        '${_round(declinePct)}% decline). Consider lighter activity today.';

    // Persist memory.
    final memoryId = '$kRecoveryAlertMemorySource:$dayKey';
    final memory = MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      scope: 'health',
      source: kRecoveryAlertMemorySource,
      sourceId: dayKey,
      title: 'Recovery Alert · $dayKey',
      summary: summary,
      payload: <String, Object?>{
        'context': 'HRV decline detected at ${start.toUtc().toIso8601String()}',
        'decision': 'recommend lighter activity',
        'reasoning': '${recent.length} consecutive days below baseline',
        'outcome': <String, Object?>{
          'baseline_avg_ms': _round(avgBaseline),
          'recent_avg_ms': _round(avgRecent),
          'decline_pct': _round(declinePct),
          'consecutive_days': recent.length,
        },
      },
      entities: <String>{'recovery_alert', 'hrv_decline', dayKey},
      importance: 0.7,
      confidence: 0.8,
      validFrom: start.toUtc(),
      createdAt: start.toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    await runtime.remember(memory);

    // Notify.
    if (notifier != null) {
      try {
        if (await notifier!.hasPermissions()) {
          await notifier!.showNow(
            id: HealthNotifications.idForRecoveryAlert(start.toLocal()),
            title: 'Recovery Alert',
            body: 'HRV down ${_round(declinePct)}% over ${recent.length} days. '
                'Consider lighter activity today.',
            payload: 'recovery_alert',
          );
        }
      } on Object {
        // Best-effort.
      }
    }

    return AgentRunResult(
      agentId: kRecoveryAlertAgentId,
      status: AgentRunStatus.completed,
      startedAt: start,
      finishedAt: DateTime.now().toUtc(),
      summary: summary,
      payload: <String, Object?>{
        'baseline_avg_ms': _round(avgBaseline),
        'recent_avg_ms': _round(avgRecent),
        'decline_pct': _round(declinePct),
        'consecutive_days': recent.length,
      },
      memoryId: memoryId,
    );
  }

  static double _round(double v) => (v * 100).round() / 100.0;
}

/// Riverpod-exposed agent.
final recoveryAlertAgentProvider = Provider<Agent>(
  (ref) => const RecoveryAlertAgent(),
);
