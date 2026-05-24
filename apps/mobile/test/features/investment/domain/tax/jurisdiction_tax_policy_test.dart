import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/investment/domain/tax/jurisdiction_tax_policy.dart';
import 'package:naviwealth/features/investment/domain/tax/tax_jurisdiction.dart';

import '../_helpers.dart';

void main() {
  final policy = JurisdictionTaxPolicy();

  group('JurisdictionTaxPolicy.dividendWithholding', () {
    test('US asset paid to CN holder applies treaty 10% WHT', () {
      final r = policy.dividendWithholding(
        grossAmount: d('100'),
        currency: 'USD',
        sourceJurisdiction: TaxJurisdiction.us,
        holderJurisdiction: TaxJurisdiction.cn,
      );
      expect(r.rate, d('0.10'));
      expect(r.withholdingTax, d('10'));
      expect(r.netAmount, d('90'));
      expect(r.currency, 'USD');
    });

    test('US asset paid to non-treaty holder defaults to 30%', () {
      final r = policy.dividendWithholding(
        grossAmount: d('100'),
        currency: 'USD',
        sourceJurisdiction: TaxJurisdiction.us,
        holderJurisdiction: TaxJurisdiction.other,
      );
      expect(r.rate, d('0.30'));
      expect(r.withholdingTax, d('30'));
      expect(r.netAmount, d('70'));
    });

    test('HK source has zero WHT in default table', () {
      final r = policy.dividendWithholding(
        grossAmount: d('100'),
        currency: 'HKD',
        sourceJurisdiction: TaxJurisdiction.hk,
        holderJurisdiction: TaxJurisdiction.cn,
      );
      expect(r.rate, Decimal.zero);
      expect(r.withholdingTax, Decimal.zero);
      expect(r.netAmount, d('100'));
    });

    test('zero gross short-circuits to zero tax', () {
      final r = policy.dividendWithholding(
        grossAmount: Decimal.zero,
        currency: 'USD',
        sourceJurisdiction: TaxJurisdiction.us,
        holderJurisdiction: TaxJurisdiction.cn,
      );
      expect(r.withholdingTax, Decimal.zero);
      expect(r.netAmount, Decimal.zero);
    });

    test('rejects negative gross', () {
      expect(
        () => policy.dividendWithholding(
          grossAmount: d('-1'),
          currency: 'USD',
          sourceJurisdiction: TaxJurisdiction.us,
          holderJurisdiction: TaxJurisdiction.cn,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('custom override beats the default table', () {
      final custom = JurisdictionTaxPolicy(
        dividendRates: {
          const DividendTaxKey(TaxJurisdiction.us, TaxJurisdiction.cn): d(
            '0.05',
          ),
        },
      );
      final r = custom.dividendWithholding(
        grossAmount: d('100'),
        currency: 'USD',
        sourceJurisdiction: TaxJurisdiction.us,
        holderJurisdiction: TaxJurisdiction.cn,
      );
      expect(r.rate, d('0.05'));
      expect(r.withholdingTax, d('5'));
    });
  });

  group('JurisdictionTaxPolicy.capitalGainsTax', () {
    test('CN holder pays no capital gains on individual A-share gain', () {
      final r = policy.capitalGainsTax(
        realizedGain: d('1000'),
        currency: 'CNY',
        holdingPeriod: const Duration(days: 30),
        holderJurisdiction: TaxJurisdiction.cn,
      );
      expect(r.tax, Decimal.zero);
      expect(r.rate, Decimal.zero);
    });

    test('US holder short-term gain uses short-term rate (22%)', () {
      final r = policy.capitalGainsTax(
        realizedGain: d('1000'),
        currency: 'USD',
        holdingPeriod: const Duration(days: 30),
        holderJurisdiction: TaxJurisdiction.us,
      );
      expect(r.rate, d('0.22'));
      expect(r.tax, d('220'));
    });

    test(
      'US holder long-term gain (>= 365 days) uses long-term rate (15%)',
      () {
        final r = policy.capitalGainsTax(
          realizedGain: d('1000'),
          currency: 'USD',
          holdingPeriod: const Duration(days: 365),
          holderJurisdiction: TaxJurisdiction.us,
        );
        expect(r.rate, d('0.15'));
        expect(r.tax, d('150'));
      },
    );

    test('losses incur no tax', () {
      final r = policy.capitalGainsTax(
        realizedGain: d('-500'),
        currency: 'USD',
        holdingPeriod: const Duration(days: 30),
        holderJurisdiction: TaxJurisdiction.us,
      );
      expect(r.tax, Decimal.zero);
      expect(r.rate, Decimal.zero);
    });

    test('zero gain is rate-zero', () {
      final r = policy.capitalGainsTax(
        realizedGain: Decimal.zero,
        currency: 'USD',
        holdingPeriod: const Duration(days: 30),
        holderJurisdiction: TaxJurisdiction.us,
      );
      expect(r.tax, Decimal.zero);
    });

    test('unknown jurisdiction falls back to "other" rule (zero rates)', () {
      final r = policy.capitalGainsTax(
        realizedGain: d('100'),
        currency: 'JPY',
        holdingPeriod: const Duration(days: 100),
        holderJurisdiction: TaxJurisdiction.other,
      );
      expect(r.tax, Decimal.zero);
      expect(r.rate, Decimal.zero);
    });

    test('custom rule overrides default short/long thresholds', () {
      final custom = JurisdictionTaxPolicy(
        capitalGainsRules: {
          TaxJurisdiction.cn: CapitalGainsRateRule(
            shortTermRate: Decimal.zero,
            longTermRate: Decimal.zero,
            longTermThreshold: const Duration(days: 365),
          ),
          TaxJurisdiction.us: CapitalGainsRateRule(
            shortTermRate: d('0.37'),
            longTermRate: d('0.20'),
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
        },
      );
      expect(
        custom
            .capitalGainsTax(
              realizedGain: d('1000'),
              currency: 'USD',
              holdingPeriod: const Duration(days: 10),
              holderJurisdiction: TaxJurisdiction.us,
            )
            .tax,
        d('370'),
      );
      expect(
        custom
            .capitalGainsTax(
              realizedGain: d('1000'),
              currency: 'USD',
              holdingPeriod: const Duration(days: 365),
              holderJurisdiction: TaxJurisdiction.us,
            )
            .tax,
        d('200'),
      );
    });
  });
}
