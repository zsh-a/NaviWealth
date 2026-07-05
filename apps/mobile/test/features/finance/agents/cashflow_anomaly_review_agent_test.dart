import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/ai/regression/agent_outcome_evaluator.dart';
import 'package:naviwealth/core/ai/trace/ai_trace_store.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/agents/cashflow_anomaly_review_agent.dart';
import 'package:naviwealth/features/finance/agents/fire_plan_drift_monitor_agent.dart';
import 'package:naviwealth/features/finance/agents/options_income_risk_review_agent.dart';
import 'package:naviwealth/features/finance/agents/providers.dart'
    as finance_agent_providers;
import 'package:naviwealth/features/finance/agents/weekly_wealth_review_agent.dart';
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
      runtime: _runtimeForDb(db),
    );

    expect(result.status, AgentRunStatus.skipped);
    expect(result.summary, 'no cashflow anomaly detected');
    expect(result.artifactId, isNull);
  });

  test('persists deterministic cashflow anomaly artifact', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final runtime = _runtimeForDb(db);
    final store = SqliteAgentArtifactStore(db: db);
    final traceStore = InMemoryAiTraceStore();

    final result = await CashflowAnomalyReviewAgent.synthesize(
      anomaly: const ExpenseAnomalySummary(deltaRatio: 0.62),
      ownerUserId: 'u',
      startedAt: now,
      finishedAt: now.add(const Duration(milliseconds: 20)),
      runtime: runtime,
      artifactStore: store,
      traceStore: traceStore,
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.memoryId, '$kCashflowAnomalyReviewMemorySource:2026-07-05');
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

  test(
    'finance providers include anomaly agent and latest domain artifacts',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final artifactStore = SqliteAgentArtifactStore(db: db);
      await artifactStore.save(
        _artifact(
          id: 'wealth-review',
          agentId: kWeeklyWealthReviewAgentId,
          createdAt: now,
        ),
      );
      await artifactStore.save(
        _artifact(
          id: 'cashflow-anomaly',
          agentId: kCashflowAnomalyReviewAgentId,
          createdAt: now.add(const Duration(minutes: 1)),
          kind: AgentArtifactKind.alert,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue(() async => 'u'),
          agent_providers.agentArtifactStoreProvider.overrideWith(
            (ref) async => artifactStore,
          ),
        ],
      );
      addTearDown(container.dispose);

      final agents = container.read(
        finance_agent_providers.financeAgentsProvider,
      );
      final artifacts = await container.read(
        finance_agent_providers.latestFinanceAgentArtifactsProvider.future,
      );

      expect(agents.map((agent) => agent.id), [
        kWeeklyWealthReviewAgentId,
        kCashflowAnomalyReviewAgentId,
        kFirePlanDriftMonitorAgentId,
        kOptionsIncomeRiskReviewAgentId,
      ]);
      expect(artifacts.map((artifact) => artifact.id), [
        'cashflow-anomaly',
        'wealth-review',
      ]);
    },
  );
}

MemoryRuntime _runtimeForDb(AppDatabase db) {
  return MemoryRuntime(
    embedder: StubEmbedder(),
    memoryStore: SqliteMemoryStore(db: db),
    eventStore: SqliteEventStore(db: db),
  );
}

AgentArtifact _artifact({
  required String id,
  required String agentId,
  required DateTime createdAt,
  AgentArtifactKind kind = AgentArtifactKind.review,
}) {
  return AgentArtifact(
    id: id,
    ownerUserId: 'u',
    agentId: agentId,
    domain: 'finance',
    kind: kind,
    severity: AgentArtifactSeverity.info,
    title: id,
    summary: id,
    createdAt: createdAt,
  );
}
