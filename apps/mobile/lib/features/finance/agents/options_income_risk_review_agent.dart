/// `options_income_risk_review` — deterministic options income risk agent.
///
/// Reviews the latest cached options-income scan and emits an artifact only
/// when the scan contains risk signals that deserve user attention.
library;

import 'package:decimal/decimal.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_presentation.dart';
import '../../../core/ai/agents/agent_artifact_store.dart';
import '../../../core/ai/agents/agent_intents.dart';
import '../../../core/ai/agents/agent_l10n.dart';
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
import '../../../l10n/gen/app_localizations.dart';
import '../composition/finance_route_paths.dart';
import '../options_income/data/options_opportunity_cache_repository.dart';
import '../options_income/data/providers.dart';
import '../options_income/domain/option_contract.dart';
import '../options_income/domain/options_opportunity.dart';

const String kOptionsIncomeRiskReviewAgentId = 'options_income_risk_review';
const String kOptionsIncomeRiskReviewMemorySource =
    'agent:options_income_risk_review';

class OptionsIncomeRiskReviewAgent implements Agent {
  const OptionsIncomeRiskReviewAgent({
    this.reader = const ProviderOptionsIncomeRiskReviewReader(),
  });

  final OptionsIncomeRiskReviewReader reader;

  @override
  String get id => kOptionsIncomeRiskReviewAgentId;

  @override
  String get name => 'Options Income Risk Review';

  @override
  AgentSchedule get schedule =>
      const AgentSchedule(interval: Duration(days: 1), preferredHourLocal: 18);

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
    required OptionsIncomeRiskSnapshot snapshot,
    required String ownerUserId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required MemoryRuntime runtime,
    AgentArtifactStore? artifactStore,
    AiTraceStore? traceStore,
    AppLocalizations? l10n,
  }) async {
    final strings = l10n ?? defaultAgentL10n();
    if (snapshot.opportunities.isEmpty) {
      return AgentRunResult.skipped(
        agentId: kOptionsIncomeRiskReviewAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: strings.financeAgentOptionsSkipNoScan,
      );
    }

    final analysis = OptionsIncomeRiskAnalysis.fromSnapshot(
      snapshot,
      now: startedAt,
      l10n: strings,
    );
    if (!analysis.hasFinding) {
      return AgentRunResult.skipped(
        agentId: kOptionsIncomeRiskReviewAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: strings.financeAgentOptionsSkipNoFinding,
      );
    }

    final dayKey = AppFormatters.utcDayKey(startedAt);
    final memoryId = '$kOptionsIncomeRiskReviewMemorySource:$dayKey';
    final artifactId = '$kOptionsIncomeRiskReviewAgentId:$dayKey';
    final traceId = '$kOptionsIncomeRiskReviewAgentId:trace:$dayKey';
    final summary = analysis.summary(strings);
    final memory = MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      scope: 'finance',
      source: kOptionsIncomeRiskReviewMemorySource,
      sourceId: dayKey,
      title: strings.financeAgentOptionsMemoryTitle(dayKey),
      summary: summary,
      payload: <String, Object?>{
        'context':
            'options income risk review run at ${startedAt.toUtc().toIso8601String()}',
        'outcome': analysis.toPayload(),
        'artifact_id': artifactId,
        if (traceStore != null) 'trace_id': traceId,
      },
      entities: <String>{
        'finance',
        'options_income',
        'risk_review',
        dayKey,
        if (snapshot.scanState != null) snapshot.scanState!.scanId,
        for (final opportunity in analysis.riskiestOpportunities)
          'option:${opportunity.contract.optionSymbol}',
        for (final issue in analysis.issues) 'options_risk:${issue.key}',
      },
      importance: analysis.severity == AgentArtifactSeverity.warning
          ? 0.78
          : 0.66,
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
        l10n: strings,
      ),
    );

    return AgentRunResult(
      agentId: kOptionsIncomeRiskReviewAgentId,
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

abstract class OptionsIncomeRiskReviewReader {
  Future<OptionsIncomeRiskSnapshot> read(AgentContext ctx);
}

class ProviderOptionsIncomeRiskReviewReader
    implements OptionsIncomeRiskReviewReader {
  const ProviderOptionsIncomeRiskReviewReader();

  @override
  Future<OptionsIncomeRiskSnapshot> read(AgentContext ctx) async {
    final opportunitiesFuture = ctx.ref.read(
      cachedOpportunitiesProvider.future,
    );
    final scanStateFuture = ctx.ref.read(latestScanStateProvider.future);
    final opportunities = await opportunitiesFuture;
    final scanState = await scanStateFuture;
    return OptionsIncomeRiskSnapshot(
      opportunities: opportunities,
      scanState: scanState,
    );
  }
}

class OptionsIncomeRiskSnapshot {
  const OptionsIncomeRiskSnapshot({
    required this.opportunities,
    required this.scanState,
  });

  final List<OptionsOpportunity> opportunities;
  final ScanCacheState? scanState;
}

class OptionsIncomeRiskAnalysis {
  const OptionsIncomeRiskAnalysis({
    required this.snapshot,
    required this.issues,
    required this.severity,
  });

  factory OptionsIncomeRiskAnalysis.fromSnapshot(
    OptionsIncomeRiskSnapshot snapshot, {
    required DateTime now,
    required AppLocalizations l10n,
  }) {
    final opportunities = snapshot.opportunities;
    final issues = <OptionsRiskIssue>[];
    final scanState = snapshot.scanState;
    if (scanState != null) {
      final age = now.toUtc().difference(scanState.scannedAt.toUtc());
      if (age > const Duration(hours: 24)) {
        issues.add(
          OptionsRiskIssue(
            key: 'stale_scan',
            title: l10n.financeAgentOptionsIssueStaleScanTitle,
            body: l10n.financeAgentOptionsIssueStaleScanBody(age.inHours),
            severity: AgentArtifactSeverity.attention,
            payload: <String, Object?>{
              'scan_id': scanState.scanId,
              'scanned_at': scanState.scannedAt.toUtc().toIso8601String(),
              'age_hours': age.inHours,
              'count': scanState.count,
            },
          ),
        );
      }
    }

    final elevated = opportunities
        .where((opp) => opp.risk == OpportunityRiskLevel.elevated)
        .toList(growable: false);
    if (elevated.isNotEmpty) {
      issues.add(
        OptionsRiskIssue(
          key: 'elevated_risk',
          title: l10n.financeAgentOptionsIssueElevatedRiskTitle,
          body: l10n.financeAgentOptionsIssueElevatedRiskBody(elevated.length),
          severity: AgentArtifactSeverity.warning,
          payload: <String, Object?>{
            'count': elevated.length,
            'symbols': [for (final opp in elevated.take(5)) _label(opp)],
          },
        ),
      );
    }

    final wideSpreads = opportunities
        .where((opp) => opp.contract.bidAskSpreadPct > Decimal.parse('0.08'))
        .toList(growable: false);
    final thinBooks = opportunities
        .where(
          (opp) => opp.contract.volume < 10 || opp.contract.openInterest < 100,
        )
        .toList(growable: false);
    if (wideSpreads.isNotEmpty || thinBooks.isNotEmpty) {
      final maxSpread = wideSpreads.fold<Decimal>(
        Decimal.zero,
        (max, opp) => opp.contract.bidAskSpreadPct > max
            ? opp.contract.bidAskSpreadPct
            : max,
      );
      issues.add(
        OptionsRiskIssue(
          key: 'quote_quality',
          title: l10n.financeAgentOptionsIssueQuoteQualityTitle,
          body: l10n.financeAgentOptionsIssueQuoteQualityBody(
            wideSpreads.length,
            thinBooks.length,
          ),
          severity: maxSpread > Decimal.parse('0.15')
              ? AgentArtifactSeverity.warning
              : AgentArtifactSeverity.attention,
          payload: <String, Object?>{
            'wide_spread_count': wideSpreads.length,
            'thin_book_count': thinBooks.length,
            'max_spread_pct': _pct(maxSpread),
          },
        ),
      );
    }

    final narrowCushion = opportunities
        .where(
          (opp) => switch (opp.metrics) {
            final OpportunityMetrics m =>
              m.marginOfSafety < Decimal.parse('0.05'),
            LeapsOpportunityMetrics() => false,
          },
        )
        .toList(growable: false);
    if (narrowCushion.isNotEmpty) {
      issues.add(
        OptionsRiskIssue(
          key: 'narrow_cushion',
          title: l10n.financeAgentOptionsIssueNarrowCushionTitle,
          body: l10n.financeAgentOptionsIssueNarrowCushionBody(
            narrowCushion.length,
          ),
          severity: AgentArtifactSeverity.attention,
          payload: <String, Object?>{
            'count': narrowCushion.length,
            'symbols': [for (final opp in narrowCushion.take(5)) _label(opp)],
          },
        ),
      );
    }

    final missingGreeks = opportunities
        .where(
          (opp) =>
              opp.contract.delta == null ||
              opp.contract.impliedVolatility == null,
        )
        .toList(growable: false);
    if (missingGreeks.isNotEmpty) {
      issues.add(
        OptionsRiskIssue(
          key: 'missing_greeks',
          title: l10n.financeAgentOptionsIssueMissingGreeksTitle,
          body: l10n.financeAgentOptionsIssueMissingGreeksBody(
            missingGreeks.length,
          ),
          severity: AgentArtifactSeverity.attention,
          payload: <String, Object?>{
            'count': missingGreeks.length,
            'symbols': [for (final opp in missingGreeks.take(5)) _label(opp)],
          },
        ),
      );
    }

    if (opportunities.length >= 3) {
      final counts = <String, int>{};
      for (final opp in opportunities) {
        counts.update(
          opp.contract.underlying,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final share = top.value / opportunities.length;
      if (share >= 0.5) {
        issues.add(
          OptionsRiskIssue(
            key: 'underlying_concentration',
            title: l10n.financeAgentOptionsIssueConcentrationTitle,
            body: l10n.financeAgentOptionsIssueConcentrationBody(
              top.value,
              opportunities.length,
              top.key,
            ),
            severity: AgentArtifactSeverity.attention,
            payload: <String, Object?>{
              'underlying': top.key,
              'count': top.value,
              'opportunity_count': opportunities.length,
              'share': share,
            },
          ),
        );
      }
    }

    final moderate = opportunities
        .where((opp) => opp.risk == OpportunityRiskLevel.moderate)
        .length;
    if (elevated.isEmpty &&
        moderate >= 3 &&
        moderate / opportunities.length >= 0.75) {
      issues.add(
        OptionsRiskIssue(
          key: 'moderate_risk_cluster',
          title: l10n.financeAgentOptionsIssueModerateClusterTitle,
          body: l10n.financeAgentOptionsIssueModerateClusterBody(
            moderate,
            opportunities.length,
          ),
          severity: AgentArtifactSeverity.attention,
          payload: <String, Object?>{
            'moderate_count': moderate,
            'opportunity_count': opportunities.length,
          },
        ),
      );
    }

    final hasWarning = issues.any(
      (issue) => issue.severity == AgentArtifactSeverity.warning,
    );
    return OptionsIncomeRiskAnalysis(
      snapshot: snapshot,
      issues: issues,
      severity: hasWarning
          ? AgentArtifactSeverity.warning
          : AgentArtifactSeverity.attention,
    );
  }

  final OptionsIncomeRiskSnapshot snapshot;
  final List<OptionsRiskIssue> issues;
  final AgentArtifactSeverity severity;

  bool get hasFinding => issues.isNotEmpty;

  List<OptionsOpportunity> get riskiestOpportunities {
    final copy = [...snapshot.opportunities];
    copy.sort((a, b) {
      final riskOrder = _riskRank(b.risk).compareTo(_riskRank(a.risk));
      if (riskOrder != 0) return riskOrder;
      return b.contract.bidAskSpreadPct.compareTo(a.contract.bidAskSpreadPct);
    });
    return copy.take(5).toList(growable: false);
  }

  String summary(AppLocalizations l10n) {
    final scanId =
        snapshot.scanState?.scanId ?? snapshot.opportunities.first.scanId;
    final elevatedCount = snapshot.opportunities
        .where((opp) => opp.risk == OpportunityRiskLevel.elevated)
        .length;
    final issueTitle = agentLocaleIsZh(l10n)
        ? issues.first.title
        : issues.first.title.toLowerCase();
    return l10n.financeAgentOptionsSummary(
      issueTitle,
      snapshot.opportunities.length,
      scanId,
      elevatedCount,
    );
  }

  Map<String, Object?> toPayload() => <String, Object?>{
    'scan_id':
        snapshot.scanState?.scanId ?? snapshot.opportunities.first.scanId,
    'scanned_at':
        (snapshot.scanState?.scannedAt ??
                snapshot.opportunities.first.scannedAt)
            .toUtc()
            .toIso8601String(),
    'opportunity_count': snapshot.opportunities.length,
    'severity': severity.wire,
    'issue_count': issues.length,
    'issues': [for (final issue in issues) issue.toPayload()],
    'risk_counts': _riskCounts(snapshot.opportunities),
    'riskiest': [
      for (final opportunity in riskiestOpportunities)
        _opportunityPayload(opportunity),
    ],
  };

  AgentArtifact toArtifact({
    required String id,
    required String ownerUserId,
    required String memoryId,
    required String? traceId,
    required DateTime createdAt,
    required AppLocalizations l10n,
  }) {
    final scanId =
        snapshot.scanState?.scanId ?? snapshot.opportunities.first.scanId;
    return AgentArtifact(
      id: id,
      ownerUserId: ownerUserId,
      agentId: kOptionsIncomeRiskReviewAgentId,
      domain: 'finance',
      kind: severity == AgentArtifactSeverity.warning
          ? AgentArtifactKind.alert
          : AgentArtifactKind.review,
      severity: severity,
      title: l10n.financeAgentOptionsTitle,
      summary: summary(l10n),
      metrics: <AgentMetric>[
        AgentMetric(
          label: l10n.financeAgentOptionsInsightScanSnapshotTitle,
          value: snapshot.opportunities.length.toString(),
          context: _riskMixLabel(l10n, snapshot.opportunities),
        ),
        AgentMetric(
          label: l10n.financeAgentOptionsAction,
          value: issues.length.toString(),
          severity: severity,
        ),
      ],
      insights: <AgentInsight>[
        for (final issue in issues.take(5))
          AgentInsight(
            id: issue.key,
            title: issue.title,
            body: issue.body,
            severity: issue.severity,
            route: FinanceRoutes.planIncome,
            payload: issue.payload,
          ),
        AgentInsight(
          id: 'scan_snapshot',
          title: l10n.financeAgentOptionsInsightScanSnapshotTitle,
          body: l10n.financeAgentOptionsInsightScanSnapshotBody(
            snapshot.opportunities.length,
            _riskMixLabel(l10n, snapshot.opportunities),
          ),
          payload: <String, Object?>{
            'scan_id': scanId,
            'risk_counts': _riskCounts(snapshot.opportunities),
          },
          route: FinanceRoutes.planIncome,
        ),
      ],
      evidence: <AgentEvidenceRef>[
        AgentEvidenceRef(
          type: 'options_income_scan',
          id: scanId,
          label: l10n.financeAgentOptionsEvidenceScanLabel(scanId),
          description: l10n.financeAgentOptionsInsightScanSnapshotBody(
            snapshot.opportunities.length,
            _riskMixLabel(l10n, snapshot.opportunities),
          ),
          route: FinanceRoutes.planIncome,
          payload: <String, Object?>{
            'scan_id': scanId,
            'scanned_at':
                (snapshot.scanState?.scannedAt ??
                        snapshot.opportunities.first.scannedAt)
                    .toUtc()
                    .toIso8601String(),
            'count': snapshot.opportunities.length,
          },
        ),
        for (final opportunity in riskiestOpportunities)
          AgentEvidenceRef(
            type: 'options_opportunity',
            id: opportunity.contract.optionSymbol,
            label: _label(opportunity),
            route: FinanceRoutes.planIncome,
            payload: _opportunityPayload(opportunity),
          ),
      ],
      actions: <AgentAction>[
        AgentAction(
          kind: 'review',
          label: l10n.financeAgentOptionsAction,
          intent: kAgentExplainResultIntent,
          objectType: kAgentArtifactObjectType,
          objectId: id,
          route: FinanceRoutes.planIncome,
        ),
      ],
      methodology: localAgentMethodology(
        l10n,
        sourceLabel: l10n.financeAgentOptionsEvidenceScanLabel(scanId),
      ),
      memoryId: memoryId,
      traceId: traceId,
      createdAt: createdAt.toUtc(),
      expiresAt: createdAt.toUtc().add(const Duration(days: 3)),
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
        label: 'options_income_risk_review',
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
            'agent_id': kOptionsIncomeRiskReviewAgentId,
            'surface': 'finance_home',
            'artifact_id': artifactId,
            'deterministic': true,
            'opportunity_count': snapshot.opportunities.length,
            'issue_count': issues.length,
            'severity': severity.wire,
          },
        ),
      ],
    );
  }
}

class OptionsRiskIssue {
  const OptionsRiskIssue({
    required this.key,
    required this.title,
    required this.body,
    required this.severity,
    required this.payload,
  });

  final String key;
  final String title;
  final String body;
  final AgentArtifactSeverity severity;
  final Map<String, Object?> payload;

  Map<String, Object?> toPayload() => <String, Object?>{
    'key': key,
    'title': title,
    'severity': severity.wire,
    ...payload,
  };
}

Map<String, int> _riskCounts(List<OptionsOpportunity> opportunities) {
  final counts = <String, int>{
    OpportunityRiskLevel.low.wire: 0,
    OpportunityRiskLevel.moderate.wire: 0,
    OpportunityRiskLevel.elevated.wire: 0,
  };
  for (final opportunity in opportunities) {
    counts.update(opportunity.risk.wire, (value) => value + 1);
  }
  return counts;
}

String _riskMixLabel(
  AppLocalizations l10n,
  List<OptionsOpportunity> opportunities,
) {
  final counts = _riskCounts(opportunities);
  return l10n.financeAgentOptionsRiskMix(
    counts['low'] ?? 0,
    counts['moderate'] ?? 0,
    counts['elevated'] ?? 0,
  );
}

Map<String, Object?> _opportunityPayload(OptionsOpportunity opportunity) {
  final contract = opportunity.contract;
  final metrics = switch (opportunity.metrics) {
    final OpportunityMetrics sell => sell,
    // The risk-review agent focuses on sell-side exposure; LEAPS rows
    // carry their own metrics shape and are summarised without them.
    LeapsOpportunityMetrics() => null,
  };
  return <String, Object?>{
    'scan_id': opportunity.scanId,
    'option_symbol': contract.optionSymbol,
    'underlying': contract.underlying,
    'strategy': opportunity.strategy.wire,
    'risk': opportunity.risk.wire,
    'score': opportunity.score.toString(),
    'dte': contract.dte,
    'bid_ask_spread_pct': _pct(contract.bidAskSpreadPct),
    'volume': contract.volume,
    'open_interest': contract.openInterest,
    'delta': contract.delta?.toString(),
    'implied_volatility': contract.impliedVolatility?.toString(),
    if (metrics != null) ...{
      'margin_of_safety': _pct(metrics.marginOfSafety),
      'annualized_yield': _pct(metrics.annualizedYield),
      'cash_required': metrics.cashRequired.amount.toString(),
      'currency': metrics.cashRequired.currency,
    },
    'why_risky': opportunity.explanation.whyRisky,
  };
}

String _label(OptionsOpportunity opportunity) {
  return '${opportunity.contract.underlying} '
      '${opportunity.contract.type.wire} ${opportunity.contract.strike.amount}';
}

int _riskRank(OpportunityRiskLevel risk) => switch (risk) {
  OpportunityRiskLevel.low => 0,
  OpportunityRiskLevel.moderate => 1,
  OpportunityRiskLevel.elevated => 2,
};

String _pct(Decimal value, {int decimalDigits = 1}) {
  return Fmt.signedPercent(
    value.toDouble(),
    decimalDigits: decimalDigits,
  ).replaceFirst('+', '');
}
