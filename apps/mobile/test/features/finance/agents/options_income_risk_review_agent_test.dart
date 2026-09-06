import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/regression/agent_outcome_evaluator.dart';
import 'package:naviwealth/core/ai/trace/ai_trace_store.dart';
import 'package:naviwealth/features/finance/agents/options_income_risk_review_agent.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/options_income/data/options_opportunity_cache_repository.dart';
import 'package:naviwealth/features/finance/options_income/data/providers.dart';
import 'package:naviwealth/features/finance/options_income/domain/opportunity_explanation.dart';
import 'package:naviwealth/features/finance/options_income/domain/option_contract.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_opportunity.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  final now = DateTime.utc(2026, 7, 5, 18);

  test('skips when no options income scan is available', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    final result = await OptionsIncomeRiskReviewAgent.synthesize(
      snapshot: const OptionsIncomeRiskSnapshot(
        opportunities: [],
        scanState: null,
      ),
      ownerUserId: 'u',
      startedAt: now,
      finishedAt: now.add(const Duration(milliseconds: 20)),
    );

    expect(result.status, AgentRunStatus.skipped);
    expect(result.summary, 'no options income scan available');
    expect(result.artifactId, isNull);
    final failures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'finance.options_income_risk_review.no_finding',
      ),
      result: result,
    );
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('skips clean low-risk scans', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final snapshot = OptionsIncomeRiskSnapshot(
      scanState: ScanCacheState(
        scanId: 'scan-clean',
        scannedAt: now.subtract(const Duration(hours: 1)),
        count: 1,
      ),
      opportunities: [
        _opportunity(
          symbol: 'AAPL',
          score: '0.82',
          risk: OpportunityRiskLevel.low,
          spread: '0.02',
          marginOfSafety: '0.12',
          scanId: 'scan-clean',
          scannedAt: now.subtract(const Duration(hours: 1)),
        ),
      ],
    );

    final result = await OptionsIncomeRiskReviewAgent.synthesize(
      snapshot: snapshot,
      ownerUserId: 'u',
      startedAt: now,
      finishedAt: now.add(const Duration(milliseconds: 20)),
    );

    expect(result.status, AgentRunStatus.skipped);
    expect(result.summary, 'no options income risk finding');
  });

  test('persists deterministic options income risk artifact', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SqliteAgentArtifactStore(db: db);
    final traceStore = InMemoryAiTraceStore();
    final snapshot = OptionsIncomeRiskSnapshot(
      scanState: ScanCacheState(
        scanId: 'scan-risk',
        scannedAt: now.subtract(const Duration(hours: 30)),
        count: 3,
      ),
      opportunities: [
        _opportunity(
          symbol: 'AAPL',
          score: '0.40',
          risk: OpportunityRiskLevel.elevated,
          spread: '0.18',
          volume: 4,
          openInterest: 40,
          marginOfSafety: '0.02',
          delta: null,
          scanId: 'scan-risk',
          scannedAt: now.subtract(const Duration(hours: 30)),
        ),
        _opportunity(
          symbol: 'AAPL',
          score: '0.55',
          risk: OpportunityRiskLevel.moderate,
          spread: '0.04',
          marginOfSafety: '0.08',
          scanId: 'scan-risk',
          scannedAt: now.subtract(const Duration(hours: 30)),
        ),
        _opportunity(
          symbol: 'MSFT',
          score: '0.65',
          risk: OpportunityRiskLevel.low,
          spread: '0.03',
          marginOfSafety: '0.10',
          scanId: 'scan-risk',
          scannedAt: now.subtract(const Duration(hours: 30)),
        ),
      ],
    );

    final result = await OptionsIncomeRiskReviewAgent.synthesize(
      snapshot: snapshot,
      ownerUserId: 'u',
      startedAt: now,
      finishedAt: now.add(const Duration(milliseconds: 20)),
      artifactStore: store,
      traceStore: traceStore,
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.memoryId, isNull);
    expect(result.artifactId, '$kOptionsIncomeRiskReviewAgentId:2026-07-05');
    expect(result.traceId, '$kOptionsIncomeRiskReviewAgentId:trace:2026-07-05');
    expect(result.payload['issue_count'], greaterThanOrEqualTo(4));
    expect(result.summary, contains('scan data is stale'));

    final artifact = await store.read(result.artifactId!);
    expect(artifact, isNotNull);
    expect(artifact!.domain, 'finance');
    expect(artifact.kind, AgentArtifactKind.alert);
    expect(artifact.severity, AgentArtifactSeverity.warning);
    expect(artifact.actions.single.intent, 'agent.explainResult');
    expect(
      artifact.evidence.map((ref) => ref.type),
      containsAll(['options_income_scan', 'options_opportunity']),
    );
    expect(
      artifact.insights.map((insight) => insight.title),
      containsAll([
        'Scan data is stale',
        'Elevated-risk contracts present',
        'Quote quality needs review',
      ]),
    );
    final outcomeFailures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'finance.options_income_risk_review.ready',
      ),
      result: result,
      artifact: artifact,
    );
    expect(outcomeFailures, isEmpty, reason: outcomeFailures.join('\n'));
    final noLlmFallbackFailures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'finance.options_income_risk_review.no_llm_profile_fallback',
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
    expect(trace.intent.label, 'options_income_risk_review');
    expect(trace.spans.single.attributes, containsPair('deterministic', true));
    expect(trace.spans.single.attributes, containsPair('issue_count', 6));
  });

  test(
    'provider reader starts both provider reads before awaiting either',
    () async {
      final opportunitiesCompleter = Completer<List<OptionsOpportunity>>();
      final scanStateCompleter = Completer<ScanCacheState?>();
      var scanStateReadStarted = false;
      final readerProvider = FutureProvider<OptionsIncomeRiskSnapshot>((ref) {
        return const ProviderOptionsIncomeRiskReviewReader().read(
          AgentContext(ref: ref, now: now),
        );
      });
      final container = ProviderContainer(
        overrides: [
          cachedOpportunitiesProvider.overrideWith((ref) {
            return opportunitiesCompleter.future;
          }),
          latestScanStateProvider.overrideWith((ref) {
            scanStateReadStarted = true;
            return scanStateCompleter.future;
          }),
        ],
      );
      addTearDown(container.dispose);

      final future = container.read(readerProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(scanStateReadStarted, isTrue);

      final opportunity = _opportunity(
        symbol: 'AAPL',
        score: '0.40',
        risk: OpportunityRiskLevel.elevated,
        spread: '0.18',
        marginOfSafety: '0.02',
        scanId: 'scan-concurrent',
        scannedAt: now,
      );
      final scanState = ScanCacheState(
        scanId: 'scan-concurrent',
        scannedAt: now,
        count: 1,
      );
      opportunitiesCompleter.complete([opportunity]);
      scanStateCompleter.complete(scanState);

      final snapshot = await future;
      expect(snapshot.opportunities.single, same(opportunity));
      expect(snapshot.scanState, same(scanState));
    },
  );
}

OptionsOpportunity _opportunity({
  required String symbol,
  required String score,
  required OpportunityRiskLevel risk,
  required String spread,
  required String marginOfSafety,
  required String scanId,
  required DateTime scannedAt,
  int volume = 50,
  int openInterest = 500,
  String? delta = '-0.20',
}) {
  final strike = Money.parse('190', 'USD');
  final bid = Money.parse('2.50', 'USD');
  final ask = Money.parse('2.60', 'USD');
  final mid = Money.parse('2.55', 'USD');
  final contract = OptionContract(
    underlying: symbol,
    market: AssetMarket.usStock,
    optionSymbol: '${symbol}250620P00190000',
    type: OptionType.put,
    expiration: DateTime.utc(2026, 7, 20),
    dte: 30,
    strike: strike,
    bid: bid,
    ask: ask,
    mid: mid,
    volume: volume,
    openInterest: openInterest,
    impliedVolatility: Decimal.parse('0.25'),
    delta: delta == null ? null : Decimal.parse(delta),
    underlyingPrice: Money.parse('200', 'USD'),
    bidAskSpreadPct: Decimal.parse(spread),
    fetchedAt: scannedAt,
  );
  return OptionsOpportunity(
    strategy: OpportunityStrategy.cashSecuredPut,
    contract: contract,
    metrics: OpportunityMetrics(
      premium: Money.parse('255', 'USD'),
      cashRequired: Money.parse('19000', 'USD'),
      breakeven: Money.parse('187.45', 'USD'),
      staticReturn: Decimal.parse('0.0134'),
      annualizedYield: Decimal.parse('0.1630'),
      marginOfSafety: Decimal.parse(marginOfSafety),
    ),
    risk: risk,
    explanation: OpportunityExplanation(
      summary: '$symbol put',
      whyGood: const ['yield'],
      whyRisky: const ['assignment'],
      bestFor: 'cash flow',
      avoidIf: 'no assignment',
      worstCase: 'assigned shares',
      scoreBreakdown: {'yield': Decimal.parse(score)},
    ),
    score: Decimal.parse(score),
    scannedAt: scannedAt,
    scanId: scanId,
  );
}
