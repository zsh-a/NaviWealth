import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/options_income/domain/approved_underlying.dart';
import 'package:naviwealth/features/finance/options_income/domain/option_contract.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/services/opportunity_scorer.dart';

void main() {
  group('OpportunityScorer hard filters', () {
    test('rejects cash-secured put when underlying not approved', () {
      const scorer = OpportunityScorer();
      final contract = _putContract(strike: 190);
      final result = scorer.filter(
        contract: contract,
        strategy: OptionsStrategyKind.cashSecuredPut,
        profile: _profileBalanced(),
        approved: null,
        sharesOwned: 0,
        availableCash: Money.parse('1000000', 'USD'),
      );
      expect(result, isNotNull);
      expect(result!.reasons, contains('underlying_not_approved_for_put'));
    });

    test('rejects covered call when shares < 100', () {
      const scorer = OpportunityScorer();
      final contract = _callContract(strike: 200);
      final result = scorer.filter(
        contract: contract,
        strategy: OptionsStrategyKind.coveredCall,
        profile: _profileBalanced(),
        approved: _approved(symbol: 'AAPL'),
        sharesOwned: 50,
        availableCash: Money.parse('1000000', 'USD'),
      );
      expect(result, isNotNull);
      expect(result!.reasons, contains('insufficient_shares'));
    });

    test('rejects sell put when cash cap is hit', () {
      const scorer = OpportunityScorer();
      final contract = _putContract(strike: 190);
      final smallCash = Money.parse('10000', 'USD');
      final result = scorer.filter(
        contract: contract,
        strategy: OptionsStrategyKind.cashSecuredPut,
        profile: _profileBalanced(),
        approved: _approved(symbol: 'AAPL'),
        sharesOwned: 0,
        availableCash: smallCash,
      );
      expect(result, isNotNull);
      expect(result!.reasons, contains('cash_required_above_cap'));
    });

    test('rejects sell put when available cash is a different currency', () {
      const scorer = OpportunityScorer();
      final contract = _putContract(strike: 190);
      final result = scorer.filter(
        contract: contract,
        strategy: OptionsStrategyKind.cashSecuredPut,
        profile: _profileBalanced(),
        approved: _approved(symbol: 'AAPL'),
        sharesOwned: 0,
        availableCash: Money.parse('1000000', 'CNY'),
      );

      expect(result, isNotNull);
      expect(result!.reasons, contains('available_cash_currency_mismatch'));
      expect(result.reasons, contains('cash_required_above_cap'));
      expect(
        scorer.scoreOne(
          contract: contract,
          strategy: OptionsStrategyKind.cashSecuredPut,
          profile: _profileBalanced(),
          approved: _approved(symbol: 'AAPL'),
          sharesOwned: 0,
          availableCash: Money.parse('1000000', 'CNY'),
        ),
        isNull,
      );
    });

    test('rejects when spread is too wide', () {
      const scorer = OpportunityScorer();
      final contract = _putContract(strike: 190, bid: 1.0, ask: 5.0);
      final result = scorer.filter(
        contract: contract,
        strategy: OptionsStrategyKind.cashSecuredPut,
        profile: _profileBalanced(),
        approved: _approved(symbol: 'AAPL'),
        sharesOwned: 0,
        availableCash: Money.parse('1000000', 'USD'),
      );
      expect(result, isNotNull);
      expect(result!.reasons, contains('bid_ask_spread_too_wide'));
    });
  });

  group('OpportunityScorer scoring', () {
    test('scores a clean cash-secured put as a non-null candidate', () {
      const scorer = OpportunityScorer();
      final contract = _putContract(strike: 190, bid: 2.5, ask: 2.6);
      final scored = scorer.scoreOne(
        contract: contract,
        strategy: OptionsStrategyKind.cashSecuredPut,
        profile: _profileBalanced(),
        approved: _approved(symbol: 'AAPL'),
        sharesOwned: 0,
        availableCash: Money.parse('1000000', 'USD'),
      );
      expect(scored, isNotNull);
      final opp = scored!.opportunity;
      expect(opp.score, greaterThan(Decimal.zero));
      expect(opp.score, lessThanOrEqualTo(Decimal.one));
      expect(opp.metrics.cashRequired.amount.toString(), '19000');
      expect(opp.metrics.premium.amount, greaterThan(Decimal.zero));
      expect(opp.explanation.whyGood, isNotEmpty);
      expect(opp.explanation.worstCase, contains('AAPL'));
    });

    test('does not hard-filter an empty bid quote when mid is available', () {
      const scorer = OpportunityScorer();
      final contract = _putContract(
        strike: 190,
        bid: 0,
        ask: 0,
        mid: 2.5,
        spread: Decimal.one,
      );
      final rejection = scorer.filter(
        contract: contract,
        strategy: OptionsStrategyKind.cashSecuredPut,
        profile: _profileBalanced(),
        approved: _approved(symbol: 'AAPL'),
        sharesOwned: 0,
        availableCash: Money.parse('1000000', 'USD'),
      );
      expect(rejection, isNull);

      final scored = scorer.scoreOne(
        contract: contract,
        strategy: OptionsStrategyKind.cashSecuredPut,
        profile: _profileBalanced(),
        approved: _approved(symbol: 'AAPL'),
        sharesOwned: 0,
        availableCash: Money.parse('1000000', 'USD'),
      );
      expect(scored, isNotNull);
      expect(scored!.opportunity.metrics.premium.amount, Decimal.fromInt(250));
    });

    test('annualized yield = static return × 365 / dte', () {
      const scorer = OpportunityScorer();
      final contract = _putContract(strike: 200, dte: 30, bid: 2.0, ask: 2.2);
      final scored = scorer.scoreOne(
        contract: contract,
        strategy: OptionsStrategyKind.cashSecuredPut,
        profile: _profileBalanced(),
        approved: _approved(symbol: 'AAPL'),
        sharesOwned: 0,
        availableCash: Money.parse('1000000', 'USD'),
      );
      expect(scored, isNotNull);
      final metrics = scored!.opportunity.metrics;
      // mid = 2.10, premium = 210, cashRequired = 20000, static = 0.0105
      expect(metrics.staticReturn.toString(), startsWith('0.0105'));
      // annualised = 0.0105 * 365/30 ≈ 0.12775
      final annual = metrics.annualizedYield.toDouble();
      expect(annual, closeTo(0.12775, 0.001));
    });

    test('covered call breakeven = strike + premium per share', () {
      const scorer = OpportunityScorer();
      final contract = _callContract(strike: 210, bid: 2.5, ask: 2.7);
      final scored = scorer.scoreOne(
        contract: contract,
        strategy: OptionsStrategyKind.coveredCall,
        profile: _profileBalanced(),
        approved: _approved(symbol: 'AAPL'),
        sharesOwned: 100,
        availableCash: Money.parse('1000000', 'USD'),
      );
      expect(scored, isNotNull);
      final m = scored!.opportunity.metrics;
      // mid = 2.60, breakeven = 212.6
      expect(m.breakeven.amount.toString(), '212.6');
    });

    test('portfolio fit drops as current underlying exposure nears cap', () {
      const scorer = OpportunityScorer();
      final contract = _putContract(strike: 190, bid: 2.5, ask: 2.6);
      final profile = _profileBalanced().copyWith(
        maxUnderlyingExposurePct: Decimal.parse('0.20'),
      );
      final lowExposure = scorer.scoreOne(
        contract: contract,
        strategy: OptionsStrategyKind.cashSecuredPut,
        profile: profile,
        approved: _approved(symbol: 'AAPL'),
        sharesOwned: 0,
        availableCash: Money.parse('1000000', 'USD'),
        currentUnderlyingExposurePct: Decimal.parse('0.05'),
      );
      final highExposure = scorer.scoreOne(
        contract: contract,
        strategy: OptionsStrategyKind.cashSecuredPut,
        profile: profile,
        approved: _approved(symbol: 'AAPL'),
        sharesOwned: 0,
        availableCash: Money.parse('1000000', 'USD'),
        currentUnderlyingExposurePct: Decimal.parse('0.20'),
      );

      expect(lowExposure, isNotNull);
      expect(highExposure, isNotNull);
      expect(
        lowExposure!.opportunity.score,
        greaterThan(highExposure!.opportunity.score),
      );
    });
  });
}

OptionsStrategyProfile _profileBalanced() => defaultProfileForMode(
  OptionsStrategyMode.balanced,
).copyWith(riskDisclosureAckAt: DateTime.utc(2026, 5, 21));

ApprovedUnderlying _approved({
  required String symbol,
  bool allowPut = true,
  bool allowCall = true,
}) => ApprovedUnderlying(
  id: ApprovedUnderlying.idFor(market: AssetMarket.usStock, symbol: symbol),
  symbol: symbol,
  market: AssetMarket.usStock,
  allowPut: allowPut,
  allowCall: allowCall,
  maxBuyPrice: null,
  minSellPrice: null,
  notes: null,
  sync: SyncMeta(
    ownerUserId: 'u1',
    updatedAt: DateTime.utc(2026, 5, 21),
    updatedByDevice: 'dev',
    hlc: Hlc.zero('u1'),
  ),
);

OptionContract _putContract({
  required double strike,
  double bid = 1.5,
  double ask = 1.6,
  double? mid,
  Decimal? spread,
  int dte = 30,
  int oi = 500,
  int volume = 50,
}) => _contract(
  type: OptionType.put,
  strike: strike,
  bid: bid,
  ask: ask,
  mid: mid,
  spread: spread,
  dte: dte,
  oi: oi,
  volume: volume,
);

OptionContract _callContract({
  required double strike,
  double bid = 1.5,
  double ask = 1.6,
  double? mid,
  Decimal? spread,
  int dte = 30,
  int oi = 500,
  int volume = 50,
}) => _contract(
  type: OptionType.call,
  strike: strike,
  bid: bid,
  ask: ask,
  mid: mid,
  spread: spread,
  dte: dte,
  oi: oi,
  volume: volume,
);

OptionContract _contract({
  required OptionType type,
  required double strike,
  required double bid,
  required double ask,
  required double? mid,
  required Decimal? spread,
  required int dte,
  required int oi,
  required int volume,
}) {
  final strikeDec = Decimal.parse(strike.toString());
  final bidDec = Decimal.parse(bid.toString());
  final askDec = Decimal.parse(ask.toString());
  final midDec = Decimal.parse((mid ?? ((bid + ask) / 2)).toStringAsFixed(4));
  final spreadDenominator = midDec <= Decimal.zero ? Decimal.one : midDec;
  final bidAskSpreadPct =
      spread ??
      ((askDec - bidDec) / spreadDenominator).toDecimal(
        scaleOnInfinitePrecision: 6,
      );
  return OptionContract(
    underlying: 'AAPL',
    market: AssetMarket.usStock,
    optionSymbol:
        'AAPL250620${type == OptionType.put ? "P" : "C"}'
        '${(strike * 1000).toInt().toString().padLeft(8, "0")}',
    type: type,
    expiration: DateTime.utc(2026, 6, 20),
    dte: dte,
    strike: Money(strikeDec, 'USD'),
    bid: Money(bidDec, 'USD'),
    ask: Money(askDec, 'USD'),
    mid: Money(midDec, 'USD'),
    volume: volume,
    openInterest: oi,
    impliedVolatility: Decimal.parse('0.25'),
    delta: null,
    underlyingPrice: Money.parse('200', 'USD'),
    bidAskSpreadPct: bidAskSpreadPct,
    fetchedAt: DateTime.utc(2026, 5, 21),
  );
}
