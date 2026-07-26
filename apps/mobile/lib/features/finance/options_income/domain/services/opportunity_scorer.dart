import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/domain/fx/money.dart';
import '../approved_underlying.dart';
import '../opportunity_explanation.dart';
import '../option_contract.dart';
import '../options_opportunity.dart';
import '../options_strategy_profile.dart';
import 'opportunity_explanation_texts.dart';

part 'opportunity_scorer_explanation.dart';
part 'opportunity_scorer_filters.dart';
part 'opportunity_scorer_metrics.dart';
part 'opportunity_scorer_scoring.dart';

/// Pure-Dart scorer for `OptionContract → OptionsOpportunity`.
///
/// Form: nilpotent, no IO, replayable. Mirrors the shape of the FIRE engine
/// in `lib/features/finance/fire/domain/`. Hard filters reject; the soft score is a
/// weighted linear combination of normalised sub-scores per
/// `docs/domains/options-income.md` §7.
class OpportunityScorer {
  const OpportunityScorer({
    this.weights = const ScoringWeights(),
    this.texts = const DefaultOpportunityExplanationTexts(),
  });

  final ScoringWeights weights;

  /// Locale-aware leaf strings for the generated explanation. Production
  /// wiring injects an `AppLocalizations`-backed implementation so cached
  /// explanations follow the user's language.
  final OpportunityExplanationTexts texts;

  /// Score one [contract] against the user profile + approved-list entry.
  /// Returns `null` when any hard filter rejects the candidate; the caller
  /// can capture the [RejectedCandidate] separately via [filter].
  ScoredCandidate? scoreOne({
    required OptionContract contract,
    required OptionsStrategyKind strategy,
    required OptionsStrategyProfile profile,
    required ApprovedUnderlying? approved,
    required int sharesOwned,
    required Money availableCash,
    Decimal? currentUnderlyingExposurePct,
    bool ignoreOpenInterestFloor = false,
    bool hasUpcomingEarnings = false,
    bool hasUpcomingMacroEvent = false,
    bool eventDataAvailable = false,
    DateTime? now,
  }) {
    final asOf = now ?? DateTime.now().toUtc();
    final scanId = '${asOf.toUtc().toIso8601String()}-${contract.optionSymbol}';
    final rejection = _hardFilter(
      contract: contract,
      strategy: strategy,
      profile: profile,
      approved: approved,
      sharesOwned: sharesOwned,
      availableCash: availableCash,
      ignoreOpenInterestFloor: ignoreOpenInterestFloor,
      hasUpcomingEarnings: hasUpcomingEarnings,
      hasUpcomingMacroEvent: hasUpcomingMacroEvent,
      eventDataAvailable: eventDataAvailable,
    );
    if (rejection.isNotEmpty) {
      return null;
    }
    final breakdown = _softScore(
      contract: contract,
      strategy: strategy,
      profile: profile,
      maxPositionWeight: approved?.maxPositionWeight,
      currentUnderlyingExposurePct: currentUnderlyingExposurePct,
      hasUpcomingEarnings: hasUpcomingEarnings,
      hasUpcomingMacroEvent: hasUpcomingMacroEvent,
      eventDataAvailable: eventDataAvailable,
    );
    final composite = _composite(breakdown, weights);
    final metrics = _metrics(contract: contract, strategy: strategy);
    final explanation = _explanation(
      contract: contract,
      strategy: strategy,
      profile: profile,
      breakdown: breakdown,
      metrics: metrics,
      eventDataAvailable: eventDataAvailable,
      texts: texts,
    );
    final risk = _classifyRisk(metrics, breakdown);
    return ScoredCandidate(
      opportunity: OptionsOpportunity(
        strategy: opportunityStrategyFromSellSide(strategy),
        contract: contract,
        metrics: metrics,
        risk: risk,
        explanation: explanation,
        score: composite,
        scannedAt: asOf,
        scanId: scanId,
      ),
    );
  }

  /// Convenience overload that emits a [RejectedCandidate] when hard
  /// filters fail. Useful for diagnostics and the future
  /// `whyRejected` debug view.
  RejectedCandidate? filter({
    required OptionContract contract,
    required OptionsStrategyKind strategy,
    required OptionsStrategyProfile profile,
    required ApprovedUnderlying? approved,
    required int sharesOwned,
    required Money availableCash,
    Decimal? currentUnderlyingExposurePct,
    bool ignoreOpenInterestFloor = false,
    bool hasUpcomingEarnings = false,
    bool hasUpcomingMacroEvent = false,
    bool eventDataAvailable = false,
  }) {
    final reasons = _hardFilter(
      contract: contract,
      strategy: strategy,
      profile: profile,
      approved: approved,
      sharesOwned: sharesOwned,
      availableCash: availableCash,
      ignoreOpenInterestFloor: ignoreOpenInterestFloor,
      hasUpcomingEarnings: hasUpcomingEarnings,
      hasUpcomingMacroEvent: hasUpcomingMacroEvent,
      eventDataAvailable: eventDataAvailable,
    );
    if (reasons.isEmpty) return null;
    return RejectedCandidate(
      optionSymbol: contract.optionSymbol,
      reasons: reasons,
      strategy: opportunityStrategyFromSellSide(strategy),
    );
  }
}

/// One scored candidate; the orchestrator collects these and persists them
/// to the cache table in a single transaction.
class ScoredCandidate {
  const ScoredCandidate({required this.opportunity});

  final OptionsOpportunity opportunity;
}

/// Weights for the soft-score linear combination. Default mirrors the
/// design doc §7.2.
///
/// Weights are stored as strings so the constructor stays `const`; the
/// scorer resolves them to [Decimal] on demand via [forDimension].
class ScoringWeights {
  const ScoringWeights({
    this.yieldWeight = '0.25',
    this.liquidityWeight = '0.20',
    this.safetyMarginWeight = '0.20',
    this.ivWeight = '0.15',
    this.portfolioFitWeight = '0.10',
    this.eventSafetyWeight = '0.10',
  });

  final String yieldWeight;
  final String liquidityWeight;
  final String safetyMarginWeight;
  final String ivWeight;
  final String portfolioFitWeight;
  final String eventSafetyWeight;

  Decimal forDimension(String key) {
    switch (key) {
      case 'yield':
        return Decimal.parse(yieldWeight);
      case 'liquidity':
        return Decimal.parse(liquidityWeight);
      case 'safety_margin':
        return Decimal.parse(safetyMarginWeight);
      case 'iv':
        return Decimal.parse(ivWeight);
      case 'portfolio_fit':
        return Decimal.parse(portfolioFitWeight);
      case 'event_safety':
        return Decimal.parse(eventSafetyWeight);
    }
    return Decimal.zero;
  }
}
