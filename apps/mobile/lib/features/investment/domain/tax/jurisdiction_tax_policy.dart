import 'package:decimal/decimal.dart';

import 'tax_jurisdiction.dart';
import 'tax_policy.dart';

/// Per-pair dividend WHT and per-jurisdiction capital-gains rule set.
///
/// Defaults reflect the most common consumer cases (so the app produces
/// reasonable numbers out of the box):
///
/// - **CN → CN dividends**: 0–20 % differential rate by holding period
///   (≤ 1 month: 20 %, > 1 month and ≤ 1 year: 10 %, > 1 year: 0 %). The
///   policy here applies the **median** 10 % rate by default — finer-
///   grained rules can be reconfigured by the caller because this engine
///   is a simple lookup, not a full tax engine.
/// - **US → non-US dividends**: 30 % default WHT. CN/HK holders may file
///   for a treaty rate; the policy stores the contractual rate and lets
///   the caller override per-account.
/// - **CN A-share capital gains**: 0 % for individual investors (waived
///   by `财税 [2009] 167号` and successors).
/// - **US capital gains**: 15 % long-term (>= 365 days), 22 % short-term
///   (< 365 days) — placeholder rates, the user reconfigures per filing.
/// - **HK capital gains**: 0 %.
///
/// All rates are stored as `Decimal` fractions (`0.10` = 10 %).
class JurisdictionTaxPolicy implements TaxPolicy {
  JurisdictionTaxPolicy({
    Map<DividendTaxKey, Decimal>? dividendRates,
    Map<TaxJurisdiction, CapitalGainsRateRule>? capitalGainsRules,
    int decimalScale = 8,
  }) : dividendRates = Map.unmodifiable(dividendRates ?? defaultDividendRates),
       capitalGainsRules = Map.unmodifiable(
         capitalGainsRules ?? defaultCapitalGainsRules,
       ),
       _scale = decimalScale {
    for (final entry in this.dividendRates.entries) {
      _requireRateInRange(entry.value, 'dividendRates[${entry.key}]');
    }
    for (final rule in this.capitalGainsRules.values) {
      _requireRateInRange(rule.shortTermRate, 'capitalGainsRules.shortTerm');
      _requireRateInRange(rule.longTermRate, 'capitalGainsRules.longTerm');
    }
  }

  /// Default dividend WHT rates. Keys are `(source, holder)` pairs; missing
  /// pairs resolve to 0 % WHT (we treat unknown corridors as no
  /// pre-deduction; the holder still owes tax at year-end).
  static final Map<DividendTaxKey, Decimal> defaultDividendRates = {
    const DividendTaxKey(TaxJurisdiction.cn, TaxJurisdiction.cn): _d('0.10'),
    const DividendTaxKey(TaxJurisdiction.us, TaxJurisdiction.us): _d('0'),
    const DividendTaxKey(TaxJurisdiction.us, TaxJurisdiction.cn): _d('0.10'),
    const DividendTaxKey(TaxJurisdiction.us, TaxJurisdiction.hk): _d('0.30'),
    const DividendTaxKey(TaxJurisdiction.us, TaxJurisdiction.other): _d('0.30'),
    const DividendTaxKey(TaxJurisdiction.hk, TaxJurisdiction.hk): _d('0'),
    const DividendTaxKey(TaxJurisdiction.hk, TaxJurisdiction.cn): _d('0'),
    const DividendTaxKey(TaxJurisdiction.cn, TaxJurisdiction.hk): _d('0.10'),
    const DividendTaxKey(TaxJurisdiction.cn, TaxJurisdiction.us): _d('0.10'),
  };

  /// Default capital-gains rules per holder jurisdiction.
  static final Map<TaxJurisdiction, CapitalGainsRateRule>
  defaultCapitalGainsRules = {
    TaxJurisdiction.cn: CapitalGainsRateRule(
      shortTermRate: Decimal.zero,
      longTermRate: Decimal.zero,
      longTermThreshold: const Duration(days: 365),
    ),
    TaxJurisdiction.us: CapitalGainsRateRule(
      shortTermRate: _d('0.22'),
      longTermRate: _d('0.15'),
      longTermThreshold: const Duration(days: 365),
    ),
    TaxJurisdiction.hk: CapitalGainsRateRule(
      shortTermRate: Decimal.zero,
      longTermRate: Decimal.zero,
      longTermThreshold: const Duration(days: 365),
    ),
    TaxJurisdiction.other: CapitalGainsRateRule(
      shortTermRate: Decimal.zero,
      longTermRate: Decimal.zero,
      longTermThreshold: const Duration(days: 365),
    ),
  };

  final Map<DividendTaxKey, Decimal> dividendRates;
  final Map<TaxJurisdiction, CapitalGainsRateRule> capitalGainsRules;
  final int _scale;

  @override
  DividendTaxResult dividendWithholding({
    required Decimal grossAmount,
    required String currency,
    required TaxJurisdiction sourceJurisdiction,
    required TaxJurisdiction holderJurisdiction,
  }) {
    if (grossAmount.sign < 0) {
      throw ArgumentError.value(
        grossAmount,
        'grossAmount',
        'must be non-negative',
      );
    }
    final rate =
        dividendRates[DividendTaxKey(
          sourceJurisdiction,
          holderJurisdiction,
        )] ??
        Decimal.zero;
    if (grossAmount.sign == 0 || rate.sign == 0) {
      return DividendTaxResult(
        grossAmount: grossAmount,
        withholdingTax: Decimal.zero,
        netAmount: grossAmount,
        rate: rate,
        currency: currency,
      );
    }
    final tax = (grossAmount * rate).round(scale: _scale);
    final clampedTax = tax > grossAmount ? grossAmount : tax;
    return DividendTaxResult(
      grossAmount: grossAmount,
      withholdingTax: clampedTax,
      netAmount: grossAmount - clampedTax,
      rate: rate,
      currency: currency,
    );
  }

  @override
  CapitalGainsTaxResult capitalGainsTax({
    required Decimal realizedGain,
    required String currency,
    required Duration holdingPeriod,
    required TaxJurisdiction holderJurisdiction,
  }) {
    if (realizedGain.sign <= 0) {
      return CapitalGainsTaxResult.zero(
        realizedGain: realizedGain,
        currency: currency,
        holdingPeriod: holdingPeriod,
      );
    }
    final rule =
        capitalGainsRules[holderJurisdiction] ??
        capitalGainsRules[TaxJurisdiction.other]!;
    final rate = holdingPeriod >= rule.longTermThreshold
        ? rule.longTermRate
        : rule.shortTermRate;
    if (rate.sign == 0) {
      return CapitalGainsTaxResult(
        realizedGain: realizedGain,
        tax: Decimal.zero,
        rate: Decimal.zero,
        currency: currency,
        holdingPeriod: holdingPeriod,
      );
    }
    final tax = (realizedGain * rate).round(scale: _scale);
    return CapitalGainsTaxResult(
      realizedGain: realizedGain,
      tax: tax,
      rate: rate,
      currency: currency,
      holdingPeriod: holdingPeriod,
    );
  }

  static Decimal _d(String s) => Decimal.parse(s);

  static void _requireRateInRange(Decimal rate, String name) {
    if (rate.sign < 0 || rate > Decimal.one) {
      throw ArgumentError.value(rate, name, 'must be in [0, 1]');
    }
  }
}

/// `(asset jurisdiction, holder jurisdiction)` lookup key for dividend
/// withholding tables.
class DividendTaxKey {
  const DividendTaxKey(this.source, this.holder);
  final TaxJurisdiction source;
  final TaxJurisdiction holder;

  @override
  bool operator ==(Object other) =>
      other is DividendTaxKey && other.source == source && other.holder == holder;

  @override
  int get hashCode => Object.hash(source, holder);

  @override
  String toString() => '${source.name}->${holder.name}';
}

/// Capital-gains rule per holder jurisdiction. The split between short-term
/// and long-term rates is the simplest abstraction that captures the
/// US-style "long-term preferential rate" pattern; jurisdictions that don't
/// use a tenor split set both rates to the same value.
class CapitalGainsRateRule {
  const CapitalGainsRateRule({
    required this.shortTermRate,
    required this.longTermRate,
    required this.longTermThreshold,
  });

  /// Rate applied when `holdingPeriod < longTermThreshold`.
  final Decimal shortTermRate;

  /// Rate applied when `holdingPeriod >= longTermThreshold`.
  final Decimal longTermRate;

  /// Duration cutoff between short- and long-term tax treatment.
  final Duration longTermThreshold;
}
