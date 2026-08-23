/// `recovery_alert` — fires when HRV shows a sustained decline.
///
/// Reads the last 7 days of HRV data and checks for 3+ consecutive days below
/// the rolling average. It emits a temporary artifact; the app-owned attention
/// arbiter owns interruption policy.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_presentation.dart';
import '../../../core/ai/agents/agent_intents.dart';
import '../../../core/ai/agents/agent_l10n.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/runtime/agent_runtime/agent_runtime_effect_plan_binding.dart';
import '../../../core/ai/runtime/agent_runtime/agent_runtime_terminal_output.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/health_route_paths.dart';
import '../data/providers.dart';
import '../domain/health_metric_kind.dart';

const String kRecoveryAlertAgentId = 'recovery_alert';

/// Minimum consecutive below-average days to trigger an alert.
const int kDeclineThresholdDays = 3;

class RecoveryAlertAgent implements Agent {
  const RecoveryAlertAgent({
    this.signalReader = const RepositoryRecoveryAlertSignalReader(),
  });

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
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final l10n = agentL10n(ctx.ref);
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
    final summary = l10n.healthAgentRecoverySummary(
      alert.consecutiveDays,
      _round(alert.avgRecentMs),
      _round(alert.avgBaselineMs),
      _round(alert.declinePct),
    );
    final artifactId = '$kRecoveryAlertAgentId:$dayKey';

    final artifactStore = await ctx.ref.read(
      agent_providers.agentArtifactStoreProvider.future,
    );
    await artifactStore.save(
      _artifact(
        id: artifactId,
        ownerUserId: ownerUserId,
        createdAt: start,
        source: signal.source,
        traceId: signal.traceId,
        alert: alert,
        summary: summary,
        l10n: l10n,
      ),
    );

    return _completedResult(
      startedAt: start,
      summary: summary,
      artifactId: artifactId,
      signal: signal,
      alert: alert,
    );
  }

  static AgentRunResult _completedResult({
    required DateTime startedAt,
    required String summary,
    required String artifactId,
    required RecoveryAlertSignalRead signal,
    required RecoveryAlertSignal alert,
  }) {
    return AgentRunResult(
      agentId: kRecoveryAlertAgentId,
      status: AgentRunStatus.completed,
      startedAt: startedAt,
      finishedAt: DateTime.now().toUtc(),
      summary: summary,
      payload: <String, Object?>{
        'baseline_avg_ms': _round(alert.avgBaselineMs),
        'recent_avg_ms': _round(alert.avgRecentMs),
        'decline_pct': _round(alert.declinePct),
        'consecutive_days': alert.consecutiveDays,
        'signal_source': signal.source,
      },
      artifactId: artifactId,
      traceId: signal.traceId,
    );
  }

  static AgentArtifact _artifact({
    required String id,
    required String ownerUserId,
    required DateTime createdAt,
    required String source,
    required String? traceId,
    required RecoveryAlertSignal alert,
    required String summary,
    required AppLocalizations l10n,
  }) {
    final severity = alert.declinePct >= 20
        ? AgentArtifactSeverity.warning
        : AgentArtifactSeverity.attention;
    return AgentArtifact(
      id: id,
      ownerUserId: ownerUserId,
      agentId: kRecoveryAlertAgentId,
      domain: 'health',
      kind: AgentArtifactKind.alert,
      severity: severity,
      title: l10n.healthAgentRecoveryTitle,
      summary: summary,
      metrics: <AgentMetric>[
        AgentMetric(
          label: l10n.healthAgentRecoveryInsightDeclineTitle,
          value: '-${_round(alert.declinePct)}%',
          context: l10n.healthAgentRecoveryInsightDeclineBody(
            alert.consecutiveDays,
            _round(alert.declinePct),
          ),
          severity: severity,
        ),
      ],
      insights: <AgentInsight>[
        AgentInsight(
          id: 'hrv_decline',
          title: l10n.healthAgentRecoveryInsightDeclineTitle,
          body: l10n.healthAgentRecoveryInsightDeclineBody(
            alert.consecutiveDays,
            _round(alert.declinePct),
          ),
          severity: severity,
          details: <AgentMetric>[
            AgentMetric(
              label: l10n.agentResultMetricCurrent,
              value: '${_round(alert.avgRecentMs)} ms',
              severity: severity,
            ),
            AgentMetric(
              label: l10n.agentResultMetricBaseline,
              value: '${_round(alert.avgBaselineMs)} ms',
            ),
          ],
          evidenceIds: <String>['$source:$id'],
          route: HealthRoutes.trend,
          payload: <String, Object?>{
            'decline_pct': _round(alert.declinePct),
            'consecutive_days': alert.consecutiveDays,
          },
        ),
        AgentInsight(
          id: 'suggested_adjustment',
          title: l10n.healthAgentRecoveryInsightAdjustmentTitle,
          body: l10n.healthAgentRecoveryInsightAdjustmentBody,
          route: HealthRoutes.today,
        ),
      ],
      evidence: <AgentEvidenceRef>[
        AgentEvidenceRef(
          type: 'health_metric_trend',
          id: '$source:$id',
          label: l10n.healthAgentRecoveryEvidenceLabel,
          description: l10n.healthAgentRecoveryInsightDeclineBody(
            alert.consecutiveDays,
            _round(alert.declinePct),
          ),
          route: HealthRoutes.trend,
          payload: <String, Object?>{
            'baseline_avg_ms': _round(alert.avgBaselineMs),
            'recent_avg_ms': _round(alert.avgRecentMs),
            'decline_pct': _round(alert.declinePct),
            'consecutive_days': alert.consecutiveDays,
            'source': source,
          },
        ),
      ],
      actions: <AgentAction>[
        AgentAction(
          kind: 'review',
          label: l10n.healthAgentRecoveryAction,
          intent: kHealthExplainRecoveryAlertIntent,
          objectType: kAgentArtifactObjectType,
          objectId: id,
          route: HealthRoutes.today,
        ),
      ],
      methodology: localAgentMethodology(
        l10n,
        sourceLabel: l10n.healthAgentRecoveryEvidenceLabel,
      ),
      traceId: traceId,
      createdAt: createdAt.toUtc(),
      expiresAt: createdAt.toUtc().add(const Duration(days: 7)),
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
      l10n: agentL10n(ctx.ref),
    );
  }
}

class FrbRecoveryAlertSignalReader implements RecoveryAlertSignalReader {
  const FrbRecoveryAlertSignalReader({
    required AgentRuntimeEffectPlanBinding runtime,
    this.fallback = const RepositoryRecoveryAlertSignalReader(),
  }) : _runtime = runtime;

  final AgentRuntimeEffectPlanBinding _runtime;
  final RecoveryAlertSignalReader fallback;

  @override
  Future<RecoveryAlertSignalRead> read(AgentContext ctx) async {
    return _runtime.readFromEffectPlan(
      effectPlan: const <AgentRuntimeEffect>[
        AgentRuntimeEffect.tool(
          name: 'get_hrv_trend',
          input: <String, Object?>{'window_days': 14},
        ),
      ],
      maxEffectSteps: 1,
      fallback: () => fallback.read(ctx),
      decode: (stepRun) {
        final result = agentRuntimeTerminalEffectResultForTool(
          stepRun.terminalStep,
          'get_hrv_trend',
        );
        final points = _hrvPointsFromToolResult(result);
        if (points == null) return null;
        return recoveryAlertSignalFromValues(
          points,
          source: 'frb_tool:get_hrv_trend',
          traceId: stepRun.traceId,
          l10n: agentL10n(ctx.ref),
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
    this.traceId,
  });

  factory RecoveryAlertSignalRead.alert({
    required String source,
    required RecoveryAlertSignal alert,
    String? traceId,
  }) {
    return RecoveryAlertSignalRead._(
      source: source,
      alert: alert,
      traceId: traceId,
    );
  }

  factory RecoveryAlertSignalRead.skipped({
    required String source,
    required String reason,
    String? traceId,
  }) {
    return RecoveryAlertSignalRead._(
      source: source,
      skipReason: reason,
      traceId: traceId,
    );
  }

  final String source;
  final RecoveryAlertSignal? alert;
  final String? skipReason;
  final String? traceId;
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
  String? traceId,
  AppLocalizations? l10n,
}) {
  final strings = l10n ?? defaultAgentL10n();
  if (points.length < 4) {
    return RecoveryAlertSignalRead.skipped(
      source: source,
      reason: strings.healthAgentRecoverySkipInsufficient(points.length),
      traceId: traceId,
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
      reason: strings.healthAgentRecoverySkipNoDecline,
      traceId: traceId,
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
    traceId: traceId,
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
