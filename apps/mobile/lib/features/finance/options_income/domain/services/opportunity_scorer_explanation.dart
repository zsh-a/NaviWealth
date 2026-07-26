part of 'opportunity_scorer.dart';

OpportunityExplanation _explanation({
  required OptionContract contract,
  required OptionsStrategyKind strategy,
  required OptionsStrategyProfile profile,
  required Map<String, Decimal> breakdown,
  required OpportunityMetrics metrics,
  required bool eventDataAvailable,
  required OpportunityExplanationTexts texts,
}) {
  final whyGood = <String>[];
  final whyRisky = <String>[];
  final sortedAsc = breakdown.entries.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  final top3 = sortedAsc.reversed.take(3).toList();
  final bottom2 = sortedAsc.take(2).toList();
  for (final entry in top3) {
    whyGood.add(
      _strengthBullet(
        entry,
        metrics,
        contract,
        texts,
        eventDataAvailable: eventDataAvailable,
      ),
    );
  }
  for (final entry in bottom2) {
    whyRisky.add(
      _weaknessBullet(
        entry,
        metrics,
        contract,
        texts,
        eventDataAvailable: eventDataAvailable,
      ),
    );
  }
  final summary = _summary(
    strategy: strategy,
    contract: contract,
    metrics: metrics,
    texts: texts,
  );
  final bestFor = _bestForLine(strategy, profile.mode, texts);
  final avoidIf = _avoidIfLine(strategy, texts);
  final worstCase = _worstCase(strategy, contract, metrics, texts);
  return OpportunityExplanation(
    summary: summary,
    whyGood: whyGood,
    whyRisky: whyRisky,
    bestFor: bestFor,
    avoidIf: avoidIf,
    worstCase: worstCase,
    scoreBreakdown: Map<String, Decimal>.from(breakdown),
  );
}

String _strengthBullet(
  MapEntry<String, Decimal> entry,
  OpportunityMetrics metrics,
  OptionContract contract,
  OpportunityExplanationTexts texts, {
  required bool eventDataAvailable,
}) {
  final score = texts.percent(entry.value);
  switch (entry.key) {
    case 'yield':
      return texts.yieldStrength(texts.percent(metrics.annualizedYield), score);
    case 'liquidity':
      return texts.liquidityStrength(
        texts.percent(contract.bidAskSpreadPct),
        contract.openInterest,
        score,
      );
    case 'safety_margin':
      return texts.safetyStrength(texts.percent(metrics.marginOfSafety), score);
    case 'iv':
      return texts.ivStrength(
        contract.impliedVolatility == null
            ? texts.ivUnknown()
            : texts.percent(contract.impliedVolatility!),
        score,
      );
    case 'portfolio_fit':
      return texts.fitStrength(score);
    case 'event_safety':
      if (!eventDataAvailable) {
        return texts.eventUnavailable();
      }
      return texts.eventStrength(score);
    default:
      return texts.genericScore(entry.key, score);
  }
}

String _weaknessBullet(
  MapEntry<String, Decimal> entry,
  OpportunityMetrics metrics,
  OptionContract contract,
  OpportunityExplanationTexts texts, {
  required bool eventDataAvailable,
}) {
  final score = texts.percent(entry.value);
  switch (entry.key) {
    case 'yield':
      return texts.yieldWeak(texts.percent(metrics.annualizedYield), score);
    case 'liquidity':
      return texts.liquidityWeak(
        texts.percent(contract.bidAskSpreadPct),
        score,
      );
    case 'safety_margin':
      return texts.safetyWeak(texts.percent(metrics.marginOfSafety), score);
    case 'iv':
      return texts.ivWeak(score);
    case 'portfolio_fit':
      return texts.fitWeak(score);
    case 'event_safety':
      if (!eventDataAvailable) {
        return texts.eventCheck();
      }
      return texts.eventWeak(score);
    default:
      return texts.genericScore(entry.key, score);
  }
}

String _summary({
  required OptionsStrategyKind strategy,
  required OptionContract contract,
  required OpportunityMetrics metrics,
  required OpportunityExplanationTexts texts,
}) {
  final strike = texts.money(contract.strike);
  final annualized = texts.percent(metrics.annualizedYield);
  final margin = texts.percent(metrics.marginOfSafety);
  return switch (strategy) {
    OptionsStrategyKind.cashSecuredPut => texts.summaryPut(
      contract.underlying,
      contract.dte,
      strike,
      annualized,
      margin,
    ),
    OptionsStrategyKind.coveredCall => texts.summaryCall(
      contract.underlying,
      contract.dte,
      strike,
      annualized,
      margin,
    ),
  };
}

String _bestForLine(
  OptionsStrategyKind strategy,
  OptionsStrategyMode mode,
  OpportunityExplanationTexts texts,
) {
  switch (strategy) {
    case OptionsStrategyKind.cashSecuredPut:
      switch (mode) {
        case OptionsStrategyMode.conservative:
          return texts.bestForPutConservative();
        case OptionsStrategyMode.balanced:
        case OptionsStrategyMode.custom:
          return texts.bestForPutBalanced();
        case OptionsStrategyMode.aggressive:
          return texts.bestForPutAggressive();
      }
    case OptionsStrategyKind.coveredCall:
      switch (mode) {
        case OptionsStrategyMode.conservative:
          return texts.bestForCallConservative();
        case OptionsStrategyMode.balanced:
        case OptionsStrategyMode.custom:
          return texts.bestForCallBalanced();
        case OptionsStrategyMode.aggressive:
          return texts.bestForCallAggressive();
      }
  }
}

String _avoidIfLine(
  OptionsStrategyKind strategy,
  OpportunityExplanationTexts texts,
) {
  switch (strategy) {
    case OptionsStrategyKind.cashSecuredPut:
      return texts.avoidPut();
    case OptionsStrategyKind.coveredCall:
      return texts.avoidCall();
  }
}

String _worstCase(
  OptionsStrategyKind strategy,
  OptionContract contract,
  OpportunityMetrics metrics,
  OpportunityExplanationTexts texts,
) {
  switch (strategy) {
    case OptionsStrategyKind.cashSecuredPut:
      return texts.worstCasePut(
        contract.underlying,
        texts.money(contract.strike),
        texts.money(metrics.breakeven),
        texts.money(metrics.cashRequired),
      );
    case OptionsStrategyKind.coveredCall:
      final cap = contract.strike.amount + contract.mid.amount;
      final capMoney = Money(cap, contract.strike.currency);
      return texts.worstCaseCall(
        contract.underlying,
        texts.money(contract.strike),
        texts.money(capMoney),
      );
  }
}
