import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

import 'package:naviwealth/features/finance/domain/fx/money.dart';

/// Leaf strings the scorer stitches into an `OpportunityExplanation`.
///
/// The scorer runs in the domain layer and must stay free of
/// `AppLocalizations`; callers inject a locale-aware implementation
/// (see `application/opportunity_explanation_l10n.dart`) so the cached
/// explanation is generated in the user's language. The default English
/// implementation keeps the scorer usable in pure-domain tests.
abstract interface class OpportunityExplanationTexts {
  String percent(Decimal ratio);
  String money(Money value);

  String yieldStrength(String yieldPct, String score);
  String liquidityStrength(String spread, int openInterest, String score);
  String safetyStrength(String margin, String score);
  String ivStrength(String iv, String score);
  String ivUnknown();
  String fitStrength(String score);
  String eventStrength(String score);
  String eventUnavailable();
  String genericScore(String dimension, String score);

  String yieldWeak(String yieldPct, String score);
  String liquidityWeak(String spread, String score);
  String safetyWeak(String margin, String score);
  String ivWeak(String score);
  String fitWeak(String score);
  String eventWeak(String score);
  String eventCheck();

  String summaryPut(
    String symbol,
    int dte,
    String strike,
    String yieldPct,
    String margin,
  );
  String summaryCall(
    String symbol,
    int dte,
    String strike,
    String yieldPct,
    String margin,
  );

  String bestForPutConservative();
  String bestForPutBalanced();
  String bestForPutAggressive();
  String bestForCallConservative();
  String bestForCallBalanced();
  String bestForCallAggressive();

  String avoidPut();
  String avoidCall();

  String worstCasePut(
    String symbol,
    String strike,
    String breakeven,
    String cash,
  );
  String worstCaseCall(String symbol, String strike, String cap);

  // Buy-side LEAPS lane.
  String leapsSummary(
    String symbol,
    int dte,
    String strike,
    String cost,
    String delta,
  );
  String leapsWorstCase(String symbol, String strike, String cost);
  String leapsBestFor();
  String leapsAvoid();
  String leapsCostBullet(String costPct);
  String leapsLeverageBullet(String leverage, String delta);
  String leapsIntrinsicBullet(String intrinsicPct);
  String leapsSpreadBullet(String spread);
  String leapsThetaBullet(String extrinsic);
  String leapsFundingBullet(String coverage);
}

/// English fallback mirroring the pre-localized copy.
class DefaultOpportunityExplanationTexts
    implements OpportunityExplanationTexts {
  const DefaultOpportunityExplanationTexts();

  @override
  String percent(Decimal ratio) {
    final hundred = (ratio * Decimal.fromInt(100)).toStringAsFixed(1);
    return '$hundred%';
  }

  @override
  String money(Money value) {
    return NumberFormat.currency(
      locale: 'en',
      name: value.currency,
      symbol: '${value.currency} ',
      decimalDigits: 2,
    ).format(value.amount.toDouble());
  }

  @override
  String yieldStrength(String yieldPct, String score) =>
      'Annualized yield $yieldPct (score $score)';

  @override
  String liquidityStrength(String spread, int openInterest, String score) =>
      'Good liquidity: bid/ask spread $spread, open interest '
      '$openInterest (score $score)';

  @override
  String safetyStrength(String margin, String score) =>
      'Margin of safety $margin from breakeven (score $score)';

  @override
  String ivStrength(String iv, String score) =>
      'Implied volatility $iv is in a resilient range (score $score)';

  @override
  String ivUnknown() => 'unknown';

  @override
  String fitStrength(String score) => 'Fits current positions (score $score)';

  @override
  String eventStrength(String score) =>
      'No earnings or macro event in the next 7 days (score $score)';

  @override
  String eventUnavailable() =>
      'Event calendar unavailable; event risk is not scored';

  @override
  String genericScore(String dimension, String score) =>
      '$dimension score $score';

  @override
  String yieldWeak(String yieldPct, String score) =>
      'Lower annualized yield: $yieldPct (score $score)';

  @override
  String liquidityWeak(String spread, String score) =>
      'Moderate liquidity: bid/ask spread $spread (score $score)';

  @override
  String safetyWeak(String margin, String score) =>
      'Limited margin of safety: $margin (score $score)';

  @override
  String ivWeak(String score) =>
      'Implied volatility is outside the normal range (score $score)';

  @override
  String fitWeak(String score) =>
      'Only a moderate fit with current positions (score $score)';

  @override
  String eventWeak(String score) =>
      'Execution needs caution inside the event window (score $score)';

  @override
  String eventCheck() =>
      'Check earnings and macro dates before placing the trade';

  @override
  String summaryPut(
    String symbol,
    int dte,
    String strike,
    String yieldPct,
    String margin,
  ) =>
      '$symbol ${dte}DTE sell put @ $strike — annualized $yieldPct, '
      'margin of safety $margin';

  @override
  String summaryCall(
    String symbol,
    int dte,
    String strike,
    String yieldPct,
    String margin,
  ) =>
      '$symbol ${dte}DTE covered call @ $strike — annualized $yieldPct, '
      'margin of safety $margin';

  @override
  String bestForPutConservative() =>
      'Best for conservative cash-flow preference: higher margin of safety '
      'and liquidity first.';

  @override
  String bestForPutBalanced() =>
      'Best for balanced cash-flow preference: balances yield against '
      'downside risk.';

  @override
  String bestForPutAggressive() =>
      'Best when you accept higher assignment probability in exchange for '
      'annualized yield.';

  @override
  String bestForCallConservative() =>
      'Best for conservative enhancement: sell farther OTM calls with lower '
      'assignment probability.';

  @override
  String bestForCallBalanced() =>
      'Best for balanced enhancement: add income without materially '
      'disrupting the position.';

  @override
  String bestForCallAggressive() =>
      'Best when you are willing to accept assignment to realize gains.';

  @override
  String avoidPut() =>
      'Avoid if you are not willing to buy 100 shares at the strike when '
      'assigned.';

  @override
  String avoidCall() =>
      'Avoid if you are not willing to sell 100 shares at the strike.';

  @override
  String worstCasePut(
    String symbol,
    String strike,
    String breakeven,
    String cash,
  ) =>
      'If $symbol falls below $strike, you would buy 100 shares at an '
      'effective cost of $breakeven, using $cash cash.';

  @override
  String worstCaseCall(String symbol, String strike, String cap) =>
      'If $symbol rises to $strike, you would sell 100 shares at $strike '
      'and miss upside above that level; total proceeds are capped at $cap.';

  @override
  String leapsSummary(
    String symbol,
    int dte,
    String strike,
    String cost,
    String delta,
  ) => '$symbol ${dte}DTE LEAPS call @ $strike — cost $cost, delta $delta';

  @override
  String leapsWorstCase(String symbol, String strike, String cost) =>
      'If $symbol closes below $strike at expiration, the entire $cost '
      'premium is lost. Maximum loss is the full cost paid.';

  @override
  String leapsBestFor() =>
      'Best as a funded stock substitute: long-dated deep-in-the-money '
      'exposure paid for by wheel or dividend income.';

  @override
  String leapsAvoid() =>
      'Avoid if you cannot hold through a full drawdown — time value '
      'decays and the position can expire worthless.';

  @override
  String leapsCostBullet(String costPct) =>
      'Annualized time-value cost $costPct per unit of share exposure';

  @override
  String leapsLeverageBullet(String leverage, String delta) =>
      'Controls ${leverage}x the share exposure per unit of capital '
      '(delta $delta)';

  @override
  String leapsIntrinsicBullet(String intrinsicPct) =>
      '$intrinsicPct of the premium is intrinsic value';

  @override
  String leapsSpreadBullet(String spread) =>
      'Wide bid/ask spread $spread — LEAPS liquidity is thin, use limit '
      'orders';

  @override
  String leapsThetaBullet(String extrinsic) =>
      '$extrinsic of time value will decay to zero by expiration';

  @override
  String leapsFundingBullet(String coverage) =>
      'Group income already covers $coverage of this cost';
}
