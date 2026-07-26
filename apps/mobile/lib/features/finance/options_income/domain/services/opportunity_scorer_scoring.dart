part of 'opportunity_scorer.dart';

Map<String, Decimal> _softScore({
  required OptionContract contract,
  required OptionsStrategyKind strategy,
  required OptionsStrategyProfile profile,
  required Decimal? currentUnderlyingExposurePct,
  required bool hasUpcomingEarnings,
  required bool hasUpcomingMacroEvent,
  required bool eventDataAvailable,
}) {
  final metrics = _metrics(contract: contract, strategy: strategy);

  // Yield score: how far the annualized yield is above the floor, with
  // diminishing returns past 2x the floor.
  final yieldScore = _saturate(
    base: metrics.annualizedYield,
    floor: profile.minAnnualizedYield,
    ceiling: profile.minAnnualizedYield * Decimal.fromInt(3),
  );

  // Liquidity score: spread % is bad, OI/volume is good; combine.
  final spreadScore = Decimal.one - contract.bidAskSpreadPct;
  final oiScore = _saturate(
    base: Decimal.fromInt(contract.openInterest),
    floor: Decimal.fromInt(profile.minOpenInterest),
    ceiling: Decimal.fromInt(profile.minOpenInterest * 5),
  );
  final volScore = _saturate(
    base: Decimal.fromInt(contract.volume),
    floor: Decimal.fromInt(profile.minVolume),
    ceiling: Decimal.fromInt(profile.minVolume * 5),
  );
  final liquidityScore = _avg([spreadScore, oiScore, volScore]);

  final safetyScore = _saturate(
    base: metrics.marginOfSafety,
    floor: Decimal.zero,
    ceiling: Decimal.parse('0.15'),
  );

  // IV score: moderate IV is best. >100% IV is "too hot"; <20% is
  // "too cold". Centre at 30%.
  final iv = contract.impliedVolatility;
  Decimal ivScore;
  if (iv == null) {
    ivScore = Decimal.parse('0.5');
  } else {
    final centre = Decimal.parse('0.30');
    final delta = (iv - centre).abs();
    final norm = (delta / Decimal.parse('0.50')).toDecimal(
      scaleOnInfinitePrecision: 4,
    );
    ivScore = (Decimal.one - norm).clamp(Decimal.zero, Decimal.one);
  }

  final portfolioFitScore = _portfolioFitScore(
    currentExposure: currentUnderlyingExposurePct,
    maxExposure: profile.maxUnderlyingExposurePct,
  );

  final eventSafetyScore = !eventDataAvailable
      ? Decimal.parse('0.50')
      : (hasUpcomingEarnings || hasUpcomingMacroEvent)
      ? Decimal.parse('0.20')
      : Decimal.parse('0.95');

  return <String, Decimal>{
    'yield': yieldScore,
    'liquidity': liquidityScore,
    'safety_margin': safetyScore,
    'iv': ivScore,
    'portfolio_fit': portfolioFitScore,
    'event_safety': eventSafetyScore,
  };
}

Decimal _portfolioFitScore({
  required Decimal? currentExposure,
  required Decimal maxExposure,
}) {
  if (currentExposure == null || maxExposure <= Decimal.zero) {
    return Decimal.parse('0.50');
  }
  final halfCap = (maxExposure / Decimal.fromInt(2)).toDecimal(
    scaleOnInfinitePrecision: 4,
  );
  if (currentExposure <= halfCap) return Decimal.one;
  if (currentExposure >= maxExposure) return Decimal.zero;
  return (Decimal.one -
          ((currentExposure - halfCap) / halfCap).toDecimal(
            scaleOnInfinitePrecision: 4,
          ))
      .clamp(Decimal.zero, Decimal.one);
}

Decimal _composite(Map<String, Decimal> breakdown, ScoringWeights weights) {
  Decimal acc = Decimal.zero;
  breakdown.forEach((dim, value) {
    acc = acc + value * weights.forDimension(dim);
  });
  return acc.clamp(Decimal.zero, Decimal.one);
}

OpportunityRiskLevel _classifyRisk(
  OpportunityMetrics metrics,
  Map<String, Decimal> breakdown,
) {
  final safety = breakdown['safety_margin'] ?? Decimal.zero;
  final event = breakdown['event_safety'] ?? Decimal.one;
  if (safety >= Decimal.parse('0.75') && event >= Decimal.parse('0.8')) {
    return OpportunityRiskLevel.low;
  }
  if (safety < Decimal.parse('0.40') || event < Decimal.parse('0.4')) {
    return OpportunityRiskLevel.elevated;
  }
  return OpportunityRiskLevel.moderate;
}

Decimal _saturate({
  required Decimal base,
  required Decimal floor,
  required Decimal ceiling,
}) {
  if (ceiling <= floor) return Decimal.one;
  if (base <= floor) return Decimal.zero;
  if (base >= ceiling) return Decimal.one;
  final fraction = ((base - floor) / (ceiling - floor)).toDecimal(
    scaleOnInfinitePrecision: 4,
  );
  return fraction.clamp(Decimal.zero, Decimal.one);
}

Decimal _avg(List<Decimal> values) {
  if (values.isEmpty) return Decimal.zero;
  final sum = values.fold<Decimal>(Decimal.zero, (a, b) => a + b);
  return (sum / Decimal.fromInt(values.length)).toDecimal(
    scaleOnInfinitePrecision: 4,
  );
}
