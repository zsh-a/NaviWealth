/// `fire_plan_drift_monitor` — deterministic FIRE plan drift agent.
///
/// Reads the FIRE OS state and reuses the existing review engine. It only
/// emits an artifact when the review contains warning / critical findings;
/// healthy plans are recorded as skipped runs so schedules still advance.
library;

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
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
import '../fire/data/fire_providers.dart';
import '../fire/domain/fire_action.dart';
import '../fire/domain/fire_review.dart';
import '../fire/domain/fire_review_engine.dart';

const String kFirePlanDriftMonitorAgentId = 'fire_plan_drift_monitor';
const String kFirePlanDriftMonitorMemorySource =
    'agent:fire_plan_drift_monitor';

class FirePlanDriftMonitorAgent implements Agent {
  const FirePlanDriftMonitorAgent({
    this.reader = const ProviderFirePlanDriftMonitorReader(),
  });

  final FirePlanDriftMonitorReader reader;

  @override
  String get id => kFirePlanDriftMonitorAgentId;

  @override
  String get name => 'FIRE Plan Drift Monitor';

  @override
  AgentSchedule get schedule =>
      const AgentSchedule(interval: Duration(days: 7), preferredHourLocal: 19);

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    final startedAt = ctx.now;
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final runtime = await ctx.ref.read(memoryRuntimeProvider.future);
    final artifactStore = await ctx.ref.read(
      agent_providers.agentArtifactStoreProvider.future,
    );
    final traceStore = ctx.ref.read(aiTraceStoreProvider);
    final review = await reader.read(ctx);
    return synthesize(
      review: review,
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
    required FireReview? review,
    required String ownerUserId,
    required DateTime startedAt,
    required DateTime finishedAt,
    required MemoryRuntime runtime,
    AgentArtifactStore? artifactStore,
    AiTraceStore? traceStore,
    AppLocalizations? l10n,
  }) async {
    final strings = l10n ?? defaultAgentL10n();
    if (review == null) {
      return AgentRunResult.skipped(
        agentId: kFirePlanDriftMonitorAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: strings.financeAgentFireSkipNoPlan,
      );
    }

    final analysis = FirePlanDriftAnalysis.fromReview(review);
    if (!analysis.hasDrift) {
      return AgentRunResult.skipped(
        agentId: kFirePlanDriftMonitorAgentId,
        startedAt: startedAt,
        finishedAt: finishedAt,
        reason: strings.financeAgentFireSkipNoDrift,
      );
    }

    final dayKey = AppFormatters.utcDayKey(startedAt);
    final memoryId = '$kFirePlanDriftMonitorMemorySource:$dayKey';
    final artifactId = '$kFirePlanDriftMonitorAgentId:$dayKey';
    final traceId = '$kFirePlanDriftMonitorAgentId:trace:$dayKey';
    final summary = analysis.summary(strings);
    final memory = MemoryRecord(
      id: memoryId,
      kind: MemoryKind.episodic,
      ownerUserId: ownerUserId,
      scope: 'finance',
      source: kFirePlanDriftMonitorMemorySource,
      sourceId: dayKey,
      title: strings.financeAgentFireMemoryTitle(dayKey),
      summary: summary,
      payload: <String, Object?>{
        'context':
            'FIRE plan drift monitor run at ${startedAt.toUtc().toIso8601String()}',
        'outcome': analysis.toPayload(),
        'artifact_id': artifactId,
        if (traceStore != null) 'trace_id': traceId,
      },
      entities: <String>{
        'finance',
        'fire',
        'fire_plan',
        'drift',
        review.periodKey,
        for (final finding in analysis.concerningFindings)
          'fire_finding:${finding.code.name}',
      },
      importance: analysis.severity == AgentArtifactSeverity.warning
          ? 0.78
          : 0.66,
      confidence: 0.92,
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
      agentId: kFirePlanDriftMonitorAgentId,
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

abstract class FirePlanDriftMonitorReader {
  Future<FireReview?> read(AgentContext ctx);
}

class ProviderFirePlanDriftMonitorReader implements FirePlanDriftMonitorReader {
  const ProviderFirePlanDriftMonitorReader();

  @override
  Future<FireReview?> read(AgentContext ctx) async {
    final state = ctx.ref.read(fireStateProvider).value;
    if (state == null || !state.isConfigured) return null;
    final stress = ctx.ref.read(fireStressTestsProvider).value ?? const [];
    return generateReview(
      kind: FireReviewKind.monthly,
      state: state,
      stressTests: stress,
      now: ctx.now,
    );
  }
}

class FirePlanDriftAnalysis {
  const FirePlanDriftAnalysis({
    required this.review,
    required this.concerningFindings,
    required this.severity,
  });

  factory FirePlanDriftAnalysis.fromReview(FireReview review) {
    final findings = review.findings
        .where((finding) => finding.severity != FireActionSeverity.info)
        .toList(growable: false);
    final hasCritical = findings.any(
      (finding) => finding.severity == FireActionSeverity.critical,
    );
    return FirePlanDriftAnalysis(
      review: review,
      concerningFindings: findings,
      severity: hasCritical
          ? AgentArtifactSeverity.warning
          : AgentArtifactSeverity.attention,
    );
  }

  final FireReview review;
  final List<FireReviewFinding> concerningFindings;
  final AgentArtifactSeverity severity;

  bool get hasDrift => concerningFindings.isNotEmpty;

  String summary(AppLocalizations l10n) {
    final headline = concerningFindings.first;
    // The feed summary should explain the leading finding in user language.
    // Diagnostic values remain available in insights and evidence, where
    // unavailable rates/months have enough context and do not leak raw
    // `n/a` or enum names into the home cockpit.
    return _findingBody(l10n, headline);
  }

  Map<String, Object?> toPayload() => <String, Object?>{
    'period_key': review.periodKey,
    'safety_level': review.safetyLevel.name,
    'net_worth': review.netWorth.amount.toString(),
    'investable_assets': review.investableAssets.amount.toString(),
    'annual_spend': review.annualSpend.amount.toString(),
    'withdrawal_rate': review.withdrawalRate.isFinite
        ? review.withdrawalRate
        : null,
    'safe_withdrawal_rate': review.safeWithdrawalRate,
    'cash_bucket_months': review.cashBucketMonths.isFinite
        ? review.cashBucketMonths
        : null,
    'target_cash_bucket_months': review.targetCashBucketMonths,
    'fire_eta_months': review.fireEtaMonths,
    'finding_count': concerningFindings.length,
    'findings': [for (final finding in concerningFindings) finding.toJson()],
  };

  AgentArtifact toArtifact({
    required String id,
    required String ownerUserId,
    required String memoryId,
    required String? traceId,
    required DateTime createdAt,
    required AppLocalizations l10n,
  }) {
    return AgentArtifact(
      id: id,
      ownerUserId: ownerUserId,
      agentId: kFirePlanDriftMonitorAgentId,
      domain: 'finance',
      kind: AgentArtifactKind.review,
      severity: severity,
      title: l10n.financeAgentFireTitle,
      summary: summary(l10n),
      insights: <AgentInsight>[
        for (final finding in concerningFindings.take(4))
          AgentInsight(
            title: _findingTitle(l10n, finding),
            body: _findingBody(l10n, finding),
            severity: _severity(finding.severity),
            payload: finding.toJson(),
          ),
        AgentInsight(
          title: l10n.financeAgentFireInsightPlanSnapshotTitle,
          body: l10n.financeAgentFireInsightPlanSnapshotBody(
            _rate(review.withdrawalRate),
            _rate(review.safeWithdrawalRate),
            _months(review.cashBucketMonths),
            review.targetCashBucketMonths,
          ),
          payload: <String, Object?>{
            'withdrawal_rate': review.withdrawalRate.isFinite
                ? review.withdrawalRate
                : null,
            'safe_withdrawal_rate': review.safeWithdrawalRate,
            'cash_bucket_months': review.cashBucketMonths.isFinite
                ? review.cashBucketMonths
                : null,
            'target_cash_bucket_months': review.targetCashBucketMonths,
          },
        ),
      ],
      evidence: <AgentEvidenceRef>[
        AgentEvidenceRef(
          type: 'fire_review',
          id: review.periodKey,
          label: l10n.financeAgentFireEvidenceReviewLabel(review.periodKey),
          payload: review.toJson(),
        ),
        for (final finding in concerningFindings.take(6))
          AgentEvidenceRef(
            type: 'fire_finding',
            id: finding.code.name,
            label: _findingTitle(l10n, finding),
            payload: finding.toJson(),
          ),
      ],
      actions: <AgentAction>[
        AgentAction(
          kind: 'review',
          label: l10n.financeAgentFireAction,
          intent: kAgentExplainResultIntent,
          objectType: kAgentArtifactObjectType,
          objectId: id,
        ),
      ],
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
        capability: Capability.analyze,
        risk: RiskLevel.info,
        label: 'fire_plan_drift_monitor',
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
            'agent_id': kFirePlanDriftMonitorAgentId,
            'surface': 'finance_home',
            'artifact_id': artifactId,
            'deterministic': true,
            'period_key': review.periodKey,
            'safety_level': review.safetyLevel.name,
            'finding_count': concerningFindings.length,
          },
        ),
      ],
    );
  }
}

AgentArtifactSeverity _severity(FireActionSeverity severity) =>
    switch (severity) {
      FireActionSeverity.info => AgentArtifactSeverity.info,
      FireActionSeverity.warning => AgentArtifactSeverity.attention,
      FireActionSeverity.critical => AgentArtifactSeverity.warning,
    };

String _findingTitle(AppLocalizations l10n, FireReviewFinding finding) =>
    switch (finding.code) {
      FireReviewFindingCode.belowTargetCashBucket =>
        l10n.financeAgentFireFindingCashBucketBelowTargetTitle,
      FireReviewFindingCode.withdrawalRateAboveSwr =>
        l10n.financeAgentFireFindingWithdrawalRateAboveSwrTitle,
      FireReviewFindingCode.withdrawalRateInfinite =>
        l10n.financeAgentFireFindingWithdrawalRateInfiniteTitle,
      FireReviewFindingCode.fireEtaUnreachable =>
        l10n.financeAgentFireFindingEtaUnreachableTitle,
      FireReviewFindingCode.currencyGapPresent =>
        l10n.financeAgentFireFindingCurrencyGapTitle,
      FireReviewFindingCode.unmappedHoldingsPresent =>
        l10n.financeAgentFireFindingUnmappedHoldingsTitle,
      FireReviewFindingCode.stressTestDanger =>
        l10n.financeAgentFireFindingStressDangerTitle,
      FireReviewFindingCode.stressTestCautious =>
        l10n.financeAgentFireFindingStressCautiousTitle,
      FireReviewFindingCode.netWorthBroken =>
        l10n.financeAgentFireFindingNetWorthBrokenTitle,
      _ => finding.code.name,
    };

String _findingBody(AppLocalizations l10n, FireReviewFinding finding) {
  return switch (finding.code) {
    FireReviewFindingCode.belowTargetCashBucket =>
      l10n.financeAgentFireFindingCashBucketBelowTargetBody(
        finding.months ?? 0,
      ),
    FireReviewFindingCode.withdrawalRateAboveSwr =>
      l10n.financeAgentFireFindingWithdrawalRateAboveSwrBody(
        _rate(finding.pct ?? 0),
      ),
    FireReviewFindingCode.withdrawalRateInfinite =>
      l10n.financeAgentFireFindingWithdrawalRateInfiniteBody,
    FireReviewFindingCode.fireEtaUnreachable =>
      l10n.financeAgentFireFindingEtaUnreachableBody,
    FireReviewFindingCode.currencyGapPresent =>
      l10n.financeAgentFireFindingCurrencyGapBody(finding.months ?? 0),
    FireReviewFindingCode.unmappedHoldingsPresent =>
      l10n.financeAgentFireFindingUnmappedHoldingsBody(finding.months ?? 0),
    FireReviewFindingCode.stressTestDanger =>
      l10n.financeAgentFireFindingStressDangerBody(
        finding.scenarioCode ?? 'unknown',
      ),
    FireReviewFindingCode.stressTestCautious =>
      l10n.financeAgentFireFindingStressCautiousBody(
        finding.scenarioCode ?? 'unknown',
      ),
    FireReviewFindingCode.netWorthBroken =>
      l10n.financeAgentFireFindingNetWorthBrokenBody,
    _ => l10n.financeAgentFireFindingDefaultBody(finding.code.name),
  };
}

String _rate(double value) {
  if (!value.isFinite) return 'n/a';
  return Fmt.signedPercent(value, decimalDigits: 1).replaceFirst('+', '');
}

String _months(double value) {
  if (!value.isFinite) return 'n/a';
  return Fmt.number(value, decimalDigits: 1);
}
