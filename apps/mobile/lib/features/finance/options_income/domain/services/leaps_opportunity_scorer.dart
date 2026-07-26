import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/domain/fx/money.dart';
import '../opportunity_explanation.dart';
import '../option_contract.dart';
import '../options_opportunity.dart';
import '../options_strategy_profile.dart';
import 'opportunity_explanation_texts.dart';

/// Buy-side scorer for the LEAPS call lane.
///
/// Deliberately not a variant of [OpportunityScorer]: selling income and
/// buying long-dated exposure have opposite economics (high IV helps the
/// seller and hurts the buyer; annualized yield is meaningless on a
/// debit). MVP ranking uses one transparent metric — the annualized
/// time-value cost per unit of delta-equivalent share exposure ("yearly
/// rent per share of exposure") — instead of an opaque composite score.
class LeapsOpportunityScorer {
  const LeapsOpportunityScorer({
    this.texts = const DefaultOpportunityExplanationTexts(),
  });

  final OpportunityExplanationTexts texts;

  /// Score one call contract for the LEAPS lane. Returns `null` when a
  /// hard filter rejects it — the caller can capture reasons via
  /// [filter].
  OptionsOpportunity? scoreOne({
    required OptionContract contract,
    required OptionsStrategyProfile profile,
    Money? budgetRemaining,
    Money? groupFundingPool,
    bool ignoreOpenInterestFloor = false,
    DateTime? now,
  }) {
    if (_rejectionReasons(
      contract: contract,
      profile: profile,
      budgetRemaining: budgetRemaining,
      ignoreOpenInterestFloor: ignoreOpenInterestFloor,
    ).isNotEmpty) {
      return null;
    }
    final asOf = now ?? DateTime.now().toUtc();
    final delta = contract.delta!;
    final currency = contract.strike.currency;
    final hundred = Decimal.fromInt(100);

    final totalCost = contract.mid.amount * hundred;
    final intrinsicPerShare = _max(
      contract.underlyingPrice.amount - contract.strike.amount,
      Decimal.zero,
    );
    final intrinsicTotal = intrinsicPerShare * hundred;
    final extrinsic = _max(totalCost - intrinsicTotal, Decimal.zero);
    final extrinsicRatio = _ratio(extrinsic, totalCost);
    final exposure = contract.underlyingPrice.amount * delta * hundred;
    final leverage = exposure == Decimal.zero
        ? null
        : _ratio(exposure, totalCost);
    final annualizedCost = exposure == Decimal.zero
        ? null
        : _ratio(
            extrinsic * Decimal.fromInt(365),
            exposure * Decimal.fromInt(contract.dte),
          );
    final fundingCoverage =
        groupFundingPool != null &&
            groupFundingPool.currency == currency &&
            totalCost > Decimal.zero
        ? _ratio(groupFundingPool.amount, totalCost)
        : null;

    final metrics = LeapsOpportunityMetrics(
      totalCost: Money(totalCost, currency),
      breakeven: Money(contract.strike.amount + contract.mid.amount, currency),
      extrinsicValue: Money(extrinsic, currency),
      extrinsicRatio: extrinsicRatio,
      leverageRatio: leverage,
      annualizedExtrinsicCostPct: annualizedCost,
      fundingCoveragePct: fundingCoverage,
    );

    // Rank purely by cost efficiency, clamped into [0, 1] so the lane
    // sorts alongside itself in the shared cache ordering.
    final score = annualizedCost == null
        ? Decimal.zero
        : _clamp01(Decimal.one - annualizedCost);

    return OptionsOpportunity(
      strategy: OpportunityStrategy.leapsCall,
      contract: contract,
      metrics: metrics,
      risk: _risk(
        extrinsicRatio: extrinsicRatio,
        delta: delta,
        spread: contract.bidAskSpreadPct,
        profile: profile,
      ),
      explanation: _explanation(
        contract: contract,
        metrics: metrics,
        delta: delta,
        score: score,
      ),
      score: score,
      scannedAt: asOf,
      scanId: '${asOf.toIso8601String()}-${contract.optionSymbol}',
    );
  }

  /// Rejection reasons for a candidate [scoreOne] returned `null` for.
  RejectedCandidate? filter({
    required OptionContract contract,
    required OptionsStrategyProfile profile,
    Money? budgetRemaining,
    bool ignoreOpenInterestFloor = false,
  }) {
    final reasons = _rejectionReasons(
      contract: contract,
      profile: profile,
      budgetRemaining: budgetRemaining,
      ignoreOpenInterestFloor: ignoreOpenInterestFloor,
    );
    if (reasons.isEmpty) return null;
    return RejectedCandidate(
      optionSymbol: contract.optionSymbol,
      reasons: reasons,
    );
  }

  List<String> _rejectionReasons({
    required OptionContract contract,
    required OptionsStrategyProfile profile,
    required Money? budgetRemaining,
    required bool ignoreOpenInterestFloor,
  }) {
    final reasons = <String>[];
    if (contract.type != OptionType.call) {
      reasons.add('not_a_call');
      return reasons;
    }
    if (contract.mid.amount <= Decimal.zero) {
      reasons.add('quote_unavailable');
      return reasons;
    }
    if (contract.dte < profile.leapsMinDte ||
        contract.dte > profile.leapsMaxDte) {
      reasons.add('dte_outside_target_range');
    }
    final delta = contract.delta;
    if (delta == null) {
      reasons.add('delta_unavailable');
    } else if (delta < profile.leapsDeltaMin || delta > profile.leapsDeltaMax) {
      reasons.add('delta_outside_target_range');
    }
    if (contract.bidAskSpreadPct > profile.leapsMaxSpreadPct) {
      reasons.add('bid_ask_spread_above_maximum');
    }
    if (!ignoreOpenInterestFloor &&
        contract.openInterest < profile.leapsMinOpenInterest) {
      reasons.add('open_interest_below_minimum');
    }
    if (budgetRemaining != null &&
        budgetRemaining.currency == contract.strike.currency &&
        contract.mid.amount * Decimal.fromInt(100) > budgetRemaining.amount) {
      reasons.add('leaps_budget_exceeded');
    }
    return reasons;
  }

  OpportunityRiskLevel _risk({
    required Decimal extrinsicRatio,
    required Decimal delta,
    required Decimal spread,
    required OptionsStrategyProfile profile,
  }) {
    if (extrinsicRatio > Decimal.parse('0.40') ||
        spread > profile.leapsMaxSpreadPct) {
      return OpportunityRiskLevel.elevated;
    }
    if (delta >= Decimal.parse('0.75') &&
        extrinsicRatio <= Decimal.parse('0.15')) {
      return OpportunityRiskLevel.low;
    }
    return OpportunityRiskLevel.moderate;
  }

  OpportunityExplanation _explanation({
    required OptionContract contract,
    required LeapsOpportunityMetrics metrics,
    required Decimal delta,
    required Decimal score,
  }) {
    final strike = texts.money(contract.strike);
    final cost = texts.money(metrics.totalCost);
    final deltaLabel = delta.toStringAsFixed(2);
    final whyGood = <String>[
      if (metrics.annualizedExtrinsicCostPct case final costPct?)
        texts.leapsCostBullet(texts.percent(costPct)),
      if (metrics.leverageRatio case final leverage?)
        texts.leapsLeverageBullet(leverage.toStringAsFixed(1), deltaLabel),
      texts.leapsIntrinsicBullet(
        texts.percent(Decimal.one - metrics.extrinsicRatio),
      ),
      if (metrics.fundingCoveragePct case final coverage?
          when coverage >= Decimal.one)
        texts.leapsFundingBullet(texts.percent(coverage)),
    ];
    final whyRisky = <String>[
      texts.leapsThetaBullet(texts.money(metrics.extrinsicValue)),
      if (contract.bidAskSpreadPct > Decimal.parse('0.04'))
        texts.leapsSpreadBullet(texts.percent(contract.bidAskSpreadPct)),
      if (metrics.fundingCoveragePct case final coverage?
          when coverage < Decimal.one)
        texts.leapsFundingBullet(texts.percent(coverage)),
    ];
    return OpportunityExplanation(
      summary: texts.leapsSummary(
        contract.underlying,
        contract.dte,
        strike,
        cost,
        deltaLabel,
      ),
      whyGood: whyGood,
      whyRisky: whyRisky,
      bestFor: texts.leapsBestFor(),
      avoidIf: texts.leapsAvoid(),
      worstCase: texts.leapsWorstCase(contract.underlying, strike, cost),
      scoreBreakdown: {'cost_efficiency': score},
    );
  }
}

Decimal _max(Decimal a, Decimal b) => a > b ? a : b;

Decimal _ratio(Decimal numerator, Decimal denominator) =>
    denominator == Decimal.zero
    ? Decimal.zero
    : (numerator / denominator).toDecimal(scaleOnInfinitePrecision: 8);

Decimal _clamp01(Decimal value) => value < Decimal.zero
    ? Decimal.zero
    : value > Decimal.one
    ? Decimal.one
    : value;
