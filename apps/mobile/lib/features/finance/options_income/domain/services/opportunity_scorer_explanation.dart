part of 'opportunity_scorer.dart';

OpportunityExplanation _explanation({
  required OptionContract contract,
  required OptionsStrategyKind strategy,
  required OptionsStrategyProfile profile,
  required Map<String, Decimal> breakdown,
  required OpportunityMetrics metrics,
  required bool eventDataAvailable,
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
        eventDataAvailable: eventDataAvailable,
      ),
    );
  }
  final summary = _summary(
    strategy: strategy,
    contract: contract,
    metrics: metrics,
  );
  final bestFor = _bestForLine(strategy, profile.mode);
  final avoidIf = _avoidIfLine(strategy);
  final worstCase = _worstCase(strategy, contract, metrics);
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
  OptionContract contract, {
  required bool eventDataAvailable,
}) {
  final pct = _pct(entry.value);
  switch (entry.key) {
    case 'yield':
      return 'Annualized yield ${_pct(metrics.annualizedYield)} (score $pct)';
    case 'liquidity':
      return 'Good liquidity: bid/ask spread '
          '${_pct(contract.bidAskSpreadPct)}, open interest '
          '${contract.openInterest} (score $pct)';
    case 'safety_margin':
      return 'Margin of safety ${_pct(metrics.marginOfSafety)} from '
          'breakeven (score $pct)';
    case 'iv':
      return 'Implied volatility '
          '${contract.impliedVolatility == null ? "unknown" : _pct(contract.impliedVolatility!)} '
          'is in a resilient range (score $pct)';
    case 'portfolio_fit':
      return 'Fits current positions (score $pct)';
    case 'event_safety':
      if (!eventDataAvailable) {
        return 'Event calendar unavailable; event risk is not scored';
      }
      return 'No earnings or macro event in the next 7 days (score $pct)';
    default:
      return '${entry.key} score $pct';
  }
}

String _weaknessBullet(
  MapEntry<String, Decimal> entry,
  OpportunityMetrics metrics,
  OptionContract contract, {
  required bool eventDataAvailable,
}) {
  final pct = _pct(entry.value);
  switch (entry.key) {
    case 'yield':
      return 'Lower annualized yield: ${_pct(metrics.annualizedYield)} '
          '(score $pct)';
    case 'liquidity':
      return 'Moderate liquidity: bid/ask spread '
          '${_pct(contract.bidAskSpreadPct)} (score $pct)';
    case 'safety_margin':
      return 'Limited margin of safety: ${_pct(metrics.marginOfSafety)} '
          '(score $pct)';
    case 'iv':
      return 'Implied volatility is outside the normal range (score $pct)';
    case 'portfolio_fit':
      return 'Only a moderate fit with current positions (score $pct)';
    case 'event_safety':
      if (!eventDataAvailable) {
        return 'Check earnings and macro dates before placing the trade';
      }
      return 'Execution needs caution inside the event window (score $pct)';
    default:
      return '${entry.key} score $pct';
  }
}

String _summary({
  required OptionsStrategyKind strategy,
  required OptionContract contract,
  required OpportunityMetrics metrics,
}) {
  final action = strategy == OptionsStrategyKind.cashSecuredPut
      ? 'sell put'
      : 'covered call';
  return '${contract.underlying} ${contract.dte}DTE $action @ '
      '${_fmt(contract.strike)} — annualized '
      '${_pct(metrics.annualizedYield)}, margin of safety '
      '${_pct(metrics.marginOfSafety)}';
}

String _bestForLine(OptionsStrategyKind strategy, OptionsStrategyMode mode) {
  switch (strategy) {
    case OptionsStrategyKind.cashSecuredPut:
      switch (mode) {
        case OptionsStrategyMode.conservative:
          return 'Best for conservative cash-flow preference: higher margin '
              'of safety and liquidity first.';
        case OptionsStrategyMode.balanced:
        case OptionsStrategyMode.custom:
          return 'Best for balanced cash-flow preference: balances yield '
              'against downside risk.';
        case OptionsStrategyMode.aggressive:
          return 'Best when you accept higher assignment probability in '
              'exchange for annualized yield.';
      }
    case OptionsStrategyKind.coveredCall:
      switch (mode) {
        case OptionsStrategyMode.conservative:
          return 'Best for conservative enhancement: sell farther OTM calls '
              'with lower assignment probability.';
        case OptionsStrategyMode.balanced:
        case OptionsStrategyMode.custom:
          return 'Best for balanced enhancement: add income without '
              'materially disrupting the position.';
        case OptionsStrategyMode.aggressive:
          return 'Best when you are willing to accept assignment to realize '
              'gains.';
      }
  }
}

String _avoidIfLine(OptionsStrategyKind strategy) {
  switch (strategy) {
    case OptionsStrategyKind.cashSecuredPut:
      return 'Avoid if you are not willing to buy 100 shares at the strike '
          'when assigned.';
    case OptionsStrategyKind.coveredCall:
      return 'Avoid if you are not willing to sell 100 shares at the strike.';
  }
}

String _worstCase(
  OptionsStrategyKind strategy,
  OptionContract contract,
  OpportunityMetrics metrics,
) {
  switch (strategy) {
    case OptionsStrategyKind.cashSecuredPut:
      return 'If ${contract.underlying} falls below '
          '${_fmt(contract.strike)}, you would buy 100 shares at an '
          'effective cost of ${_fmt(metrics.breakeven)}, using '
          '${_fmt(metrics.cashRequired)} cash.';
    case OptionsStrategyKind.coveredCall:
      final cap = contract.strike.amount + contract.mid.amount;
      final capMoney = Money(cap, contract.strike.currency);
      return 'If ${contract.underlying} rises to '
          '${_fmt(contract.strike)}, you would sell 100 shares at '
          '${_fmt(contract.strike)} and miss upside above that level; '
          'total proceeds are capped at ${_fmt(capMoney)}.';
  }
}

String _pct(Decimal value) {
  final hundred = (value * Decimal.fromInt(100)).toStringAsFixed(1);
  return '$hundred%';
}

String _fmt(Money money) {
  return NumberFormat.currency(
    locale: 'en',
    name: money.currency,
    symbol: '${money.currency} ',
    decimalDigits: 2,
  ).format(money.amount.toDouble());
}
