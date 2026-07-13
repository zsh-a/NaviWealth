/// `fire_plan_drift_monitor` — deterministic FIRE plan drift agent.
///
/// Reads the FIRE OS state and reuses the existing review engine. It only
/// emits an artifact when the review contains warning / critical findings;
/// healthy plans are recorded as skipped runs so schedules still advance.
library;

import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';

import '../../../core/ai/agents/agent.dart';
import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_store.dart';
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
import '../domain/fx/money.dart';
import '../fire/data/fire_providers.dart';
import '../fire/data/fire_review_cache.dart';
import '../fire/domain/fire_action.dart';
import '../fire/domain/fire_review.dart';
import '../fire/domain/fire_review_engine.dart';
import '../fire/domain/fire_state.dart';
import '../fire/domain/fire_stress_test.dart';

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
    final snapshot = await reader.read(ctx);
    return synthesize(
      review: snapshot?.review,
      stressTests: snapshot?.stressTests ?? const <FireStressResult>[],
      previousReview: snapshot?.previousReview,
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
    List<FireStressResult> stressTests = const <FireStressResult>[],
    FireReview? previousReview,
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

    final analysis = FirePlanDriftAnalysis.fromReview(
      review,
      stressTests: stressTests,
      previousReview: previousReview,
    );
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
  Future<FirePlanDriftSnapshot?> read(AgentContext ctx);
}

class ProviderFirePlanDriftMonitorReader implements FirePlanDriftMonitorReader {
  const ProviderFirePlanDriftMonitorReader();

  @override
  Future<FirePlanDriftSnapshot?> read(AgentContext ctx) async {
    final state = ctx.ref.read(fireStateProvider).value;
    if (state == null || !state.isConfigured) return null;
    final stress = ctx.ref.read(fireStressTestsProvider).value ?? const [];
    final review = generateReview(
      kind: FireReviewKind.monthly,
      state: state,
      stressTests: stress,
      now: ctx.now,
    );
    FireReview? previousReview;
    for (final cached in ctx.ref.read(fireReviewCacheProvider)) {
      if (cached.kind == FireReviewKind.monthly &&
          cached.periodKey != review.periodKey) {
        previousReview = cached;
        break;
      }
    }
    await ctx.ref.read(fireReviewCacheProvider.notifier).upsert(review);
    return FirePlanDriftSnapshot(
      review: review,
      stressTests: stress,
      previousReview: previousReview,
    );
  }
}

class FirePlanDriftSnapshot {
  const FirePlanDriftSnapshot({
    required this.review,
    required this.stressTests,
    this.previousReview,
  });

  final FireReview review;
  final List<FireStressResult> stressTests;
  final FireReview? previousReview;
}

class FirePlanDriftAnalysis {
  const FirePlanDriftAnalysis({
    required this.review,
    required this.concerningFindings,
    required this.stressTests,
    required this.diff,
    required this.severity,
  });

  factory FirePlanDriftAnalysis.fromReview(
    FireReview review, {
    List<FireStressResult> stressTests = const <FireStressResult>[],
    FireReview? previousReview,
  }) {
    final findings = review.findings
        .where((finding) => finding.severity != FireActionSeverity.info)
        .toList(growable: false);
    final hasCritical = findings.any(
      (finding) => finding.severity == FireActionSeverity.critical,
    );
    return FirePlanDriftAnalysis(
      review: review,
      concerningFindings: findings,
      stressTests: stressTests
          .where((result) => result.verdict != FireStressVerdict.safe)
          .toList(growable: false),
      diff: FireReviewDiff(before: previousReview, after: review),
      severity: hasCritical
          ? AgentArtifactSeverity.warning
          : AgentArtifactSeverity.attention,
    );
  }

  final FireReview review;
  final List<FireReviewFinding> concerningFindings;
  final List<FireStressResult> stressTests;
  final FireReviewDiff diff;
  final AgentArtifactSeverity severity;

  bool get hasDrift => concerningFindings.isNotEmpty;

  String summary(AppLocalizations l10n) {
    final parts = <String>[];
    if (review.withdrawalRate.isFinite) {
      parts.add(
        _withdrawalSummary(
          l10n,
          safeRate: _rate(review.safeWithdrawalRate),
          withdrawalRate: _rate(review.withdrawalRate),
        ),
      );
    } else {
      parts.add(_findingBody(l10n, concerningFindings.first));
    }
    final failedCount = _stressFailureCount;
    if (failedCount > 0) {
      parts.add(l10n.financeAgentFireSummaryStress(failedCount));
    }
    return parts.join(l10n.financeAgentFireSummarySeparator);
  }

  int get _stressFailureCount {
    if (stressTests.isNotEmpty) return stressTests.length;
    return concerningFindings.where(_isStressFinding).length;
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
    if (stressTests.isNotEmpty)
      'stress_tests': [for (final result in stressTests) result.toJson()],
    if (diff.before != null) ...<String, Object?>{
      'previous_period_key': diff.before!.periodKey,
      'withdrawal_rate_delta': diff.withdrawalRateDelta,
      'net_worth_delta': diff.netWorthDelta?.toString(),
      'safety_level_changed': diff.safetyLevelChanged,
    },
  };

  AgentArtifact toArtifact({
    required String id,
    required String ownerUserId,
    required String memoryId,
    required String? traceId,
    required DateTime createdAt,
    required AppLocalizations l10n,
  }) {
    final metrics = _headlineMetrics(l10n);
    final primaryFindings = concerningFindings
        .where((finding) => !_isStressFinding(finding))
        .take(4)
        .toList(growable: false);
    final stressFindings = concerningFindings
        .where(_isStressFinding)
        .toList(growable: false);
    final trendDetails = _trendDetails(l10n);
    return AgentArtifact(
      id: id,
      ownerUserId: ownerUserId,
      agentId: kFirePlanDriftMonitorAgentId,
      domain: 'finance',
      kind: AgentArtifactKind.review,
      severity: severity,
      title: l10n.financeAgentFireTitle,
      summary: summary(l10n),
      metrics: metrics,
      insights: <AgentInsight>[
        for (final finding in primaryFindings)
          AgentInsight(
            id: _findingEvidenceId(finding),
            title: _findingTitle(l10n, finding),
            body: _findingBody(l10n, finding),
            severity: _severity(finding.severity),
            details: _findingDetails(l10n, finding),
            evidenceIds: <String>[_findingEvidenceId(finding)],
            route: FinanceRoutes.planFire,
            payload: finding.toJson(),
          ),
        if (stressTests.isNotEmpty || stressFindings.isNotEmpty)
          AgentInsight(
            id: 'stress_tests',
            title: l10n.financeAgentFireStressGroupTitle(_stressFailureCount),
            body: _stressGroupBody(l10n, stressFindings),
            severity: severity,
            details: _stressDetails(l10n, stressFindings),
            evidenceIds: _stressEvidenceIds(stressFindings),
            route: FinanceRoutes.planFire,
            payload: <String, Object?>{
              'failed_count': _stressFailureCount,
              if (stressTests.isNotEmpty)
                'results': [for (final result in stressTests) result.toJson()],
            },
          ),
        if (trendDetails.isNotEmpty)
          AgentInsight(
            id: 'period_change',
            title: l10n.financeAgentFireTrendTitle,
            body: l10n.financeAgentFireTrendBody(
              trendDetails
                  .map((detail) => '${detail.label} ${detail.value}')
                  .join(l10n.financeAgentFireSummarySeparator),
            ),
            details: trendDetails,
            route: FinanceRoutes.planFire,
          ),
      ],
      evidence: <AgentEvidenceRef>[
        AgentEvidenceRef(
          type: 'fire_review',
          id: review.periodKey,
          label: l10n.financeAgentFireEvidenceReviewLabel(review.periodKey),
          description: l10n.financeAgentFireEvidenceReviewBody,
          route: FinanceRoutes.planFire,
          details: metrics,
          payload: review.toJson(),
        ),
        for (final finding in primaryFindings)
          AgentEvidenceRef(
            type: 'fire_finding',
            id: _findingEvidenceId(finding),
            label: _findingTitle(l10n, finding),
            description: _findingBody(l10n, finding),
            route: FinanceRoutes.planFire,
            details: _findingDetails(l10n, finding),
            payload: finding.toJson(),
          ),
        if (stressTests.isNotEmpty)
          for (final result in stressTests)
            AgentEvidenceRef(
              type: 'fire_stress_test',
              id: 'stress:${_scenarioWire(result.scenario)}',
              label: _scenarioLabel(l10n, result.scenario),
              description: _stressResultContext(l10n, result),
              route: FinanceRoutes.planFire,
              details: _stressResultDetails(l10n, result),
              payload: result.toJson(),
            )
        else
          for (final finding in stressFindings)
            AgentEvidenceRef(
              type: 'fire_stress_test',
              id: _findingEvidenceId(finding),
              label: _scenarioLabelFromCode(l10n, finding.scenarioCode),
              description: _findingBody(l10n, finding),
              route: FinanceRoutes.planFire,
              payload: finding.toJson(),
            ),
      ],
      actions: <AgentAction>[
        AgentAction(
          kind: 'open_route',
          label: l10n.financeAgentFireAction,
          description: l10n.financeAgentFireActionBody,
          route: FinanceRoutes.planFire,
        ),
      ],
      methodology: AgentMethodology(
        title: l10n.financeAgentFireMethodTitle,
        body: l10n.financeAgentFireMethodBody,
        details: <AgentMetric>[
          AgentMetric(
            label: l10n.financeAgentFireMethodPeriodLabel,
            value: review.periodKey,
          ),
          AgentMetric(
            label: l10n.financeAgentFireMethodModeLabel,
            value: l10n.financeAgentFireMethodModeValue,
          ),
        ],
      ),
      memoryId: memoryId,
      traceId: traceId,
      createdAt: createdAt.toUtc(),
      expiresAt: createdAt.toUtc().add(const Duration(days: 14)),
    );
  }

  List<AgentMetric> _headlineMetrics(AppLocalizations l10n) => <AgentMetric>[
    AgentMetric(
      label: l10n.financeAgentFireMetricWithdrawalRate,
      value: _rate(review.withdrawalRate),
      severity: review.withdrawalRate > review.safeWithdrawalRate
          ? AgentArtifactSeverity.warning
          : AgentArtifactSeverity.info,
    ),
    AgentMetric(
      label: l10n.financeAgentFireMetricSafeRate,
      value: _rate(review.safeWithdrawalRate),
    ),
    AgentMetric(
      label: l10n.financeAgentFireMetricCashBucket,
      value: l10n.financeAgentFireMonthsValue(_months(review.cashBucketMonths)),
      context: l10n.financeAgentFireMetricTargetMonths(
        review.targetCashBucketMonths,
      ),
      severity: review.cashBucketMonths < review.targetCashBucketMonths
          ? AgentArtifactSeverity.attention
          : AgentArtifactSeverity.info,
    ),
  ];

  List<AgentMetric> _findingDetails(
    AppLocalizations l10n,
    FireReviewFinding finding,
  ) => switch (finding.code) {
    FireReviewFindingCode.withdrawalRateAboveSwr => <AgentMetric>[
      AgentMetric(
        label: l10n.financeAgentFireMetricWithdrawalRate,
        value: _rate(review.withdrawalRate),
        severity: _severity(finding.severity),
      ),
      AgentMetric(
        label: l10n.financeAgentFireMetricSafeRate,
        value: _rate(review.safeWithdrawalRate),
      ),
      if (finding.pct case final pct?)
        AgentMetric(
          label: l10n.financeAgentFireMetricExcess,
          value: _percentagePoints(l10n, pct),
          severity: _severity(finding.severity),
        ),
    ],
    FireReviewFindingCode.belowTargetCashBucket => <AgentMetric>[
      AgentMetric(
        label: l10n.financeAgentFireMetricCashBucket,
        value: l10n.financeAgentFireMonthsValue(
          _months(review.cashBucketMonths),
        ),
        severity: _severity(finding.severity),
      ),
      AgentMetric(
        label: l10n.financeAgentFireMetricTarget,
        value: l10n.financeAgentFireMonthsValue(
          review.targetCashBucketMonths.toString(),
        ),
      ),
    ],
    FireReviewFindingCode.currencyGapPresent ||
    FireReviewFindingCode.unmappedHoldingsPresent => <AgentMetric>[
      AgentMetric(
        label: l10n.financeAgentFireMetricAffectedItems,
        value: (finding.months ?? 0).toString(),
        severity: _severity(finding.severity),
      ),
    ],
    _ => const <AgentMetric>[],
  };

  String _stressGroupBody(
    AppLocalizations l10n,
    List<FireReviewFinding> findings,
  ) {
    final labels = stressTests.isNotEmpty
        ? [
            for (final result in stressTests)
              _scenarioLabel(l10n, result.scenario),
          ]
        : [
            for (final finding in findings)
              _scenarioLabelFromCode(l10n, finding.scenarioCode),
          ];
    return l10n.financeAgentFireStressGroupBody(
      labels.join(l10n.financeAgentFireScenarioSeparator),
    );
  }

  List<AgentMetric> _stressDetails(
    AppLocalizations l10n,
    List<FireReviewFinding> findings,
  ) {
    if (stressTests.isNotEmpty) {
      return [
        for (final result in stressTests)
          AgentMetric(
            label: _scenarioLabel(l10n, result.scenario),
            value: _stressVerdictLabel(l10n, result.verdict),
            context: _stressResultContext(l10n, result),
            severity: result.verdict == FireStressVerdict.danger
                ? AgentArtifactSeverity.warning
                : AgentArtifactSeverity.attention,
          ),
      ];
    }
    return [
      for (final finding in findings)
        AgentMetric(
          label: _scenarioLabelFromCode(l10n, finding.scenarioCode),
          value: finding.severity == FireActionSeverity.critical
              ? l10n.financeAgentFireStressVerdictDanger
              : l10n.financeAgentFireStressVerdictCautious,
          severity: _severity(finding.severity),
        ),
    ];
  }

  List<String> _stressEvidenceIds(List<FireReviewFinding> findings) {
    if (stressTests.isNotEmpty) {
      return [
        for (final result in stressTests)
          'stress:${_scenarioWire(result.scenario)}',
      ];
    }
    return [for (final finding in findings) _findingEvidenceId(finding)];
  }

  List<AgentMetric> _stressResultDetails(
    AppLocalizations l10n,
    FireStressResult result,
  ) => <AgentMetric>[
    AgentMetric(
      label: l10n.financeAgentFireMetricNetWorthAfter,
      value: _money(result.netWorthAfter, l10n),
    ),
    AgentMetric(
      label: l10n.financeAgentFireMetricWithdrawalAfter,
      value: _rate(result.withdrawalRateAfter),
      severity: result.verdict == FireStressVerdict.danger
          ? AgentArtifactSeverity.warning
          : AgentArtifactSeverity.attention,
    ),
    AgentMetric(
      label: l10n.financeAgentFireMetricCashAfter,
      value: l10n.financeAgentFireMonthsValue(
        _months(result.cashBucketMonthsAfter),
      ),
    ),
  ];

  List<AgentMetric> _trendDetails(AppLocalizations l10n) {
    if (diff.before == null) return const <AgentMetric>[];
    final details = <AgentMetric>[];
    if (diff.withdrawalRateDelta case final delta?) {
      if (delta.abs() >= 0.00005) {
        details.add(
          AgentMetric(
            label: l10n.financeAgentFireTrendWithdrawal,
            value: _percentagePoints(l10n, delta, signed: true),
            severity: delta > 0
                ? AgentArtifactSeverity.warning
                : AgentArtifactSeverity.info,
          ),
        );
      }
    }
    if (diff.netWorthDelta case final delta?) {
      if (delta.sign != 0) {
        details.add(
          AgentMetric(
            label: l10n.financeAgentFireTrendNetWorth,
            value: _signedMoney(delta, review.baseCurrency, l10n),
            severity: delta.sign < 0 ? AgentArtifactSeverity.attention : null,
          ),
        );
      }
    }
    if (diff.safetyLevelChanged) {
      details.add(
        AgentMetric(
          label: l10n.financeAgentFireTrendSafety,
          value:
              '${_safetyLabel(l10n, diff.before!.safetyLevel)} → '
              '${_safetyLabel(l10n, review.safetyLevel)}',
          severity: severity,
        ),
      );
    }
    return details;
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

bool _isStressFinding(FireReviewFinding finding) =>
    finding.code == FireReviewFindingCode.stressTestDanger ||
    finding.code == FireReviewFindingCode.stressTestCautious;

String _findingEvidenceId(FireReviewFinding finding) {
  final scenario = finding.scenarioCode;
  return scenario == null
      ? 'finding:${finding.code.name}'
      : 'finding:${finding.code.name}:$scenario';
}

String _scenarioWire(FireStressScenario scenario) => switch (scenario) {
  FireStressScenario.marketDrawdown => 'market_drawdown',
  FireStressScenario.expenseSurge => 'expense_surge',
  FireStressScenario.oneOffShock => 'one_off_shock',
  FireStressScenario.fxShock => 'fx_shock',
  FireStressScenario.cashDepletion => 'cash_depletion',
};

String _scenarioLabel(
  AppLocalizations l10n,
  FireStressScenario scenario,
) => switch (scenario) {
  FireStressScenario.marketDrawdown =>
    l10n.financeAgentFireScenarioMarketDrawdown,
  FireStressScenario.expenseSurge => l10n.financeAgentFireScenarioExpenseSurge,
  FireStressScenario.oneOffShock => l10n.financeAgentFireScenarioOneOffShock,
  FireStressScenario.fxShock => l10n.financeAgentFireScenarioFxShock,
  FireStressScenario.cashDepletion =>
    l10n.financeAgentFireScenarioCashDepletion,
};

String _scenarioLabelFromCode(AppLocalizations l10n, String? code) =>
    switch (code) {
      'market_drawdown' => l10n.financeAgentFireScenarioMarketDrawdown,
      'expense_surge' => l10n.financeAgentFireScenarioExpenseSurge,
      'one_off_shock' => l10n.financeAgentFireScenarioOneOffShock,
      'fx_shock' => l10n.financeAgentFireScenarioFxShock,
      'cash_depletion' => l10n.financeAgentFireScenarioCashDepletion,
      _ => l10n.financeAgentFireScenarioUnknown,
    };

String _stressVerdictLabel(AppLocalizations l10n, FireStressVerdict verdict) =>
    switch (verdict) {
      FireStressVerdict.safe => l10n.financeAgentFireStressVerdictSafe,
      FireStressVerdict.cautious => l10n.financeAgentFireStressVerdictCautious,
      FireStressVerdict.danger => l10n.financeAgentFireStressVerdictDanger,
    };

String _stressResultContext(AppLocalizations l10n, FireStressResult result) =>
    l10n.financeAgentFireStressResultContext(
      _months(result.cashBucketMonthsAfter),
      _rate(result.withdrawalRateAfter),
    );

String _withdrawalSummary(
  AppLocalizations l10n, {
  required String safeRate,
  required String withdrawalRate,
}) => l10n.financeAgentFireSummaryWithdrawal(safeRate, withdrawalRate);

String _percentagePoints(
  AppLocalizations l10n,
  double value, {
  bool signed = false,
}) {
  if (!value.isFinite) return 'n/a';
  final points = value * 100;
  final prefix = signed && points > 0 ? '+' : '';
  final formatted = '$prefix${Fmt.number(points, decimalDigits: 1)}';
  return l10n.financeAgentFirePercentagePoints(formatted);
}

String _money(Money money, AppLocalizations l10n) {
  final locale = Locale(l10n.localeName);
  return AppFormatters(
    locale: locale,
    baseCurrency: money.currency,
  ).currency(money.amount, code: money.currency);
}

String _signedMoney(Decimal value, String currency, AppLocalizations l10n) {
  final formatted = _money(Money(value.abs(), currency), l10n);
  if (value.sign > 0) return '+$formatted';
  if (value.sign < 0) return '-$formatted';
  return formatted;
}

String _safetyLabel(AppLocalizations l10n, FireSafetyLevel level) =>
    switch (level) {
      FireSafetyLevel.unconfigured => l10n.fireOsSafetyUnconfigured,
      FireSafetyLevel.safe => l10n.fireOsSafetySafe,
      FireSafetyLevel.cautious => l10n.fireOsSafetyCautious,
      FireSafetyLevel.danger => l10n.fireOsSafetyDanger,
    };

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
        _percentagePoints(l10n, finding.pct ?? 0),
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
        _scenarioLabelFromCode(l10n, finding.scenarioCode),
      ),
    FireReviewFindingCode.stressTestCautious =>
      l10n.financeAgentFireFindingStressCautiousBody(
        _scenarioLabelFromCode(l10n, finding.scenarioCode),
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
