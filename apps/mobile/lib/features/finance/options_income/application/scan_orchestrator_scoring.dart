part of 'scan_orchestrator.dart';

_PerSymbolResult _scoreSnapshot({
  required OpportunityScorer scorer,
  required OptionsChainSnapshot snapshot,
  required ApprovedUnderlying ap,
  required ScanInputs inputs,
  required DateTime now,
}) {
  final symbol = ap.symbol.toUpperCase();
  final shares = inputs.holdingsBySymbol[symbol] ?? 0;
  final exposure = inputs.exposureBySymbol[symbol];
  final hasEarnings = inputs.upcomingEarningsSymbols.contains(symbol);
  final hasMacro = inputs.upcomingMacroEvent;
  final ignoreOpenInterestFloor = _openInterestUnavailable(snapshot);
  final opps = <OptionsOpportunity>[];
  final rejs = <RejectedCandidate>[];
  for (final contract in snapshot.contracts) {
    final OptionsStrategyKind strategy;
    switch (contract.type) {
      case OptionType.put:
        if (!ap.allowPut ||
            !inputs.profile.allowedStrategies.contains(
              OptionsStrategyKind.cashSecuredPut,
            )) {
          continue;
        }
        strategy = OptionsStrategyKind.cashSecuredPut;
        break;
      case OptionType.call:
        if (!ap.allowCall ||
            !inputs.profile.allowedStrategies.contains(
              OptionsStrategyKind.coveredCall,
            )) {
          continue;
        }
        strategy = OptionsStrategyKind.coveredCall;
        break;
    }
    final scored = scorer.scoreOne(
      contract: contract,
      strategy: strategy,
      profile: inputs.profile,
      approved: ap,
      sharesOwned: shares,
      availableCash: inputs.availableCash,
      currentUnderlyingExposurePct: exposure,
      ignoreOpenInterestFloor: ignoreOpenInterestFloor,
      hasUpcomingEarnings: hasEarnings,
      hasUpcomingMacroEvent: hasMacro,
      eventDataAvailable: inputs.eventDataAvailable,
      now: now,
    );
    if (scored != null) {
      opps.add(scored.opportunity);
    } else {
      final rejection = scorer.filter(
        contract: contract,
        strategy: strategy,
        profile: inputs.profile,
        approved: ap,
        sharesOwned: shares,
        availableCash: inputs.availableCash,
        currentUnderlyingExposurePct: exposure,
        ignoreOpenInterestFloor: ignoreOpenInterestFloor,
        hasUpcomingEarnings: hasEarnings,
        hasUpcomingMacroEvent: hasMacro,
        eventDataAvailable: inputs.eventDataAvailable,
      );
      if (rejection != null) rejs.add(rejection);
    }
  }
  // Keep the top N per (strategy, expiration) tuple so the UI shows variety
  // instead of dozens of near-duplicate strikes.
  final topPerBucket = _topPerBucket(opps);
  return _PerSymbolResult(opportunities: topPerBucket, rejected: rejs);
}

/// Within each `(strategy, expiration)` bucket, keep at most 2 strikes: the
/// highest-scoring one and the most conservative one (highest safety margin).
List<OptionsOpportunity> _topPerBucket(List<OptionsOpportunity> opps) {
  final buckets = <String, List<OptionsOpportunity>>{};
  for (final opp in opps) {
    final key =
        '${opp.strategy.wire}|${opp.contract.expiration.toIso8601String()}';
    buckets.putIfAbsent(key, () => []).add(opp);
  }
  final out = <OptionsOpportunity>[];
  buckets.forEach((_, list) {
    list.sort((a, b) => b.score.compareTo(a.score));
    final best = list.first;
    out.add(best);
    // Most conservative = highest margin of safety, distinct from best.
    OptionsOpportunity? safest;
    Decimal safestMargin = Decimal.zero;
    for (final o in list.skip(1)) {
      if (o.metrics case final OpportunityMetrics m
          when m.marginOfSafety > safestMargin) {
        safest = o;
        safestMargin = m.marginOfSafety;
      }
    }
    if (safest != null) out.add(safest);
  });
  return out;
}
