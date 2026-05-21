import 'package:decimal/decimal.dart';

import '../../../domain/values/money.dart';
import 'opportunity_explanation.dart';
import 'option_contract.dart';
import 'options_strategy_profile.dart';

/// A fully-scored income opportunity. Decimal/Money throughout; the cache
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

  final OptionsStrategyKind strategy;
  final OptionContract contract;
  final OpportunityMetrics metrics;
  final OpportunityRiskLevel risk;
  final OpportunityExplanation explanation;

  /// Composite soft score in [0, 1]. Higher is more attractive.
  final Decimal score;

  final DateTime scannedAt;
  final String scanId;
}

/// Derived headline numbers a card surface renders.
class OpportunityMetrics {
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
  });

  final String optionSymbol;
  final List<String> reasons;
}
