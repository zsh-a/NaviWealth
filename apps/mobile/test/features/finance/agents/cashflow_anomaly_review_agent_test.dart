import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/regression/agent_outcome_evaluator.dart';
import 'package:naviwealth/core/ai/trace/ai_trace_store.dart';
import 'package:naviwealth/features/finance/agents/cashflow_anomaly_review_agent.dart';
import 'package:naviwealth/features/finance/expense/data/expense_anomaly_insight_provider.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  final now = DateTime.utc(2026, 7, 5, 20);

  test('skips when there is no cashflow anomaly', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    final result = await CashflowAnomalyReviewAgent.synthesize(
      anomaly: null,
      ownerUserId: 'u',
      startedAt: now,
      finishedAt: now.add(const Duration(milliseconds: 20)),
    );

    expect(result.status, AgentRunStatus.skipped);
    expect(result.summary, 'no cashflow anomaly detected');
    expect(result.artifactId, isNull);
    final failures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'finance.cashflow_anomaly_review.no_finding',
      ),
      result: result,
    );
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('persists deterministic cashflow anomaly artifact', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentArtifactStore(db: db);
    final traceStore = InMemoryAiTraceStore();

    final result = await CashflowAnomalyReviewAgent.synthesize(
      anomaly: const ExpenseAnomalySummary(deltaRatio: 0.62),
      ownerUserId: 'u',
      startedAt: now,
      finishedAt: now.add(const Duration(milliseconds: 20)),
      artifactStore: store,
      traceStore: traceStore,
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.memoryId, isNull);
    expect(result.artifactId, '$kCashflowAnomalyReviewAgentId:2026-07-05');
    expect(result.traceId, '$kCashflowAnomalyReviewAgentId:trace:2026-07-05');
    expect(result.summary, contains('+62%'));
    expect(result.payload['delta_pct'], 62);

    final artifact = await store.read(result.artifactId!);
    expect(artifact, isNotNull);
    expect(artifact!.domain, 'finance');
    expect(artifact.kind, AgentArtifactKind.alert);
    expect(artifact.severity, AgentArtifactSeverity.warning);
    expect(artifact.actions.single.intent, 'agent.explainResult');
    expect(artifact.evidence.single.type, 'anomaly_flag');
    expect(artifact.evidence.single.id, 'expense_monthly_spike|2026-07');
    final outcomeFailures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'finance.cashflow_anomaly_review.ready',
      ),
      result: result,
      artifact: artifact,
    );
    expect(outcomeFailures, isEmpty, reason: outcomeFailures.join('\n'));
    final noLlmFallbackFailures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'finance.cashflow_anomaly_review.no_llm_profile_fallback',
      ),
      result: result,
      artifact: artifact,
    );
    expect(
      noLlmFallbackFailures,
      isEmpty,
      reason: noLlmFallbackFailures.join('\n'),
    );

    final trace = await traceStore.findByRequestId(result.traceId!);
    expect(trace, isNotNull);
    expect(trace!.routingReason, kDeterministicAgentRoutingReason);
    expect(trace.intent.domain, kDomainFinance);
    expect(trace.intent.label, 'cashflow_anomaly_review');
    expect(trace.spans.single.attributes, containsPair('deterministic', true));
    expect(trace.spans.single.attributes, containsPair('delta_pct', 62));
  });
}
