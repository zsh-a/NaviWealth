/// `weekly_wealth_review` — deterministic FinanceOS weekly review agent.
///
/// Reads the same dashboard snapshot the Finance Home renders, derives a
/// local-only artifact, and stores an episodic memory for future recall. This
/// agent intentionally does not call an LLM: money math and data-quality
/// checks stay deterministic.
library;

import 'dart:ui' show Locale;

import 'package:decimal/decimal.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_presentation.dart';
import '../../../core/ai/agents/agent_artifact_store.dart';
import '../../../core/ai/agents/agent_intents.dart';
import '../../../core/ai/agents/agent_l10n.dart';
import '../../../core/ai/agents/agent_schedule.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/contracts/context_evidence.dart';
import '../../../core/ai/contracts/contracts.dart';
import '../../../core/ai/contracts/memory_record.dart';
import '../../../core/ai/local/memory/memory_runtime.dart';
import '../../../core/ai/local/memory/providers.dart';
import '../../../core/ai/trace/ai_trace_store.dart';
import '../../../core/ai/trace/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/format/formatters.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/read_models/dashboard_providers.dart';
import '../composition/finance_route_paths.dart';
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
    final traceStore = ctx.ref.read(aiTraceStoreProvider);
    final snapshot = await reader.read(ctx);
    return synthesize(
      snapshot: snapshot,
      ownerUserId: ownerUserId,
      startedAt: startedAt,
      finishedAt: DateTime.now().toUtc(),
      runtime: runtime,
      artifactStore: artifactStore,
      traceStore: traceStore,
      l10n: agentL10n(ctx.ref),
    );
  }

  static Future<AgentRunResult> synthesize({
    required DashboardSnapshot snapshot,
    required String ownerUserId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required MemoryRuntime runtime,
    AgentArtifactStore? artifactStore,
    AiTraceStore? traceStore,
    AppLocalizations? l10n,
  }) async {
    final strings = l10n ?? defaultAgentL10n();
    if (snapshot.isEmpty &&
        snapshot.netWorth.isZero &&
        snapshot.totalAssets.isZero &&
        snapshot.totalLiabilities.isZero) {
      return AgentRunResult.skipped(
        agentId: kWeeklyWealthReviewAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: strings.financeAgentWeeklyWealthSkipNoSnapshot,
      );
    }

    final analysis = WealthReviewAnalysis.fromSnapshot(snapshot);
    final dayKey = AppFormatters.utcDayKey(startedAt);
    final memoryId = '$kWeeklyWealthReviewMemorySource:$dayKey';
    final artifactId = '$kWeeklyWealthReviewAgentId:$dayKey';
    final traceId = '$kWeeklyWealthReviewAgentId:trace:$dayKey';
    final summary = analysis.summary(strings);
    final memory = MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      role: MemoryRole.pattern,
      authority: EvidenceAuthority.deterministicDerived,
      ownerUserId: ownerUserId,
      scope: 'finance',
      source: kWeeklyWealthReviewMemorySource,
      sourceId: dayKey,
      title: strings.financeAgentWeeklyWealthMemoryTitle(dayKey),
      summary: summary,
      payload: <String, Object?>{
        'context':
            'weekly wealth review run at ${startedAt.toUtc().toIso8601String()}',
        'outcome': analysis.toPayload(),
        'artifact_id': artifactId,
        if (traceStore != null) 'trace_id': traceId,
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
        l10n: strings,
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
      traceId: traceStore == null ? null : traceId,
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

  String summary(AppLocalizations l10n) {
    final parts = <String>[
      l10n.financeAgentWeeklyWealthPartNetWorth(
        _money(snapshot.netWorth, l10n),
      ),
      l10n.financeAgentWeeklyWealthPartAssets(
        _money(snapshot.totalAssets, l10n),
      ),
      l10n.financeAgentWeeklyWealthPartLiabilities(
        _money(snapshot.totalLiabilities, l10n),
      ),
    ];
    final top = topAllocation;
    if (top != null) {
      parts.add(
        l10n.financeAgentWeeklyWealthPartLargestAllocation(
          _categoryLabel(l10n, top.category),
          _money(top.totalInBase, l10n),
          Fmt.signedPercent(
            topAllocationRatio,
            decimalDigits: 0,
          ).replaceFirst('+', ''),
        ),
      );
    }
    if (snapshot.staleHoldingCount > 0) {
      parts.add(
        l10n.financeAgentWeeklyWealthPartStalePrices(
          snapshot.staleHoldingCount,
        ),
      );
    }
    if (snapshot.currencyMismatches.isNotEmpty) {
      parts.add(
        l10n.financeAgentWeeklyWealthPartFxGaps(
          snapshot.currencyMismatches.length,
        ),
      );
    }
    return l10n.financeAgentWeeklyWealthSummary(parts.join(' · '));
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
    required String? traceId,
    required DateTime createdAt,
    required AppLocalizations l10n,
  }) {
    final top = topAllocation;
    return AgentArtifact(
      id: id,
      ownerUserId: ownerUserId,
      agentId: kWeeklyWealthReviewAgentId,
      domain: 'finance',
      kind: AgentArtifactKind.review,
      severity: severity,
      title: l10n.financeAgentWeeklyWealthTitle,
      summary: summary(l10n),
      metrics: <AgentMetric>[
        AgentMetric(
          label: l10n.financeAgentWeeklyWealthInsightNetWorthTitle,
          value: _money(snapshot.netWorth, l10n),
        ),
        if (top != null)
          AgentMetric(
            label: l10n.financeAgentWeeklyWealthInsightLargestAllocationTitle,
            value: Fmt.signedPercent(
              topAllocationRatio,
              decimalDigits: 0,
            ).replaceFirst('+', ''),
            context: _categoryLabel(l10n, top.category),
            severity: topAllocationRatio >= 0.7
                ? AgentArtifactSeverity.attention
                : null,
          ),
        AgentMetric(
          label: l10n.financeAgentWeeklyWealthInsightPriceFreshnessTitle,
          value: snapshot.staleHoldingCount.toString(),
          severity: snapshot.staleHoldingCount > 0
              ? AgentArtifactSeverity.attention
              : null,
        ),
      ],
      insights: <AgentInsight>[
        AgentInsight(
          id: 'net_worth',
          title: l10n.financeAgentWeeklyWealthInsightNetWorthTitle,
          body: l10n.financeAgentWeeklyWealthInsightNetWorthBody(
            _money(snapshot.netWorth, l10n),
            _money(snapshot.totalAssets, l10n),
            _money(snapshot.totalLiabilities, l10n),
          ),
          payload: <String, Object?>{
            'net_worth': snapshot.netWorth.amount.toString(),
            'total_assets': snapshot.totalAssets.amount.toString(),
            'total_liabilities': snapshot.totalLiabilities.amount.toString(),
          },
          route: FinanceRoutes.wealth,
        ),
        if (top != null)
          AgentInsight(
            id: 'largest_allocation',
            title: l10n.financeAgentWeeklyWealthInsightLargestAllocationTitle,
            body: l10n.financeAgentWeeklyWealthInsightLargestAllocationBody(
              _categoryLabel(l10n, top.category),
              _money(top.totalInBase, l10n),
              Fmt.signedPercent(
                topAllocationRatio,
                decimalDigits: 0,
              ).replaceFirst('+', ''),
            ),
            severity: topAllocationRatio >= 0.7
                ? AgentArtifactSeverity.attention
                : AgentArtifactSeverity.info,
            payload: <String, Object?>{
              'category': top.category.name,
              'amount': top.totalInBase.amount.toString(),
              'ratio': topAllocationRatio,
            },
            route: FinanceRoutes.wealthPortfolio,
          ),
        if (snapshot.staleHoldingCount > 0)
          AgentInsight(
            id: 'price_freshness',
            title: l10n.financeAgentWeeklyWealthInsightPriceFreshnessTitle,
            body: l10n.financeAgentWeeklyWealthInsightPriceFreshnessBody(
              snapshot.staleHoldingCount,
            ),
            severity: AgentArtifactSeverity.attention,
            payload: <String, Object?>{
              'stale_holding_count': snapshot.staleHoldingCount,
            },
            route: FinanceRoutes.wealthPortfolio,
          ),
        if (snapshot.currencyMismatches.isNotEmpty)
          AgentInsight(
            id: 'fx_coverage',
            title: l10n.financeAgentWeeklyWealthInsightFxCoverageTitle,
            body: l10n.financeAgentWeeklyWealthInsightFxCoverageBody(
              snapshot.currencyMismatches.length,
            ),
            severity: AgentArtifactSeverity.warning,
            payload: <String, Object?>{
              'currency_mismatch_count': snapshot.currencyMismatches.length,
            },
            route: FinanceRoutes.wealth,
          ),
      ],
      evidence: <AgentEvidenceRef>[
        for (final item in evidenceItems.take(8))
          AgentEvidenceRef(
            type: 'finance_holding',
            id: item.id,
            label: item.name,
            route: FinanceRoutes.wealthAsset(item.id),
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
            route: FinanceRoutes.wealth,
          ),
      ],
      actions: <AgentAction>[
        AgentAction(
          kind: 'review',
          label: l10n.financeAgentWeeklyWealthAction,
          intent: kFinanceReviewWealthIntent,
          objectType: kAgentArtifactObjectType,
          objectId: id,
          route: FinanceRoutes.wealth,
        ),
      ],
      methodology: localAgentMethodology(
        l10n,
        sourceLabel: l10n.financeAgentWeeklyWealthTitle,
      ),
      memoryId: memoryId,
      traceId: traceId,
      createdAt: createdAt.toUtc(),
      expiresAt: createdAt.toUtc().add(const Duration(days: 14)),
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
        capability: Capability.summarize,
        risk: RiskLevel.info,
        label: 'weekly_wealth_review',
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
            'agent_id': kWeeklyWealthReviewAgentId,
            'surface': 'finance_home',
            'artifact_id': artifactId,
            'deterministic': true,
            'base_currency': snapshot.baseCurrency,
            'allocation_count': snapshot.allocations.length,
            'evidence_count': evidenceItems.length,
            'stale_holding_count': snapshot.staleHoldingCount,
            'currency_mismatch_count': snapshot.currencyMismatches.length,
          },
        ),
      ],
    );
  }
}

String _money(Money money, AppLocalizations l10n) {
  final locale = Locale(l10n.localeName);
  return AppFormatters(
    locale: locale,
    baseCurrency: money.currency,
  ).currency(money.amount, code: money.currency);
}

String _categoryLabel(AppLocalizations l10n, AssetCategory category) =>
    switch (category) {
      AssetCategory.stock => l10n.financeAgentAssetCategoryStock,
      AssetCategory.etf => l10n.financeAgentAssetCategoryEtf,
      AssetCategory.bondsAndFunds =>
        l10n.financeAgentAssetCategoryBondsAndFunds,
      AssetCategory.cash => l10n.financeAgentAssetCategoryCash,
      AssetCategory.crypto => l10n.financeAgentAssetCategoryCrypto,
      AssetCategory.realEstate => l10n.financeAgentAssetCategoryRealEstate,
      AssetCategory.vehicle => l10n.financeAgentAssetCategoryVehicle,
      AssetCategory.liability => l10n.financeAgentAssetCategoryLiability,
    };
