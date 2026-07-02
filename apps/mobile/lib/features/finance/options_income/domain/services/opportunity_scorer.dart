import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

import 'package:naviwealth/domain/values/money.dart';
import '../approved_underlying.dart';
import '../opportunity_explanation.dart';
import '../option_contract.dart';
import '../options_opportunity.dart';
import '../options_strategy_profile.dart';

/// Pure-Dart scorer for `OptionContract → OptionsOpportunity`.
///
/// Form: nilpotent, no IO, replayable. Mirrors the shape of the FIRE engine
/// in `lib/features/fire/domain/`. Hard filters reject; the soft score is a
/// weighted linear combination of normalised sub-scores per
/// `docs/domains/options-income.md` §7.
class OpportunityScorer {
  const OpportunityScorer({this.weights = const ScoringWeights()});

  final ScoringWeights weights;

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
    );
    if (rejection.isNotEmpty) {
      return null;
    }
    final breakdown = _softScore(
      contract: contract,
      strategy: strategy,
      profile: profile,
      currentUnderlyingExposurePct: currentUnderlyingExposurePct,
      hasUpcomingEarnings: hasUpcomingEarnings,
      hasUpcomingMacroEvent: hasUpcomingMacroEvent,
    );
    final composite = _composite(breakdown);
    final metrics = _metrics(contract: contract, strategy: strategy);
    final explanation = _explanation(
      contract: contract,
      strategy: strategy,
      profile: profile,
      breakdown: breakdown,
      metrics: metrics,
    );
    final risk = _classifyRisk(metrics, breakdown);
    return ScoredCandidate(
      opportunity: OptionsOpportunity(
        strategy: strategy,
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
    );
    if (reasons.isEmpty) return null;
    return RejectedCandidate(
      optionSymbol: contract.optionSymbol,
      reasons: reasons,
    );
  }

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
  }) {
    final reasons = <String>[];
    if (!ignoreOpenInterestFloor &&
        contract.openInterest < profile.minOpenInterest) {
      reasons.add('open_interest_below_floor');
    }
    if (contract.volume < profile.minVolume) reasons.add('volume_below_floor');
    final hasBidAskQuote =
        contract.bid.amount > Decimal.zero &&
        contract.ask.amount > Decimal.zero;
    if (hasBidAskQuote &&
        contract.bidAskSpreadPct > profile.maxBidAskSpreadPct) {
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
        if (profile.onlyOnApprovedUnderlyings &&
            (approved == null || !approved.allowPut)) {
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
        if (profile.onlyOnApprovedUnderlyings &&
            (approved == null || !approved.allowCall)) {
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

    if (profile.avoidEarnings && hasUpcomingEarnings) {
      reasons.add('earnings_window');
    }
    if (profile.avoidMacroEvents && hasUpcomingMacroEvent) {
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

  Map<String, Decimal> _softScore({
    required OptionContract contract,
    required OptionsStrategyKind strategy,
    required OptionsStrategyProfile profile,
    required Decimal? currentUnderlyingExposurePct,
    required bool hasUpcomingEarnings,
    required bool hasUpcomingMacroEvent,
  }) {
    final metrics = _metrics(contract: contract, strategy: strategy);

    // yield score: how far the annualized yield is above the floor, with
    // diminishing returns past 2× the floor.
    final yieldScore = _saturate(
      base: metrics.annualizedYield,
      floor: profile.minAnnualizedYield,
      ceiling: profile.minAnnualizedYield * Decimal.fromInt(3),
    );

    // liquidity score: spread % is bad, OI/volume is good — combine.
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

    // safety margin score: cushion between underlying and strike,
    // strategy-aware.
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

    final eventSafetyScore = (hasUpcomingEarnings || hasUpcomingMacroEvent)
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

  Decimal _composite(Map<String, Decimal> breakdown) {
    Decimal acc = Decimal.zero;
    breakdown.forEach((dim, value) {
      acc = acc + value * weights.forDimension(dim);
    });
    return acc.clamp(Decimal.zero, Decimal.one);
  }

  OpportunityMetrics _metrics({
    required OptionContract contract,
    required OptionsStrategyKind strategy,
  }) {
    final currency = contract.strike.currency;
    final hundred = Decimal.fromInt(100);
    final premium = Money(contract.mid.amount * hundred, currency);
    final cashRequired = Money(contract.strike.amount * hundred, currency);
    final perShare = contract.mid.amount;
    final Money breakeven;
    switch (strategy) {
      case OptionsStrategyKind.cashSecuredPut:
        breakeven = Money(contract.strike.amount - perShare, currency);
        break;
      case OptionsStrategyKind.coveredCall:
        breakeven = Money(contract.strike.amount + perShare, currency);
        break;
    }
    final staticReturn = cashRequired.amount <= Decimal.zero
        ? Decimal.zero
        : (premium.amount / cashRequired.amount).toDecimal(
            scaleOnInfinitePrecision: 6,
          );
    final dteRatio = contract.dte <= 0
        ? Decimal.zero
        : (Decimal.fromInt(365) / Decimal.fromInt(contract.dte)).toDecimal(
            scaleOnInfinitePrecision: 6,
          );
    final annualizedYield = staticReturn * dteRatio;
    final marginOfSafety = contract.underlyingPrice.amount <= Decimal.zero
        ? Decimal.zero
        : strategy == OptionsStrategyKind.cashSecuredPut
        ? ((contract.underlyingPrice.amount - breakeven.amount) /
                  contract.underlyingPrice.amount)
              .toDecimal(scaleOnInfinitePrecision: 6)
        : ((contract.strike.amount - contract.underlyingPrice.amount) /
                  contract.underlyingPrice.amount)
              .toDecimal(scaleOnInfinitePrecision: 6);
    return OpportunityMetrics(
      premium: premium,
      cashRequired: cashRequired,
      breakeven: breakeven,
      staticReturn: staticReturn,
      annualizedYield: annualizedYield,
      marginOfSafety: marginOfSafety,
    );
  }

  OpportunityExplanation _explanation({
    required OptionContract contract,
    required OptionsStrategyKind strategy,
    required OptionsStrategyProfile profile,
    required Map<String, Decimal> breakdown,
    required OpportunityMetrics metrics,
  }) {
    final whyGood = <String>[];
    final whyRisky = <String>[];
    final sortedAsc = breakdown.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final top3 = sortedAsc.reversed.take(3).toList();
    final bottom2 = sortedAsc.take(2).toList();
    for (final entry in top3) {
      whyGood.add(_strengthBullet(entry, metrics, contract));
    }
    for (final entry in bottom2) {
      whyRisky.add(_weaknessBullet(entry, metrics, contract));
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

  // ---------- helpers ----------

  Money _putCashRequired(OptionContract contract) => Money(
    contract.strike.amount * Decimal.fromInt(100),
    contract.strike.currency,
  );

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

  String _strengthBullet(
    MapEntry<String, Decimal> entry,
    OpportunityMetrics metrics,
    OptionContract contract,
  ) {
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
        return 'No earnings or macro event in the next 7 days (score $pct)';
      default:
        return '${entry.key} score $pct';
    }
  }

  String _weaknessBullet(
    MapEntry<String, Decimal> entry,
    OpportunityMetrics metrics,
    OptionContract contract,
  ) {
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
