import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/regression/agent_outcome_evaluator.dart';
import 'package:naviwealth/core/ai/trace/ai_trace_store.dart';
import 'package:naviwealth/features/finance/agents/fire_plan_drift_monitor_agent.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_goal.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_plan.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_review.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_review_engine.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_state.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_state_service.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_stress_test_engine.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  final now = DateTime.utc(2026, 7, 5, 19);

  test('skips when no FIRE review is available', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    final result = await FirePlanDriftMonitorAgent.synthesize(
      review: null,
      ownerUserId: 'u',
      startedAt: now,
      finishedAt: now.add(const Duration(milliseconds: 20)),
    );

    expect(result.status, AgentRunStatus.skipped);
    expect(result.summary, 'no FIRE plan configured');
    expect(result.artifactId, isNull);
  });

  test('skips healthy FIRE reviews without warning findings', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final review = generateReview(
      kind: FireReviewKind.monthly,
      state: _state(),
      now: now,
    );

    final result = await FirePlanDriftMonitorAgent.synthesize(
      review: review,
      ownerUserId: 'u',
      startedAt: now,
      finishedAt: now.add(const Duration(milliseconds: 20)),
    );

    expect(result.status, AgentRunStatus.skipped);
    expect(result.summary, 'no FIRE plan drift detected');
    expect(result.artifactId, isNull);
    final failures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'finance.fire_plan_drift_monitor.no_finding',
      ),
      result: result,
    );
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('persists deterministic FIRE drift artifact', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentArtifactStore(db: db);
    final traceStore = InMemoryAiTraceStore();
    final state = _state(
      investable: '400000',
      liquid: '12000',
      etaMonths: null,
    );
    final stressTests = runStressTests(state);
    final review = generateReview(
      kind: FireReviewKind.monthly,
      state: state,
      stressTests: stressTests,
      now: now,
    );

    final result = await FirePlanDriftMonitorAgent.synthesize(
      review: review,
      ownerUserId: 'u',
      startedAt: now,
      finishedAt: now.add(const Duration(milliseconds: 20)),
      stressTests: stressTests,
      artifactStore: store,
      traceStore: traceStore,
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.memoryId, isNull);
    expect(result.artifactId, '$kFirePlanDriftMonitorAgentId:2026-07-05');
    expect(result.traceId, '$kFirePlanDriftMonitorAgentId:trace:2026-07-05');
    expect(result.payload['finding_count'], greaterThan(0));

    final artifact = await store.read(result.artifactId!);
    expect(artifact, isNotNull);
    expect(artifact!.domain, 'finance');
    expect(artifact.kind, AgentArtifactKind.review);
    expect(artifact.severity, AgentArtifactSeverity.warning);
    expect(artifact.actions.single.route, FinanceRoutes.planFire);
    expect(artifact.actions.single.intent, isNull);
    expect(artifact.metrics.map((metric) => metric.value), [
      '12.0%',
      '4.0%',
      '3.0 months',
    ]);
    expect(artifact.methodology?.title, 'Deterministic on-device calculation');
    expect(
      artifact.evidence.map((ref) => ref.type),
      containsAll(['fire_review', 'fire_finding']),
    );
    expect(
      artifact.insights.map((insight) => insight.title),
      contains('Withdrawal rate above safe rate'),
    );
    expect(
      artifact.insights.map((insight) => insight.id),
      contains('stress_tests'),
    );
    expect(
      artifact.insights.expand((insight) => [insight.title, insight.body]),
      everyElement(isNot(contains('market_drawdown'))),
    );
    expect(
      artifact.evidence.map((ref) => ref.id).toSet().length,
      artifact.evidence.length,
    );
    final outcomeFailures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'finance.fire_plan_drift_monitor.ready',
      ),
      result: result,
      artifact: artifact,
    );
    expect(outcomeFailures, isEmpty, reason: outcomeFailures.join('\n'));
    final noLlmFallbackFailures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'finance.fire_plan_drift_monitor.no_llm_profile_fallback',
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
    expect(trace.intent.label, 'fire_plan_drift_monitor');
    expect(trace.spans.single.attributes, containsPair('deterministic', true));
  });

  test('renders Chinese FIRE metrics without placeholder drift', () {
    final state = _state(
      investable: '400000',
      liquid: '12000',
      etaMonths: null,
    );
    final review = generateReview(
      kind: FireReviewKind.monthly,
      state: state,
      now: now,
    );
    final artifact = FirePlanDriftAnalysis.fromReview(review).toArtifact(
      id: 'fire-zh',
      ownerUserId: 'u',
      traceId: null,
      createdAt: now,
      l10n: lookupAppLocalizations(const Locale('zh')),
    );

    expect(artifact.summary, '当前提取率 12.0%，安全线 4.0%');
    expect(artifact.metrics.map((metric) => metric.value), [
      '12.0%',
      '4.0%',
      '3.0 个月',
    ]);
    expect(artifact.metrics.last.context, '目标 12 个月');
    expect(artifact.insights.first.body, contains('8.0 个百分点'));
  });

  test('adds a concise comparison when a previous review exists', () {
    final previous = generateReview(
      kind: FireReviewKind.monthly,
      state: _state(investable: '500000', liquid: '12000', etaMonths: null),
      now: DateTime.utc(2026, 6, 5),
    );
    final current = generateReview(
      kind: FireReviewKind.monthly,
      state: _state(investable: '400000', liquid: '12000', etaMonths: null),
      now: now,
    );
    final artifact =
        FirePlanDriftAnalysis.fromReview(
          current,
          previousReview: previous,
        ).toArtifact(
          id: 'fire-trend',
          ownerUserId: 'u',
          traceId: null,
          createdAt: now,
          l10n: lookupAppLocalizations(const Locale('zh')),
        );

    final trend = artifact.insights.singleWhere(
      (insight) => insight.id == 'period_change',
    );
    expect(trend.title, '相比上次');
    expect(trend.body, contains('提取率 +2.4 个百分点'));
    expect(trend.body, contains('净资产 -¥100,000.00'));
  });
}

FireState _state({
  String investable = '2000000',
  String liquid = '48000',
  String annualSpend = '48000',
  int? etaMonths = 60,
}) {
  final plan = FirePlan.fromGoal(
    FireGoal(
      targetAmount: Decimal.parse('1000000'),
      monthlyExpenses: Decimal.parse('4000'),
      monthlySurplus: Decimal.zero,
      inflationRate: 0,
    ),
    baseCurrency: 'CNY',
    safeWithdrawalRate: 0.04,
    targetCashBucketMonths: 12,
  );
  return computeFireState(
    plan: plan,
    netWorth: Money(Decimal.parse(investable), 'CNY'),
    investableAssets: Money(Decimal.parse(investable), 'CNY'),
    liquidAssets: Money(Decimal.parse(liquid), 'CNY'),
    trailingAnnualSpend: Money(Decimal.parse(annualSpend), 'CNY'),
    fireEtaMonths: etaMonths,
    currencyMismatchCount: 0,
    computedAt: DateTime.utc(2026, 7, 5),
  );
}
