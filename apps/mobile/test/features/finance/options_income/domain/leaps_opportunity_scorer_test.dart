import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/options_income/domain/option_contract.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_opportunity.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/services/leaps_opportunity_scorer.dart';

void main() {
  final profile = defaultProfileForMode(OptionsStrategyMode.balanced);
  const scorer = LeapsOpportunityScorer();

  group('LeapsOpportunityScorer', () {
    test('deep ITM call scores with buy-side economics', () {
      final scored = scorer.scoreOne(
        contract: _call(strike: 150, mid: 55, delta: '0.80', dte: 730),
        profile: profile,
      );
      expect(scored, isNotNull);
      expect(scored!.strategy, OpportunityStrategy.leapsCall);
      final m = scored.metrics as LeapsOpportunityMetrics;
      // mid 55 → cost 5500; intrinsic (200-150)*100 = 5000; extrinsic 500.
      expect(m.totalCost, Money.parse('5500', 'USD'));
      expect(m.extrinsicValue, Money.parse('500', 'USD'));
      expect(m.breakeven, Money.parse('205', 'USD'));
      // exposure = 200 * 0.80 * 100 = 16000; leverage ≈ 2.909.
      expect(m.leverageRatio!.toDouble(), closeTo(2.909, 0.001));
      // annualized cost = 500/16000 * 365/730 = 0.015625.
      expect(
        m.annualizedExtrinsicCostPct!.toDouble(),
        closeTo(0.015625, 0.0001),
      );
      expect(scored.explanation.worstCase, contains('QQQ'));
      expect(scored.explanation.scoreBreakdown['cost_efficiency'], isNotNull);
    });

    test('delta outside the stock-substitute band is rejected', () {
      final contract = _call(strike: 210, mid: 8, delta: '0.35', dte: 730);
      expect(scorer.scoreOne(contract: contract, profile: profile), isNull);
      expect(
        scorer.filter(contract: contract, profile: profile)!.reasons,
        contains('delta_outside_target_range'),
      );
    });

    test('short-dated calls are not LEAPS', () {
      final contract = _call(strike: 150, mid: 52, delta: '0.80', dte: 90);
      expect(
        scorer.filter(contract: contract, profile: profile)!.reasons,
        contains('dte_outside_target_range'),
      );
    });

    test('budget hard-rejects contracts costing more than the remainder', () {
      final contract = _call(strike: 150, mid: 55, delta: '0.80', dte: 730);
      expect(
        scorer
            .filter(
              contract: contract,
              profile: profile,
              budgetRemaining: Money.parse('5000', 'USD'),
            )!
            .reasons,
        contains('leaps_budget_exceeded'),
      );
      expect(
        scorer.scoreOne(
          contract: contract,
          profile: profile,
          budgetRemaining: Money.parse('6000', 'USD'),
        ),
        isNotNull,
      );
    });

    test('group funding pool becomes a coverage ratio', () {
      final scored = scorer.scoreOne(
        contract: _call(strike: 150, mid: 55, delta: '0.80', dte: 730),
        profile: profile,
        groupFundingPool: Money.parse('2750', 'USD'),
      );
      final m = scored!.metrics as LeapsOpportunityMetrics;
      expect(m.fundingCoveragePct, Decimal.parse('0.5'));
    });

    test('missing broker delta falls back to a Black–Scholes estimate', () {
      // yfinance never returns greeks: delta comes from IV instead.
      // Spot 200, strike 160, IV 22%, 730d, r 4% → d1 ≈ 1.5987 → Δ ≈ 0.945.
      // That is above the balanced band, so pick a strike near spot:
      // strike 195 → d1 ≈ 0.4941 → Δ ≈ 0.689 (inside 0.65–0.80).
      final scored = scorer.scoreOne(
        contract: _call(
          strike: 195,
          mid: 30,
          delta: null,
          dte: 730,
          impliedVolatility: '0.22',
        ),
        profile: profile,
      );
      expect(scored, isNotNull);
      final m = scored!.metrics as LeapsOpportunityMetrics;
      expect(m.leverageRatio, isNotNull);
      // Estimated delta lands in the band and the explanation carries it.
      // Estimated deltas are visibly marked and disclosed as a risk.
      expect(scored.explanation.summary, contains('≈0.6'));
      expect(
        scored.explanation.whyRisky.join(' '),
        contains('estimated from implied volatility'),
      );
    });

    test('missing delta AND missing IV still rejects', () {
      final contract = _call(
        strike: 195,
        mid: 30,
        delta: null,
        dte: 730,
        impliedVolatility: null,
      );
      expect(
        scorer.filter(contract: contract, profile: profile)!.reasons,
        contains('delta_unavailable'),
      );
    });

    test('rejections carry the LEAPS lane tag', () {
      final contract = _call(strike: 150, mid: 55, delta: '0.95', dte: 730);
      expect(
        scorer.filter(contract: contract, profile: profile)!.strategy,
        OpportunityStrategy.leapsCall,
      );
    });

    test('puts never enter the LEAPS lane', () {
      final put = _call(
        strike: 150,
        mid: 55,
        delta: '0.80',
        dte: 730,
        type: OptionType.put,
      );
      expect(
        scorer.filter(contract: put, profile: profile)!.reasons,
        contains('not_a_call'),
      );
    });
  });
}

OptionContract _call({
  required int strike,
  required double mid,
  required String? delta,
  required int dte,
  OptionType type = OptionType.call,
  String? impliedVolatility = '0.22',
}) {
  final midMoney = Money.parse(mid.toString(), 'USD');
  return OptionContract(
    underlying: 'QQQ',
    market: AssetMarket.usStock,
    optionSymbol: 'QQQ280121C00${strike}000',
    type: type,
    expiration: DateTime.utc(2028, 1, 21),
    dte: dte,
    strike: Money.parse('$strike', 'USD'),
    bid: midMoney,
    ask: midMoney,
    mid: midMoney,
    volume: 40,
    openInterest: 400,
    impliedVolatility: impliedVolatility == null
        ? null
        : Decimal.parse(impliedVolatility),
    delta: delta == null ? null : Decimal.parse(delta),
    underlyingPrice: Money.parse('200', 'USD'),
    bidAskSpreadPct: Decimal.parse('0.02'),
    fetchedAt: DateTime.utc(2026, 7, 26),
  );
}
