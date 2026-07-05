/// `weekly_wealth_review` — deterministic FinanceOS weekly review agent.
///
/// Reads the same dashboard snapshot the Finance Home renders, derives a
/// local-only artifact, and stores an episodic memory for future recall. This
/// agent intentionally does not call an LLM: money math and data-quality
/// checks stay deterministic.
library;

import 'package:decimal/decimal.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_store.dart';
import '../../../core/ai/agents/agent_intents.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../application/read_models/dashboard_providers.dart';
import '../domain/fx/money.dart';
import '../home/domain/dashboard_models.dart';

const String kWeeklyWealthReviewAgentId = 'weekly_wealth_review';
const String kWeeklyWealthReviewMemorySource = 'agent:weekly_wealth_review';

class WeeklyWealthReviewAgent implements Agent {
  const WeeklyWealthReviewAgent({
    this.reader = const DashboardWeeklyWealthReviewReader(),
  });

  final WeeklyWealthReviewReader reader;

  @override
  String get id => kWeeklyWealthReviewAgentId;

  @override
  String get name => 'Weekly Wealth Review';

  @override
  AgentSchedule get schedule =>
      const AgentSchedule(interval: Duration(days: 7), preferredHourLocal: 18);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final startedAt = ctx.now;
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final artifactStore = await ctx.ref.read(
      agent_providers.agentArtifactStoreProvider.future,
    );
    final snapshot = await reader.read(ctx);
    return synthesize(
      snapshot: snapshot,
      ownerUserId: ownerUserId,
      startedAt: startedAt,
      finishedAt: DateTime.now().toUtc(),
      runtime: runtime,
      artifactStore: artifactStore,
    );
  }

  static Future<AgentRunResult> synthesize({
    required DashboardSnapshot snapshot,
    required String ownerUserId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required MemoryRuntime runtime,
    AgentArtifactStore? artifactStore,
  }) async {
    if (snapshot.isEmpty &&
        snapshot.netWorth.isZero &&
        snapshot.totalAssets.isZero &&
        snapshot.totalLiabilities.isZero) {
      return AgentRunResult.skipped(
        agentId: kWeeklyWealthReviewAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: 'no finance snapshot to review',
      );
    }

    final analysis = WealthReviewAnalysis.fromSnapshot(snapshot);
    final dayKey = AppFormatters.utcDayKey(startedAt);
    final memoryId = '$kWeeklyWealthReviewMemorySource:$dayKey';
    final artifactId = '$kWeeklyWealthReviewAgentId:$dayKey';
    final summary = analysis.summary;
    final memory = MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      scope: 'finance',
      source: kWeeklyWealthReviewMemorySource,
      sourceId: dayKey,
      title: 'Weekly wealth review · $dayKey',
      summary: summary,
      payload: <String, Object?>{
        'context':
            'weekly wealth review run at ${startedAt.toUtc().toIso8601String()}',
        'outcome': analysis.toPayload(),
        'artifact_id': artifactId,
      },
      entities: <String>{
        'finance',
        'wealth',
        'weekly_wealth_review',
        dayKey,
        for (final allocation in snapshot.allocations)
          'finance_category:${allocation.category.name}',
        for (final item in analysis.evidenceItems.take(8))
          'finance_item:${item.id}',
      },
      importance: analysis.severity == AgentArtifactSeverity.info ? 0.58 : 0.74,
      confidence: 0.95,
      validFrom: startedAt.toUtc(),
      createdAt: startedAt.toUtc(),
      updatedAt: finishedAt.toUtc(),
    );
    await runtime.remember(memory);
    await artifactStore?.save(
      analysis.toArtifact(
        id: artifactId,
        ownerUserId: ownerUserId,
        memoryId: memoryId,
        createdAt: startedAt,
      ),
    );

    return AgentRunResult(
      agentId: kWeeklyWealthReviewAgentId,
      status: AgentRunStatus.completed,
      startedAt: startedAt,
      finishedAt: finishedAt,
      summary: summary,
      payload: analysis.toPayload(),
      memoryId: memoryId,
      artifactId: artifactStore == null ? null : artifactId,
    );
  }
}

abstract class WeeklyWealthReviewReader {
  Future<DashboardSnapshot> read(AgentContext ctx);
}

class DashboardWeeklyWealthReviewReader implements WeeklyWealthReviewReader {
  const DashboardWeeklyWealthReviewReader();

  @override
  Future<DashboardSnapshot> read(AgentContext ctx) {
    return ctx.ref.read(dashboardSnapshotProvider.future);
  }
}

class WealthReviewAnalysis {
  const WealthReviewAnalysis({
    required this.snapshot,
    required this.topAllocation,
    required this.topAllocationRatio,
    required this.evidenceItems,
    required this.severity,
  });

  factory WealthReviewAnalysis.fromSnapshot(DashboardSnapshot snapshot) {
    final assetAllocations =
        snapshot.allocations.where((a) => !a.isLiability).toList()..sort(
          (a, b) => b.totalInBase.amount.compareTo(a.totalInBase.amount),
        );
    final top = assetAllocations.isEmpty ? null : assetAllocations.first;
    final ratio = top == null || snapshot.totalAssets.amount <= Decimal.zero
        ? 0.0
        : (top.totalInBase.amount / snapshot.totalAssets.amount).toDouble();
    final evidenceItems = <CategoryItem>[
      for (final allocation in assetAllocations.take(3))
        ...allocation.items.take(3),
    ];
    final severity = snapshot.currencyMismatches.isNotEmpty
        ? AgentArtifactSeverity.warning
        : snapshot.staleHoldingCount > 0 || ratio >= 0.7
        ? AgentArtifactSeverity.attention
        : AgentArtifactSeverity.info;
    return WealthReviewAnalysis(
      snapshot: snapshot,
      topAllocation: top,
      topAllocationRatio: ratio,
      evidenceItems: List.unmodifiable(evidenceItems),
      severity: severity,
    );
  }

  final DashboardSnapshot snapshot;
  final CategoryAllocation? topAllocation;
  final double topAllocationRatio;
  final List<CategoryItem> evidenceItems;
  final AgentArtifactSeverity severity;

  String get summary {
    final parts = <String>[
      'Net worth ${_money(snapshot.netWorth)}',
      'assets ${_money(snapshot.totalAssets)}',
      'liabilities ${_money(snapshot.totalLiabilities)}',
    ];
    final top = topAllocation;
    if (top != null) {
      parts.add(
        'largest allocation ${_categoryLabel(top.category)} ${_money(top.totalInBase)} '
        '(${Fmt.signedPercent(topAllocationRatio, decimalDigits: 0).replaceFirst('+', '')})',
      );
    }
    if (snapshot.staleHoldingCount > 0) {
      parts.add('${snapshot.staleHoldingCount} stale prices');
    }
    if (snapshot.currencyMismatches.isNotEmpty) {
      parts.add('${snapshot.currencyMismatches.length} FX gaps');
    }
    return 'Weekly wealth review: ${parts.join(' · ')}.';
  }

  Map<String, Object?> toPayload() => <String, Object?>{
    'base_currency': snapshot.baseCurrency,
    'net_worth': snapshot.netWorth.amount.toString(),
    'total_assets': snapshot.totalAssets.amount.toString(),
    'total_liabilities': snapshot.totalLiabilities.amount.toString(),
    'top_allocation_category': topAllocation?.category.name,
    'top_allocation_amount': topAllocation?.totalInBase.amount.toString(),
    'top_allocation_ratio': topAllocationRatio,
    'stale_holding_count': snapshot.staleHoldingCount,
    'currency_mismatch_count': snapshot.currencyMismatches.length,
  };

  AgentArtifact toArtifact({
    required String id,
    required String ownerUserId,
    required String memoryId,
    required DateTime createdAt,
  }) {
    final top = topAllocation;
    return AgentArtifact(
      id: id,
      ownerUserId: ownerUserId,
      agentId: kWeeklyWealthReviewAgentId,
      domain: 'finance',
      kind: AgentArtifactKind.review,
      severity: severity,
      title: 'Weekly Wealth Review',
      summary: summary,
      insights: <AgentInsight>[
        AgentInsight(
          title: 'Net worth',
          body:
              '${_money(snapshot.netWorth)} net worth from '
              '${_money(snapshot.totalAssets)} assets and '
              '${_money(snapshot.totalLiabilities)} liabilities.',
          payload: <String, Object?>{
            'net_worth': snapshot.netWorth.amount.toString(),
            'total_assets': snapshot.totalAssets.amount.toString(),
            'total_liabilities': snapshot.totalLiabilities.amount.toString(),
          },
        ),
        if (top != null)
          AgentInsight(
            title: 'Largest allocation',
            body:
                '${_categoryLabel(top.category)} is '
                '${_money(top.totalInBase)}, about '
                '${Fmt.signedPercent(topAllocationRatio, decimalDigits: 0).replaceFirst('+', '')} '
                'of assets.',
            severity: topAllocationRatio >= 0.7
                ? AgentArtifactSeverity.attention
                : AgentArtifactSeverity.info,
            payload: <String, Object?>{
              'category': top.category.name,
              'amount': top.totalInBase.amount.toString(),
              'ratio': topAllocationRatio,
            },
          ),
        if (snapshot.staleHoldingCount > 0)
          AgentInsight(
            title: 'Price freshness',
            body: '${snapshot.staleHoldingCount} holdings have stale prices.',
            severity: AgentArtifactSeverity.attention,
            payload: <String, Object?>{
              'stale_holding_count': snapshot.staleHoldingCount,
            },
          ),
        if (snapshot.currencyMismatches.isNotEmpty)
          AgentInsight(
            title: 'FX coverage',
            body:
                '${snapshot.currencyMismatches.length} holdings were excluded because FX conversion is missing.',
            severity: AgentArtifactSeverity.warning,
            payload: <String, Object?>{
              'currency_mismatch_count': snapshot.currencyMismatches.length,
            },
          ),
      ],
      evidence: <AgentEvidenceRef>[
        for (final item in evidenceItems.take(8))
          AgentEvidenceRef(
            type: 'finance_holding',
            id: item.id,
            label: item.name,
            payload: <String, Object?>{
              'value_in_base': item.valueInBase.amount.toString(),
              'base_currency': item.valueInBase.currency,
              'native_amount': item.nativeAmount.toString(),
              'native_currency': item.nativeCurrency,
            },
          ),
        for (final mismatch in snapshot.currencyMismatches.take(5))
          AgentEvidenceRef(
            type: 'currency_mismatch',
            id: mismatch.id,
            label: mismatch.currency,
          ),
      ],
      actions: <AgentAction>[
        AgentAction(
          kind: 'review',
          label: 'Review wealth',
          intent: kFinanceReviewWealthIntent,
          objectType: kAgentArtifactObjectType,
          objectId: id,
        ),
      ],
      memoryId: memoryId,
      createdAt: createdAt.toUtc(),
      expiresAt: createdAt.toUtc().add(const Duration(days: 14)),
    );
  }
}

String _money(Money money) => '${money.amount} ${money.currency}';

String _categoryLabel(AssetCategory category) => switch (category) {
  AssetCategory.stock => 'stocks',
  AssetCategory.etf => 'ETFs',
  AssetCategory.bondsAndFunds => 'bonds and funds',
  AssetCategory.cash => 'cash',
  AssetCategory.crypto => 'crypto',
  AssetCategory.realEstate => 'real estate',
  AssetCategory.vehicle => 'vehicles',
  AssetCategory.liability => 'liabilities',
};
