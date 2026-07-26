part of 'opportunity_scorer.dart';

List<String> _hardFilter({
  required OptionContract contract,
  required OptionsStrategyKind strategy,
  required OptionsStrategyProfile profile,
  required ApprovedUnderlying? approved,
  required int sharesOwned,
  required Money availableCash,
  required bool ignoreOpenInterestFloor,
  required bool hasUpcomingEarnings,
  required bool hasUpcomingMacroEvent,
  required bool eventDataAvailable,
}) {
  final reasons = <String>[];
  if (!ignoreOpenInterestFloor &&
      contract.openInterest < profile.minOpenInterest) {
    reasons.add('open_interest_below_floor');
  }
  if (contract.volume < profile.minVolume) reasons.add('volume_below_floor');
  final hasBidAskQuote =
      contract.bid.amount > Decimal.zero && contract.ask.amount > Decimal.zero;
  if (hasBidAskQuote && contract.bidAskSpreadPct > profile.maxBidAskSpreadPct) {
    reasons.add('bid_ask_spread_too_wide');
  }
  if (contract.dte < profile.minDte || contract.dte > profile.maxDte) {
    reasons.add('dte_out_of_window');
  }

  // Strategy-level invariants.
  switch (strategy) {
    case OptionsStrategyKind.cashSecuredPut:
      if (contract.type != OptionType.put) {
        reasons.add('contract_type_mismatch');
      }
      if (approved == null || !approved.allowPut) {
        reasons.add('underlying_not_approved_for_put');
      }
      final cashRequired = _putCashRequired(contract);
      final cashCurrencyMatches =
          availableCash.currency == cashRequired.currency;
      if (!cashCurrencyMatches) {
        reasons.add('available_cash_currency_mismatch');
      }
      final cap = cashCurrencyMatches
          ? availableCash.amount * profile.maxCapitalPerTradePct
          : Decimal.zero;
      if (cashRequired.amount > cap) {
        reasons.add('cash_required_above_cap');
      }
      if (approved?.maxBuyPrice != null &&
          contract.strike.amount > approved!.maxBuyPrice!) {
        reasons.add('strike_above_user_max_buy_price');
      }
      break;
    case OptionsStrategyKind.coveredCall:
      if (contract.type != OptionType.call) {
        reasons.add('contract_type_mismatch');
      }
      if (sharesOwned < 100) reasons.add('insufficient_shares');
      if (approved == null || !approved.allowCall) {
        reasons.add('underlying_not_approved_for_call');
      }
      if (approved?.minSellPrice != null &&
          contract.strike.amount < approved!.minSellPrice!) {
        reasons.add('strike_below_user_min_sell_price');
      }
      break;
  }

  // Delta hard-filter only when the chain has greeks. yfinance omits
  // them; the scorer falls back to delta-equivalent moneyness checks
  // inside the soft score and does NOT reject for missing delta.
  final delta = contract.delta;
  if (delta != null) {
    switch (strategy) {
      case OptionsStrategyKind.cashSecuredPut:
        if (delta < profile.deltaPutMin || delta > profile.deltaPutMax) {
          reasons.add('delta_out_of_band');
        }
        break;
      case OptionsStrategyKind.coveredCall:
        if (delta < profile.deltaCallMin || delta > profile.deltaCallMax) {
          reasons.add('delta_out_of_band');
        }
        break;
    }
  }

  if (eventDataAvailable && profile.avoidEarnings && hasUpcomingEarnings) {
    reasons.add('earnings_window');
  }
  if (eventDataAvailable && profile.avoidMacroEvents && hasUpcomingMacroEvent) {
    reasons.add('macro_event_window');
  }

  // Annualized yield floor — derive directly so the rejection captures
  // the actual metric the user sees on screen.
  final metrics = _metrics(contract: contract, strategy: strategy);
  if (metrics.annualizedYield < profile.minAnnualizedYield) {
    reasons.add('annualized_yield_below_floor');
  }

  return reasons;
}

Money _putCashRequired(OptionContract contract) => Money(
  contract.strike.amount * Decimal.fromInt(100),
  contract.strike.currency,
);
