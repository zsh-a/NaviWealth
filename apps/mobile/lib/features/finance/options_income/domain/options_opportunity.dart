import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/domain/fx/money.dart';

import 'opportunity_explanation.dart';
import 'option_contract.dart';
import 'options_strategy_profile.dart';

/// Which scan lane produced an opportunity.
///
/// Distinct from [OptionsStrategyKind] on purpose: the trade journal only
/// ever records sell-side legs, while the scanner also surfaces buy-side
/// LEAPS candidates. Keeping the enums separate stops `leaps_call` from
/// leaking into journal forms and ledger mirrors.
enum OpportunityStrategy { cashSecuredPut, coveredCall, leapsCall }

extension OpportunityStrategyWire on OpportunityStrategy {
  String get wire => switch (this) {
    OpportunityStrategy.cashSecuredPut => 'cash_secured_put',
    OpportunityStrategy.coveredCall => 'covered_call',
    OpportunityStrategy.leapsCall => 'leaps_call',
  };

  /// Sell-side journal kind, or null for buy-side lanes.
  OptionsStrategyKind? get sellSideKind => switch (this) {
    OpportunityStrategy.cashSecuredPut => OptionsStrategyKind.cashSecuredPut,
    OpportunityStrategy.coveredCall => OptionsStrategyKind.coveredCall,
    OpportunityStrategy.leapsCall => null,
  };
}

OpportunityStrategy opportunityStrategyFromSellSide(OptionsStrategyKind kind) =>
    switch (kind) {
      OptionsStrategyKind.cashSecuredPut => OpportunityStrategy.cashSecuredPut,
      OptionsStrategyKind.coveredCall => OpportunityStrategy.coveredCall,
    };

OpportunityStrategy? parseOpportunityStrategy(String wire) {
  switch (wire) {
    case 'cash_secured_put':
      return OpportunityStrategy.cashSecuredPut;
    case 'covered_call':
      return OpportunityStrategy.coveredCall;
    case 'leaps_call':
      return OpportunityStrategy.leapsCall;
  }
  return null;
}

/// A fully-scored opportunity. Decimal/Money throughout; the cache
/// table persists this in a denormalised form (one row per opportunity).
class OptionsOpportunity {
  const OptionsOpportunity({
    required this.strategy,
    required this.contract,
    required this.metrics,
    required this.risk,
    required this.explanation,
    required this.score,
    required this.scannedAt,
    required this.scanId,
  });

  final OpportunityStrategy strategy;
  final OptionContract contract;
  final OpportunityMetricsBase metrics;
  final OpportunityRiskLevel risk;
  final OpportunityExplanation explanation;

  /// Composite soft score in [0, 1]. Higher is more attractive. For the
  /// LEAPS lane this is a normalized cost-efficiency rank, not a yield
  /// score — lanes are only sorted within themselves.
  final Decimal score;

  final DateTime scannedAt;
  final String scanId;
}

/// Headline numbers a card surface renders. Sealed because sell-side
/// (income received) and buy-side LEAPS (premium paid) opportunities have
/// disjoint economics — shoehorning one into the other's field names
/// would mislead both the UI and the AI contract.
sealed class OpportunityMetricsBase {
  const OpportunityMetricsBase();
}

/// Sell-side (cash-secured put / covered call) derived numbers.
class OpportunityMetrics extends OpportunityMetricsBase {
  const OpportunityMetrics({
    required this.premium,
    required this.cashRequired,
    required this.breakeven,
    required this.staticReturn,
    required this.annualizedYield,
    required this.marginOfSafety,
  });

  /// Mid-price * 100. The credit the user would collect per contract.
  final Money premium;

  /// `strike * 100` (puts) — collateral the user must hold.
  /// For calls, this represents the **assigned-cost basis** the shares
  /// would unwind at (`strike * 100`), used for risk display only.
  final Money cashRequired;

  /// `strike - premium/100` for puts; `strike + premium/100` for calls.
  final Money breakeven;

  /// `premium / cashRequired` — return assuming the option expires
  /// worthless and the position is closed at zero.
  final Decimal staticReturn;

  /// `staticReturn * (365 / dte)` — annualised view.
  final Decimal annualizedYield;

  /// Distance from underlying price to breakeven (puts) or strike
  /// (calls), expressed as a fraction of underlying price. Positive
  /// values indicate cushion.
  final Decimal marginOfSafety;
}

/// Buy-side LEAPS call derived numbers.
class LeapsOpportunityMetrics extends OpportunityMetricsBase {
  const LeapsOpportunityMetrics({
    required this.totalCost,
    required this.breakeven,
    required this.extrinsicValue,
    required this.extrinsicRatio,
    required this.leverageRatio,
    required this.annualizedExtrinsicCostPct,
    this.fundingCoveragePct,
  });

  /// Mid-price * 100 — the debit paid per contract; also the maximum loss.
  final Money totalCost;

  /// `strike + mid` — underlying price at expiration where the position
  /// breaks even.
  final Money breakeven;

  /// `totalCost - intrinsic` — the time value paid on top of intrinsic.
  final Money extrinsicValue;

  /// `extrinsic / totalCost` (0..1). Lower means more of the premium is
  /// real intrinsic value.
  final Decimal extrinsicRatio;

  /// `spot * delta * 100 / totalCost` — share-equivalent exposure per
  /// unit of capital. Null when delta is unavailable.
  final Decimal? leverageRatio;

  /// The headline ranking metric: annualized time-value cost per unit of
  /// delta-equivalent exposure — "the yearly rent paid for each share of
  /// exposure", as a 0..1 fraction. Null when delta is unavailable.
  final Decimal? annualizedExtrinsicCostPct;

  /// How much of this contract's cost the strategy group's realized
  /// income (wheel + dividends) already covers, as a 0..1+ fraction.
  /// Null when the underlying has no group funding context.
  final Decimal? fundingCoveragePct;
}

enum OpportunityRiskLevel { low, moderate, elevated }

extension OpportunityRiskLevelWire on OpportunityRiskLevel {
  String get wire => switch (this) {
    OpportunityRiskLevel.low => 'low',
    OpportunityRiskLevel.moderate => 'moderate',
    OpportunityRiskLevel.elevated => 'elevated',
  };
}

OpportunityRiskLevel parseOpportunityRiskLevel(String wire) {
  switch (wire) {
    case 'low':
      return OpportunityRiskLevel.low;
    case 'moderate':
      return OpportunityRiskLevel.moderate;
    case 'elevated':
      return OpportunityRiskLevel.elevated;
  }
  return OpportunityRiskLevel.moderate;
}

/// Why a candidate was rejected by the hard-filter pass.
class RejectedCandidate {
  const RejectedCandidate({
    required this.optionSymbol,
    required this.reasons,
    this.strategy,
  });

  final String optionSymbol;
  final List<String> reasons;

  /// Which scan lane rejected the candidate. Lets the UI scope "why is
  /// this filter empty?" summaries to the selected lane.
  final OpportunityStrategy? strategy;
}
