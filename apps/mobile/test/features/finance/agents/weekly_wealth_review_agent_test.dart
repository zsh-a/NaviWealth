import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/ai/trace/ai_trace_store.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/agents/weekly_wealth_review_agent.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';

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
      runtime: _runtimeForDb(db),
    );

    expect(result.status, AgentRunStatus.skipped);
    expect(result.memoryId, isNull);
    expect(result.artifactId, isNull);
  });

  test('persists deterministic weekly wealth artifact with evidence', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final runtime = _runtimeForDb(db);
    final store = SqliteAgentArtifactStore(db: db);
    final traceStore = InMemoryAiTraceStore();

    final result = await WeeklyWealthReviewAgent.synthesize(
      snapshot: _snapshot(),
      ownerUserId: 'u',
      startedAt: now,
      finishedAt: now.add(const Duration(milliseconds: 20)),
      runtime: runtime,
      artifactStore: store,
      traceStore: traceStore,
    );

    expect(result.status, AgentRunStatus.completed);
    expect(result.memoryId, '$kWeeklyWealthReviewMemorySource:2026-07-05');
    expect(result.artifactId, '$kWeeklyWealthReviewAgentId:2026-07-05');
    expect(result.traceId, '$kWeeklyWealthReviewAgentId:trace:2026-07-05');
    expect(result.summary, contains('Net worth 8000 CNY'));
    expect(result.payload['top_allocation_category'], AssetCategory.stock.name);

    final artifact = await store.read(result.artifactId!);
    expect(artifact, isNotNull);
    expect(artifact!.domain, 'finance');
    expect(artifact.kind, AgentArtifactKind.review);
    expect(artifact.severity, AgentArtifactSeverity.warning);
    expect(artifact.memoryId, result.memoryId);
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
}

MemoryRuntime _runtimeForDb(AppDatabase db) {
  return MemoryRuntime(
    embedder: StubEmbedder(),
    memoryStore: SqliteMemoryStore(db: db),
    eventStore: SqliteEventStore(db: db),
  );
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
