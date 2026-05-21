import 'package:decimal/decimal.dart';

import '../../../../domain/values/money.dart';
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
/// `docs/options-income.md` §7.
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
    required bool hasUpcomingEarnings,
    required bool hasUpcomingMacroEvent,
  }) {
    final reasons = <String>[];
    if (contract.bid.amount <= Decimal.zero) reasons.add('bid_not_positive');
    if (contract.openInterest < profile.minOpenInterest) {
      reasons.add('open_interest_below_floor');
    }
    if (contract.volume < profile.minVolume) reasons.add('volume_below_floor');
    if (contract.bidAskSpreadPct > profile.maxBidAskSpreadPct) {
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
        final cap = availableCash.amount * profile.maxCapitalPerTradePct;
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
      final norm = (delta / Decimal.parse('0.50'))
          .toDecimal(scaleOnInfinitePrecision: 4);
      ivScore = (Decimal.one - norm).clamp(Decimal.zero, Decimal.one);
    }

    // Portfolio-fit: not yet wired to exposure data; default neutral 0.5
    // for both strategies. Hook reserved for §10 ExposureChecker.
    final portfolioFitScore = Decimal.parse('0.50');

    final eventSafetyScore =
        (hasUpcomingEarnings || hasUpcomingMacroEvent)
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
        : (premium.amount / cashRequired.amount)
            .toDecimal(scaleOnInfinitePrecision: 6);
    final dteRatio = contract.dte <= 0
        ? Decimal.zero
        : (Decimal.fromInt(365) / Decimal.fromInt(contract.dte))
            .toDecimal(scaleOnInfinitePrecision: 6);
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

  Money _putCashRequired(OptionContract contract) =>
      Money(contract.strike.amount * Decimal.fromInt(100), contract.strike.currency);

  Decimal _saturate({
    required Decimal base,
    required Decimal floor,
    required Decimal ceiling,
  }) {
    if (ceiling <= floor) return Decimal.one;
    if (base <= floor) return Decimal.zero;
    if (base >= ceiling) return Decimal.one;
    final fraction = ((base - floor) / (ceiling - floor))
        .toDecimal(scaleOnInfinitePrecision: 4);
    return fraction.clamp(Decimal.zero, Decimal.one);
  }

  Decimal _avg(List<Decimal> values) {
    if (values.isEmpty) return Decimal.zero;
    final sum = values.fold<Decimal>(Decimal.zero, (a, b) => a + b);
    return (sum / Decimal.fromInt(values.length))
        .toDecimal(scaleOnInfinitePrecision: 4);
  }

  String _strengthBullet(
    MapEntry<String, Decimal> entry,
    OpportunityMetrics metrics,
    OptionContract contract,
  ) {
    final pct = _pct(entry.value);
    switch (entry.key) {
      case 'yield':
        return '年化收益 ${_pct(metrics.annualizedYield)}（评分 $pct）';
      case 'liquidity':
        return '流动性好：买卖价差 ${_pct(contract.bidAskSpreadPct)}，未平仓 ${contract.openInterest}（评分 $pct）';
      case 'safety_margin':
        return '安全边际 ${_pct(metrics.marginOfSafety)} 距盈亏平衡（评分 $pct）';
      case 'iv':
        return '隐含波动率 ${contract.impliedVolatility == null ? "未知" : _pct(contract.impliedVolatility!)} 处于稳健区间（评分 $pct）';
      case 'portfolio_fit':
        return '与现有仓位契合（评分 $pct）';
      case 'event_safety':
        return '近 7 天无业绩/宏观事件（评分 $pct）';
      default:
        return '${entry.key} 评分 $pct';
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
        return '年化收益偏低：${_pct(metrics.annualizedYield)}（评分 $pct）';
      case 'liquidity':
        return '流动性一般：买卖价差 ${_pct(contract.bidAskSpreadPct)}（评分 $pct）';
      case 'safety_margin':
        return '安全边际有限：${_pct(metrics.marginOfSafety)}（评分 $pct）';
      case 'iv':
        return '隐含波动率偏离常态（评分 $pct）';
      case 'portfolio_fit':
        return '与现有仓位契合度一般（评分 $pct）';
      case 'event_safety':
        return '事件窗口内执行需注意（评分 $pct）';
      default:
        return '${entry.key} 评分 $pct';
    }
  }

  String _summary({
    required OptionsStrategyKind strategy,
    required OptionContract contract,
    required OpportunityMetrics metrics,
  }) {
    final action =
        strategy == OptionsStrategyKind.cashSecuredPut ? '卖看跌' : '备兑看涨';
    return '${contract.underlying} ${contract.dte}DTE $action @ ${contract.strike.currency} ${_fmt(contract.strike.amount)} —— 年化 ${_pct(metrics.annualizedYield)}，安全边际 ${_pct(metrics.marginOfSafety)}';
  }

  String _bestForLine(OptionsStrategyKind strategy, OptionsStrategyMode mode) {
    switch (strategy) {
      case OptionsStrategyKind.cashSecuredPut:
        switch (mode) {
          case OptionsStrategyMode.conservative:
            return '适合保守现金流偏好：高安全边际、流动性优先';
          case OptionsStrategyMode.balanced:
          case OptionsStrategyMode.custom:
            return '适合稳健现金流偏好：平衡收益与下跌风险';
          case OptionsStrategyMode.aggressive:
            return '适合愿意承担更高被行权概率以换取年化收益的策略';
        }
      case OptionsStrategyKind.coveredCall:
        switch (mode) {
          case OptionsStrategyMode.conservative:
            return '适合保守增益偏好：卖远 OTM call，少触发被行权';
          case OptionsStrategyMode.balanced:
          case OptionsStrategyMode.custom:
            return '适合稳健增益偏好：在不打散持仓的前提下增厚收益';
          case OptionsStrategyMode.aggressive:
            return '适合愿意接受被行权以兑现盈利的策略';
        }
    }
  }

  String _avoidIfLine(OptionsStrategyKind strategy) {
    switch (strategy) {
      case OptionsStrategyKind.cashSecuredPut:
        return '若你不愿在被行权时按 strike 买入 100 股，请放弃此机会';
      case OptionsStrategyKind.coveredCall:
        return '若你不愿在 strike 价位卖出 100 股，请放弃此机会';
    }
  }

  String _worstCase(
    OptionsStrategyKind strategy,
    OptionContract contract,
    OpportunityMetrics metrics,
  ) {
    final currency = contract.strike.currency;
    switch (strategy) {
      case OptionsStrategyKind.cashSecuredPut:
        return '若 ${contract.underlying} 跌破 $currency ${_fmt(contract.strike.amount)}，'
            '你将以实际成本 $currency ${_fmt(metrics.breakeven.amount)} 买入 100 股，'
            '占用现金 $currency ${_fmt(metrics.cashRequired.amount)}';
      case OptionsStrategyKind.coveredCall:
        final cap = contract.strike.amount + contract.mid.amount;
        return '若 ${contract.underlying} 涨到 $currency ${_fmt(contract.strike.amount)}，'
            '你将以 $currency ${_fmt(contract.strike.amount)} 卖出 100 股，'
            '错过该价位以上的全部上涨；总收益上限为 $currency ${_fmt(cap)}';
    }
  }

  String _pct(Decimal value) {
    final hundred = (value * Decimal.fromInt(100)).toStringAsFixed(1);
    return '$hundred%';
  }

  String _fmt(Decimal value) => value.toStringAsFixed(2);
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
