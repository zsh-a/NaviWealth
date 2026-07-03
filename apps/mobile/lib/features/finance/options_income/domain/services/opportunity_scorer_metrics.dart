part of 'opportunity_scorer.dart';

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
