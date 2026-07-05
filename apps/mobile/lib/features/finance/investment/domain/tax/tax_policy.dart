import 'package:decimal/decimal.dart';

import 'tax_jurisdiction.dart';

/// Pluggable tax calculator.
///
/// The cost-basis engine already records the *actual* withholding the user
/// observed (broker-reported), so this contract is for **estimating**:
///
/// - the dividend withholding the user would have paid if the broker did
///   not pre-deduct it, and
/// - the capital gains tax owed on a realized sell.
///
/// Implementations must be pure (no I/O) so they can be reused in the
/// reporting layer and in form preview UIs.
abstract class TaxPolicy {
  /// Estimated withholding on a gross dividend.
  ///
  /// [sourceJurisdiction] is where the asset / issuer is domiciled (drives
  /// the WHT rate per double-tax treaty); [holderJurisdiction] is where the
  /// user files. Same-jurisdiction usually means no WHT — the tax shows up
  /// on the holder's annual return instead.
  DividendTaxResult dividendWithholding({
    required Decimal grossAmount,
    required String currency,
    required TaxJurisdiction sourceJurisdiction,
    required TaxJurisdiction holderJurisdiction,
  });

  /// Estimated capital gains tax on a realized gain.
  ///
  /// [holdingPeriod] is the elapsed time from buy to sell. Some
  /// jurisdictions tax short-term holds at a higher rate (e.g. US ≤1 year),
  /// or exempt holds beyond a threshold (e.g. CN A-share PIT exemption).
  /// Implementations may ignore [holdingPeriod] when their policy does not
  /// vary by tenor.
  ///
  /// Realized losses (negative [realizedGain]) result in zero tax — loss
  /// carry-forward is a portfolio-level operation outside this seam.
  CapitalGainsTaxResult capitalGainsTax({
    required Decimal realizedGain,
    required String currency,
    required Duration holdingPeriod,
    required TaxJurisdiction holderJurisdiction,
  });
}

/// Outcome of [TaxPolicy.dividendWithholding].
class DividendTaxResult {
  const DividendTaxResult({
    required this.grossAmount,
    required this.withholdingTax,
    required this.netAmount,
    required this.rate,
    required this.currency,
  });

  factory DividendTaxResult.zero(Decimal grossAmount, String currency) =>
      DividendTaxResult(
        grossAmount: grossAmount,
        withholdingTax: Decimal.zero,
        netAmount: grossAmount,
        rate: Decimal.zero,
        currency: currency,
      );

  final Decimal grossAmount;
  final Decimal withholdingTax;

  /// Gross minus withholding.
  final Decimal netAmount;

  /// Effective rate that was applied (`withholdingTax / grossAmount`),
  /// preserved so reports can render it without re-deriving.
  final Decimal rate;

  final String currency;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DividendTaxResult &&
        other.grossAmount == grossAmount &&
        other.withholdingTax == withholdingTax &&
        other.netAmount == netAmount &&
        other.rate == rate &&
        other.currency == currency;
  }

  @override
  int get hashCode =>
      Object.hash(grossAmount, withholdingTax, netAmount, rate, currency);

  @override
  String toString() =>
      'DividendTaxResult(gross: $grossAmount, wht: $withholdingTax, '
      'net: $netAmount $currency, rate: $rate)';
}

/// Outcome of [TaxPolicy.capitalGainsTax].
class CapitalGainsTaxResult {
  const CapitalGainsTaxResult({
    required this.realizedGain,
    required this.tax,
    required this.rate,
    required this.currency,
    required this.holdingPeriod,
  });

  factory CapitalGainsTaxResult.zero({
    required Decimal realizedGain,
    required String currency,
    required Duration holdingPeriod,
  }) => CapitalGainsTaxResult(
    realizedGain: realizedGain,
    tax: Decimal.zero,
    rate: Decimal.zero,
    currency: currency,
    holdingPeriod: holdingPeriod,
  );

  final Decimal realizedGain;
  final Decimal tax;

  /// Effective rate applied (`tax / realizedGain` for positive gains,
  /// zero for losses).
  final Decimal rate;

  final String currency;
  final Duration holdingPeriod;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CapitalGainsTaxResult &&
        other.realizedGain == realizedGain &&
        other.tax == tax &&
        other.rate == rate &&
        other.currency == currency &&
        other.holdingPeriod == holdingPeriod;
  }

  @override
  int get hashCode =>
      Object.hash(realizedGain, tax, rate, currency, holdingPeriod);

  @override
  String toString() =>
      'CapitalGainsTaxResult(gain: $realizedGain, tax: $tax $currency, '
      'rate: $rate, period: ${holdingPeriod.inDays}d)';
}
