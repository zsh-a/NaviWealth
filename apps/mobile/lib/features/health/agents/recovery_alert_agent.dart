/// `recovery_alert` — fires when HRV shows a sustained decline.
///
/// Runs daily after the Morning Briefing. Reads the last 7 days of HRV
/// data and checks for 3+ consecutive days below the rolling average.
/// When triggered, writes an episodic memory and optionally sends a
/// local notification recommending lighter activity.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/agent_runtime/agent_runtime_terminal_output.dart';
import '../../../app/agent_runtime/agent_runtime_tool_plan_binding.dart';
import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../../../core/notifications/notification_service.dart';
import '../data/providers.dart';
import '../domain/health_metric_kind.dart';
import 'health_notifications.dart';

const String kRecoveryAlertAgentId = 'recovery_alert';
const String kRecoveryAlertMemorySource = 'agent:recovery_alert';

/// Minimum consecutive below-average days to trigger an alert.
const int kDeclineThresholdDays = 3;

class RecoveryAlertAgent implements Agent {
  const RecoveryAlertAgent({
    this.notifier,
    this.signalReader = const RepositoryRecoveryAlertSignalReader(),
  });

  final NotificationService? notifier;
  final RecoveryAlertSignalReader signalReader;

  @override
  String get id => kRecoveryAlertAgentId;

  @override
  String get name => 'Recovery Alert';

  @override
  AgentSchedule get schedule => AgentSchedule.daily(hourLocal: 8);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final start = ctx.now;
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final signal = await signalReader.read(ctx);

    if (signal.skipReason != null) {
      return AgentRunResult.skipped(
        agentId: kRecoveryAlertAgentId,
        startedAt: start,
        finishedAt: DateTime.now().toUtc(),
        reason: signal.skipReason!,
      );
    }

    final alert = signal.alert!;

    final dayKey = AppFormatters.utcDayKey(start);
    final summary =
        'HRV has been below your baseline for ${alert.consecutiveDays} days '
        '(${_round(alert.avgRecentMs)} ms vs ${_round(alert.avgBaselineMs)} ms average, '
        '${_round(alert.declinePct)}% decline). Consider lighter activity today.';

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
        'reasoning': '${alert.consecutiveDays} consecutive days below baseline',
        'outcome': <String, Object?>{
          'baseline_avg_ms': _round(alert.avgBaselineMs),
          'recent_avg_ms': _round(alert.avgRecentMs),
          'decline_pct': _round(alert.declinePct),
          'consecutive_days': alert.consecutiveDays,
          'signal_source': signal.source,
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
            body:
                'HRV down ${_round(alert.declinePct)}% over ${alert.consecutiveDays} days. '
                'Consider lighter activity today.',
            payload: 'recovery_alert',
            channel: kHealthBriefingNotificationChannel,
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
        'baseline_avg_ms': _round(alert.avgBaselineMs),
        'recent_avg_ms': _round(alert.avgRecentMs),
        'decline_pct': _round(alert.declinePct),
        'consecutive_days': alert.consecutiveDays,
        'signal_source': signal.source,
      },
      memoryId: memoryId,
    );
  }

  static double _round(double v) => (v * 100).round() / 100.0;
}

abstract class RecoveryAlertSignalReader {
  Future<RecoveryAlertSignalRead> read(AgentContext ctx);
}

class RepositoryRecoveryAlertSignalReader implements RecoveryAlertSignalReader {
  const RepositoryRecoveryAlertSignalReader();

  @override
  Future<RecoveryAlertSignalRead> read(AgentContext ctx) async {
    final repo = await ctx.ref.read(healthMetricRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final rows = await repo.listByKind(
      ownerUserId: ownerUserId,
      kind: HealthMetricKind.hrvDaily,
      limit: 10,
    );
    return recoveryAlertSignalFromValues(
      rows.map((m) => RecoveryAlertHrvPoint(m.capturedAt, m.value)).toList(),
      source: 'repository',
    );
  }
}

class FrbRecoveryAlertSignalReader implements RecoveryAlertSignalReader {
  const FrbRecoveryAlertSignalReader({
    required AgentRuntimeToolPlanBinding runtime,
    this.fallback = const RepositoryRecoveryAlertSignalReader(),
  }) : _runtime = runtime;

  final AgentRuntimeToolPlanBinding _runtime;
  final RecoveryAlertSignalReader fallback;

  @override
  Future<RecoveryAlertSignalRead> read(AgentContext ctx) async {
    return _runtime.readFromToolPlan(
      toolPlan: const <Map<String, Object?>>[
        <String, Object?>{
          'name': 'get_hrv_trend',
          'input': <String, Object?>{'window_days': 14},
        },
      ],
      maxToolSteps: 1,
      fallback: () => fallback.read(ctx),
      decode: (terminalStep) {
        final result = agentRuntimeTerminalToolResult(
          terminalStep,
          'get_hrv_trend',
        );
        final points = _hrvPointsFromToolResult(result);
        if (points == null) return null;
        return recoveryAlertSignalFromValues(
          points,
          source: 'frb_tool:get_hrv_trend',
        );
      },
    );
  }
}

class RecoveryAlertSignalRead {
  const RecoveryAlertSignalRead._({
    required this.source,
    this.alert,
    this.skipReason,
  });

  factory RecoveryAlertSignalRead.alert({
    required String source,
    required RecoveryAlertSignal alert,
  }) {
    return RecoveryAlertSignalRead._(source: source, alert: alert);
  }

  factory RecoveryAlertSignalRead.skipped({
    required String source,
    required String reason,
  }) {
    return RecoveryAlertSignalRead._(source: source, skipReason: reason);
  }

  final String source;
  final RecoveryAlertSignal? alert;
  final String? skipReason;
}

class RecoveryAlertSignal {
  const RecoveryAlertSignal({
    required this.avgBaselineMs,
    required this.avgRecentMs,
    required this.declinePct,
    required this.consecutiveDays,
  });

  final double avgBaselineMs;
  final double avgRecentMs;
  final double declinePct;
  final int consecutiveDays;
}

class RecoveryAlertHrvPoint {
  const RecoveryAlertHrvPoint(this.capturedAt, this.valueMs);

  final DateTime capturedAt;
  final double valueMs;
}

RecoveryAlertSignalRead recoveryAlertSignalFromValues(
  List<RecoveryAlertHrvPoint> points, {
  required String source,
}) {
  if (points.length < 4) {
    return RecoveryAlertSignalRead.skipped(
      source: source,
      reason: 'insufficient HRV data (${points.length} points)',
    );
  }

  final sorted = points.toList()
    ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  final baseline = sorted.take(sorted.length - kDeclineThresholdDays);
  final avgBaseline =
      baseline.map((m) => m.valueMs).reduce((a, b) => a + b) / baseline.length;
  final recent = sorted.skip(sorted.length - kDeclineThresholdDays).toList();
  final allBelow = recent.every((m) => m.valueMs < avgBaseline);

  if (!allBelow) {
    return RecoveryAlertSignalRead.skipped(
      source: source,
      reason: 'no sustained HRV decline detected',
    );
  }

  final avgRecent =
      recent.map((m) => m.valueMs).reduce((a, b) => a + b) / recent.length;
  final declinePct = ((avgBaseline - avgRecent) / avgBaseline) * 100;
  return RecoveryAlertSignalRead.alert(
    source: source,
    alert: RecoveryAlertSignal(
      avgBaselineMs: avgBaseline,
      avgRecentMs: avgRecent,
      declinePct: declinePct,
      consecutiveDays: recent.length,
    ),
  );
}

Map<String, Object?>? _asObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

List<RecoveryAlertHrvPoint>? _hrvPointsFromToolResult(
  Map<String, Object?>? result,
) {
  final rawPoints = result?['points'];
  if (rawPoints is! List) return null;
  final points = <RecoveryAlertHrvPoint>[];
  for (final raw in rawPoints) {
    final point = _asObject(raw);
    final date = point?['date'];
    final hrv = point?['hrv_ms'];
    if (date is! String || hrv is! num) return null;
    final parsed = DateTime.tryParse('${date}T00:00:00Z');
    if (parsed == null) return null;
    points.add(RecoveryAlertHrvPoint(parsed, hrv.toDouble()));
  }
  return points;
}

/// Riverpod-exposed agent.
final recoveryAlertAgentProvider = Provider<Agent>(
  (ref) => const RecoveryAlertAgent(),
);
