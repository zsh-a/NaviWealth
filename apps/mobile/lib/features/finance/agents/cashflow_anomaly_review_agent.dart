/// `cashflow_anomaly_review` — deterministic FinanceOS anomaly agent.
///
/// Reuses the existing device expense anomaly detector and turns its
/// `AnalyticalUpload` shape into the unified agent artifact contract. The
/// agent does not call an LLM; the detector is the source of truth.
library;

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_store.dart';
import '../../../core/ai/agents/agent_intents.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/ai/trace/ai_trace_store.dart';
import '../../../core/ai/trace/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../expense/data/expense_anomaly_insight_provider.dart';

const String kCashflowAnomalyReviewAgentId = 'cashflow_anomaly_review';
const String kCashflowAnomalyReviewMemorySource =
    'agent:cashflow_anomaly_review';

class CashflowAnomalyReviewAgent implements Agent {
  const CashflowAnomalyReviewAgent({
    this.reader = const ProviderCashflowAnomalyReviewReader(),
  });

  final CashflowAnomalyReviewReader reader;

  @override
  String get id => kCashflowAnomalyReviewAgentId;

  @override
  String get name => 'Cashflow Anomaly Review';

  @override
  AgentSchedule get schedule =>
      const AgentSchedule(interval: Duration(days: 1), preferredHourLocal: 20);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final startedAt = ctx.now;
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final artifactStore = await ctx.ref.read(
      agent_providers.agentArtifactStoreProvider.future,
    );
    final traceStore = ctx.ref.read(aiTraceStoreProvider);
    final anomaly = await reader.read(ctx);
    return synthesize(
      anomaly: anomaly,
      ownerUserId: ownerUserId,
      startedAt: startedAt,
      finishedAt: DateTime.now().toUtc(),
      runtime: runtime,
      artifactStore: artifactStore,
      traceStore: traceStore,
    );
  }

  static Future<AgentRunResult> synthesize({
    required ExpenseAnomalySummary? anomaly,
    required String ownerUserId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required MemoryRuntime runtime,
    AgentArtifactStore? artifactStore,
    AiTraceStore? traceStore,
  }) async {
    if (anomaly == null) {
      return AgentRunResult.skipped(
        agentId: kCashflowAnomalyReviewAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: 'no cashflow anomaly detected',
      );
    }

    final analysis = CashflowAnomalyAnalysis.fromSummary(
      anomaly,
      detectedAt: startedAt,
    );
    final dayKey = AppFormatters.utcDayKey(startedAt);
    final memoryId = '$kCashflowAnomalyReviewMemorySource:$dayKey';
    final artifactId = '$kCashflowAnomalyReviewAgentId:$dayKey';
    final traceId = '$kCashflowAnomalyReviewAgentId:trace:$dayKey';
    final summary = analysis.summary;
    final memory = MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      scope: 'finance',
      source: kCashflowAnomalyReviewMemorySource,
      sourceId: dayKey,
      title: 'Cashflow anomaly review · $dayKey',
      summary: summary,
      payload: <String, Object?>{
        'context':
            'cashflow anomaly review run at ${startedAt.toUtc().toIso8601String()}',
        'outcome': analysis.toPayload(),
        'artifact_id': artifactId,
        if (traceStore != null) 'trace_id': traceId,
      },
      entities: <String>{
        'finance',
        'cashflow',
        'expense',
        'anomaly',
        analysis.upload.id,
        dayKey,
      },
      importance: analysis.severity == AgentArtifactSeverity.warning
          ? 0.76
          : 0.64,
      confidence: 0.9,
      validFrom: startedAt.toUtc(),
      createdAt: startedAt.toUtc(),
      updatedAt: finishedAt.toUtc(),
    );
    await runtime.remember(memory);
    await traceStore?.append(
      analysis.toTrace(
        requestId: traceId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        artifactId: artifactId,
      ),
    );
    await artifactStore?.save(
      analysis.toArtifact(
        id: artifactId,
        ownerUserId: ownerUserId,
        memoryId: memoryId,
        traceId: traceStore == null ? null : traceId,
        createdAt: startedAt,
      ),
    );

    return AgentRunResult(
      agentId: kCashflowAnomalyReviewAgentId,
      status: AgentRunStatus.completed,
      startedAt: startedAt,
      finishedAt: finishedAt,
      summary: summary,
      payload: analysis.toPayload(),
      memoryId: memoryId,
      artifactId: artifactStore == null ? null : artifactId,
      traceId: traceStore == null ? null : traceId,
    );
  }
}

abstract class CashflowAnomalyReviewReader {
  Future<ExpenseAnomalySummary?> read(AgentContext ctx);
}

class ProviderCashflowAnomalyReviewReader
    implements CashflowAnomalyReviewReader {
  const ProviderCashflowAnomalyReviewReader();

  @override
  Future<ExpenseAnomalySummary?> read(AgentContext ctx) async {
    return ctx.ref.read(expenseAnomalyInsightProvider);
  }
}

class CashflowAnomalyAnalysis {
  const CashflowAnomalyAnalysis({
    required this.anomaly,
    required this.upload,
    required this.detectedAt,
    required this.severity,
  });

  factory CashflowAnomalyAnalysis.fromSummary(
    ExpenseAnomalySummary anomaly, {
    required DateTime detectedAt,
  }) {
    final upload = analyticalAnomalyUpload(anomaly, now: detectedAt)!;
    final abs = anomaly.deltaRatio.abs();
    final severity = abs > 0.5
        ? AgentArtifactSeverity.warning
        : AgentArtifactSeverity.attention;
    return CashflowAnomalyAnalysis(
      anomaly: anomaly,
      upload: upload,
      detectedAt: detectedAt.toUtc(),
      severity: severity,
    );
  }

  final ExpenseAnomalySummary anomaly;
  final AnalyticalUpload upload;
  final DateTime detectedAt;
  final AgentArtifactSeverity severity;

  int get deltaPct => (anomaly.deltaRatio * 100).round();

  String get direction => anomaly.deltaRatio >= 0 ? 'higher' : 'lower';

  String get summary {
    return 'Cashflow anomaly review: projected monthly spending is '
        '${Fmt.signedPercent(anomaly.deltaRatio, decimalDigits: 0)} '
        'vs. the previous 3-month average.';
  }

  Map<String, Object?> toPayload() => <String, Object?>{
    'anomaly_id': upload.id,
    'category': upload.payload['category'],
    'kind': upload.payload['kind'],
    'delta_pct': deltaPct,
    'delta_ratio': anomaly.deltaRatio,
    'severity': upload.payload['severity'],
    'detected_at': detectedAt.toIso8601String(),
  };

  AgentArtifact toArtifact({
    required String id,
    required String ownerUserId,
    required String memoryId,
    required String? traceId,
    required DateTime createdAt,
  }) {
    return AgentArtifact(
      id: id,
      ownerUserId: ownerUserId,
      agentId: kCashflowAnomalyReviewAgentId,
      domain: 'finance',
      kind: AgentArtifactKind.alert,
      severity: severity,
      title: 'Cashflow Anomaly Review',
      summary: summary,
      insights: <AgentInsight>[
        AgentInsight(
          title: 'Monthly spending projection',
          body:
              'Current-month spending is projected $direction than the previous 3-month average by '
              '${Fmt.signedPercent(anomaly.deltaRatio, decimalDigits: 0)}.',
          severity: severity,
          payload: toPayload(),
        ),
        const AgentInsight(
          title: 'Detector source',
          body:
              'This result comes from the on-device anomaly detector used by get_anomaly_flags.',
          payload: <String, Object?>{
            'source': 'expenseAnomalyInsightProvider',
            'read_model': 'anomaly_flags',
          },
        ),
      ],
      evidence: <AgentEvidenceRef>[
        AgentEvidenceRef(
          type: 'anomaly_flag',
          id: upload.id,
          label: 'Monthly expense anomaly',
          payload: upload.payload,
        ),
      ],
      actions: <AgentAction>[
        AgentAction(
          kind: 'review',
          label: 'Review anomaly',
          intent: kAgentExplainResultIntent,
          objectType: kAgentArtifactObjectType,
          objectId: id,
        ),
      ],
      memoryId: memoryId,
      traceId: traceId,
      createdAt: createdAt.toUtc(),
      expiresAt: createdAt.toUtc().add(const Duration(days: 7)),
    );
  }

  AiTrace toTrace({
    required String requestId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required String artifactId,
  }) {
    final durationMs = finishedAt
        .toUtc()
        .difference(startedAt.toUtc())
        .inMilliseconds
        .clamp(0, 1 << 31)
        .toInt();
    return AiTrace(
      requestId: requestId,
      startedAtIso: startedAt.toUtc().toIso8601String(),
      intent: const IntentHint(
        capability: Capability.analyze,
        risk: RiskLevel.info,
        label: 'cashflow_anomaly_review',
        domain: kDomainFinance,
      ),
      backend: Backend.device,
      budgetTier: BudgetTier.small,
      routingReason: kDeterministicAgentRoutingReason,
      totalDurationMs: durationMs,
      spans: <AiSpan>[
        AiSpan(
          id: kTurnSpanId,
          kind: AiSpanKind.turn,
          name: 'turn',
          startOffsetMs: 0,
          durationMs: durationMs,
          attributes: <String, Object?>{
            'agent_id': kCashflowAnomalyReviewAgentId,
            'surface': 'finance_home',
            'artifact_id': artifactId,
            'deterministic': true,
            'anomaly_id': upload.id,
            'delta_pct': deltaPct,
            'detector_severity': upload.payload['severity'],
          },
        ),
      ],
    );
  }
}
