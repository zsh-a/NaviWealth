import 'dart:ui' show Locale;

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/regression/agent_outcome_evaluator.dart';
import 'package:naviwealth/core/ai/trace/ai_trace_store.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/features/finance/agents/providers.dart'
    as finance_agent_providers;
import 'package:naviwealth/features/finance/agents/weekly_wealth_review_agent.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  final now = DateTime.utc(2026, 7, 5, 18);

  test('skips when there is no finance snapshot to review', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final result = await WeeklyWealthReviewAgent.synthesize(
      snapshot: DashboardSnapshot.empty(asOf: now, baseCurrency: 'CNY'),
      ownerUserId: 'u',
      startedAt: now,
      finishedAt: now.add(const Duration(milliseconds: 20)),
    );

    expect(result.status, AgentRunStatus.skipped);
    expect(result.artifactId, isNull);
    final failures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'finance.weekly_wealth_review.no_finding',
      ),
      result: result,
    );
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('persists deterministic weekly wealth artifact with evidence', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentArtifactStore(db: db);
    final traceStore = InMemoryAiTraceStore();

    final result = await WeeklyWealthReviewAgent.synthesize(
      snapshot: _snapshot(),
      ownerUserId: 'u',
      startedAt: now,
      finishedAt: now.add(const Duration(milliseconds: 20)),
      artifactStore: store,
      traceStore: traceStore,
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.memoryId, isNull);
    expect(result.artifactId, '$kWeeklyWealthReviewAgentId:2026-07-05');
    expect(result.traceId, '$kWeeklyWealthReviewAgentId:trace:2026-07-05');
    expect(result.summary, contains('Net worth ¥8,000.00'));
    expect(result.payload['top_allocation_category'], AssetCategory.stock.name);

    final artifact = await store.read(result.artifactId!);
    expect(artifact, isNotNull);
    expect(artifact!.domain, 'finance');
    expect(artifact.kind, AgentArtifactKind.review);
    expect(artifact.severity, AgentArtifactSeverity.warning);
    expect(artifact.memoryId, isNull);
    expect(artifact.traceId, result.traceId);
    expect(
      artifact.insights.map((insight) => insight.title),
      containsAll([
        'Net worth',
        'Largest allocation',
        'Price freshness',
        'FX coverage',
      ]),
    );
    expect(
      artifact.evidence.map((ref) => ref.id),
      containsAll(['aapl', 'fx1']),
    );
    expect(artifact.actions.single.intent, 'finance.reviewWealth');
    final outcomeFailures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'finance.weekly_wealth_review.ready',
      ),
      result: result,
      artifact: artifact,
    );
    expect(outcomeFailures, isEmpty, reason: outcomeFailures.join('\n'));
    final noLlmFallbackFailures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'finance.weekly_wealth_review.no_llm_profile_fallback',
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
    expect(trace.intent.label, 'weekly_wealth_review');
    expect(trace.spans.single.attributes, containsPair('deterministic', true));
    expect(
      trace.spans.single.attributes,
      containsPair('artifact_id', result.artifactId),
    );
  });

  test('persists weekly wealth artifact in Chinese when requested', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentArtifactStore(db: db);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    final result = await WeeklyWealthReviewAgent.synthesize(
      snapshot: _snapshot(),
      ownerUserId: 'u',
      startedAt: now,
      finishedAt: now.add(const Duration(milliseconds: 20)),
      artifactStore: store,
      l10n: l10n,
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.summary, contains('每周财富复盘'));
    expect(result.summary, contains('净资产 ¥8,000.00'));

    final artifact = await store.read(result.artifactId!);
    expect(artifact?.title, '每周财富复盘');
    expect(
      artifact?.insights.map((insight) => insight.title),
      containsAll(['净资产', '最大配置', '价格新鲜度', '汇率覆盖']),
    );
    expect(artifact?.actions.single.label, '查看财富复盘');
  });

  test('rounds long decimal money amounts for display', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentArtifactStore(db: db);
    final l10n = lookupAppLocalizations(const Locale('zh'));

    final result = await WeeklyWealthReviewAgent.synthesize(
      snapshot: _longDecimalSnapshot(),
      ownerUserId: 'u',
      startedAt: now,
      finishedAt: now.add(const Duration(milliseconds: 20)),
      artifactStore: store,
      l10n: l10n,
    );

    expect(result.summary, contains('净资产 ¥7,532.20'));
    expect(result.summary, isNot(contains('7532.20338983050847457307')));

    final artifact = await store.read(result.artifactId!);
    expect(artifact?.summary, contains('¥7,532.20'));
    expect(artifact?.summary, isNot(contains('7532.20338983050847457307')));
  });

  test('finance agent providers read latest artifact and run', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final artifactStore = SqliteAgentArtifactStore(db: db);
    final runStore = SqliteAgentRunStore(db: db);
    await artifactStore.save(
      _financeArtifact(id: 'wealth-review-old', createdAt: now),
    );
    await artifactStore.save(
      _financeArtifact(
        id: 'wealth-review-new',
        createdAt: now.add(const Duration(days: 7)),
      ),
    );
    await runStore.finishRun(
      ownerUserId: 'u',
      agent: const WeeklyWealthReviewAgent(),
      runStartedAt: now,
      result: AgentRunResult(
        agentId: kWeeklyWealthReviewAgentId,
        status: AgentRunStatus.completed,
        startedAt: now,
        finishedAt: now.add(const Duration(milliseconds: 20)),
        summary: 'Net worth 8000 CNY',
        artifactId: 'wealth-review-new',
        traceId: 'trace-new',
      ),
      trigger: AgentRunTrigger.manual,
    );
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue(() async => 'u'),
        agent_providers.agentArtifactStoreProvider.overrideWith(
          (ref) async => artifactStore,
        ),
        agent_providers.agentRunStoreProvider.overrideWith(
          (ref) async => runStore,
        ),
      ],
    );
    addTearDown(container.dispose);

    final artifact = await container.read(
      finance_agent_providers.latestWeeklyWealthReviewArtifactProvider.future,
    );
    final run = await container.read(
      finance_agent_providers.latestWeeklyWealthReviewRunProvider.future,
    );

    expect(artifact?.id, 'wealth-review-new');
    expect(run?.status, AgentRunLifecycleStatus.ready);
    expect(run?.artifactId, 'wealth-review-new');
    expect(run?.traceId, 'trace-new');
  });
}

DashboardSnapshot _snapshot() {
  const currency = 'CNY';
  return DashboardSnapshot(
    asOf: DateTime.utc(2026, 7, 5),
    baseCurrency: currency,
    allocations: [
      CategoryAllocation(
        category: AssetCategory.stock,
        totalInBase: Money(Decimal.parse('7000'), currency),
        items: [
          CategoryItem(
            id: 'aapl',
            name: 'AAPL',
            subtitle: '10 · USD',
            valueInBase: Money(Decimal.parse('7000'), currency),
            nativeAmount: Decimal.parse('1000'),
            nativeCurrency: 'USD',
          ),
        ],
      ),
      CategoryAllocation(
        category: AssetCategory.cash,
        totalInBase: Money(Decimal.parse('3000'), currency),
        items: [
          CategoryItem(
            id: 'cash',
            name: 'Cash',
            subtitle: null,
            valueInBase: Money(Decimal.parse('3000'), currency),
            nativeAmount: Decimal.parse('3000'),
            nativeCurrency: currency,
          ),
        ],
      ),
      CategoryAllocation(
        category: AssetCategory.liability,
        totalInBase: Money(Decimal.parse('2000'), currency),
        items: [
          CategoryItem(
            id: 'loan',
            name: 'Loan',
            subtitle: null,
            valueInBase: Money(Decimal.parse('2000'), currency),
            nativeAmount: Decimal.parse('2000'),
            nativeCurrency: currency,
          ),
        ],
      ),
    ],
    totalAssets: Money(Decimal.parse('10000'), currency),
    totalLiabilities: Money(Decimal.parse('2000'), currency),
    netWorth: Money(Decimal.parse('8000'), currency),
    currencyMismatches: const [CurrencyMismatch(id: 'fx1', currency: 'USD')],
    staleHoldingCount: 1,
  );
}

DashboardSnapshot _longDecimalSnapshot() {
  const currency = 'CNY';
  final amount = Decimal.parse('7532.20338983050847457307');
  return DashboardSnapshot(
    asOf: DateTime.utc(2026, 7, 5),
    baseCurrency: currency,
    allocations: [
      CategoryAllocation(
        category: AssetCategory.cash,
        totalInBase: Money(amount, currency),
        items: [
          CategoryItem(
            id: 'cash',
            name: 'Cash',
            subtitle: null,
            valueInBase: Money(amount, currency),
            nativeAmount: amount,
            nativeCurrency: currency,
          ),
        ],
      ),
    ],
    totalAssets: Money(amount, currency),
    totalLiabilities: Money(Decimal.zero, currency),
    netWorth: Money(amount, currency),
    currencyMismatches: const [],
    staleHoldingCount: 0,
  );
}

AgentArtifact _financeArtifact({
  required String id,
  required DateTime createdAt,
}) {
  return AgentArtifact(
    id: id,
    ownerUserId: 'u',
    agentId: kWeeklyWealthReviewAgentId,
    domain: 'finance',
    kind: AgentArtifactKind.review,
    severity: AgentArtifactSeverity.info,
    title: 'Weekly Wealth Review',
    summary: 'Net worth 8000 CNY',
    createdAt: createdAt,
  );
}
