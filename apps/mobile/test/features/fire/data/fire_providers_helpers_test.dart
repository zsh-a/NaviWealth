import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/cashflow/domain/cash_flow_kind.dart';
import 'package:naviwealth/features/fire/data/fire_providers.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';

CashFlowBucket _bucket({
  required String key,
  required CashFlowKind kind,
  required String amount,
  String currency = 'CNY',
}) {
  return CashFlowBucket(
    key: key,
    kind: kind,
    currency: currency,
    totalInBase: Money(Decimal.parse(amount), currency),
    originalTotal: Money(Decimal.parse(amount), currency),
    count: 1,
  );
}

void main() {
  final fixedNow = DateTime.utc(2026, 5, 20);

  group('trailingAnnualSpend', () {
    test('returns null when fewer than three months of expense data', () {
      final summary = CashFlowSummary(
        period: CashFlowPeriod.month,
        baseCurrency: 'CNY',
        buckets: [
          _bucket(key: '2026-04', kind: CashFlowKind.expense, amount: '-4000'),
        ],
        totalInBase: Money(Decimal.parse('-4000'), 'CNY'),
      );
      expect(trailingAnnualSpend(summary, now: fixedNow), isNull);
    });

    test('annualises by observed months when partial data', () {
      // Three months of expense data (2026-03/04/05) totalling 18_000.
      // Annualised: 18_000 / 3 × 12 = 72_000.
      final summary = CashFlowSummary(
        period: CashFlowPeriod.month,
        baseCurrency: 'CNY',
        buckets: [
          _bucket(key: '2026-03', kind: CashFlowKind.expense, amount: '-6000'),
          _bucket(key: '2026-04', kind: CashFlowKind.expense, amount: '-7000'),
          _bucket(key: '2026-05', kind: CashFlowKind.expense, amount: '-5000'),
        ],
        totalInBase: Money(Decimal.parse('-18000'), 'CNY'),
      );
      final annual = trailingAnnualSpend(summary, now: fixedNow);
      expect(annual, isNotNull);
      expect(annual!.amount, Decimal.parse('72000'));
      expect(annual.currency, 'CNY');
    });

    test('skips buckets outside the 12-month window', () {
      // 2024-05 is 24 months ago — outside the trailing window.
      final summary = CashFlowSummary(
        period: CashFlowPeriod.month,
        baseCurrency: 'CNY',
        buckets: [
          _bucket(key: '2024-05', kind: CashFlowKind.expense, amount: '-50000'),
          _bucket(key: '2026-03', kind: CashFlowKind.expense, amount: '-4000'),
          _bucket(key: '2026-04', kind: CashFlowKind.expense, amount: '-4000'),
          _bucket(key: '2026-05', kind: CashFlowKind.expense, amount: '-4000'),
        ],
        totalInBase: Money(Decimal.parse('-62000'), 'CNY'),
      );
      final annual = trailingAnnualSpend(summary, now: fixedNow);
      expect(annual!.amount, Decimal.parse('48000'));
    });

    test('ignores non-expense buckets', () {
      final summary = CashFlowSummary(
        period: CashFlowPeriod.month,
        baseCurrency: 'CNY',
        buckets: [
          _bucket(key: '2026-03', kind: CashFlowKind.salary, amount: '20000'),
          _bucket(key: '2026-04', kind: CashFlowKind.dividend, amount: '1500'),
          _bucket(key: '2026-05', kind: CashFlowKind.expense, amount: '-4000'),
        ],
        totalInBase: Money(Decimal.parse('17500'), 'CNY'),
      );
      // Only one expense month → below the threshold.
      expect(trailingAnnualSpend(summary, now: fixedNow), isNull);
    });
  });

  group('computeInvestableAssets / computeLiquidAssets', () {
    DashboardSnapshot snapshot({
      List<CategoryAllocation> allocations = const [],
    }) {
      return DashboardSnapshot(
        asOf: fixedNow,
        baseCurrency: 'CNY',
        allocations: allocations,
        totalAssets: Money.zero('CNY'),
        totalLiabilities: Money.zero('CNY'),
        netWorth: Money.zero('CNY'),
      );
    }

    CategoryAllocation alloc(AssetCategory cat, String total) {
      return CategoryAllocation(
        category: cat,
        totalInBase: Money(Decimal.parse(total), 'CNY'),
        items: const [],
      );
    }

    test(
      'investable sums financial sleeves but skips real estate / vehicle',
      () {
        final s = snapshot(
          allocations: [
            alloc(AssetCategory.cash, '20000'),
            alloc(AssetCategory.stock, '300000'),
            alloc(AssetCategory.etf, '150000'),
            alloc(AssetCategory.bondsAndFunds, '50000'),
            alloc(AssetCategory.crypto, '10000'),
            alloc(AssetCategory.realEstate, '2000000'),
            alloc(AssetCategory.vehicle, '120000'),
            alloc(AssetCategory.liability, '500000'),
          ],
        );
        expect(
          computeInvestableAssets(s),
          Money(Decimal.parse('530000'), 'CNY'),
        );
      },
    );

    test('liquid is exactly the cash slice', () {
      final s = snapshot(
        allocations: [
          alloc(AssetCategory.cash, '20000'),
          alloc(AssetCategory.bondsAndFunds, '50000'),
        ],
      );
      expect(computeLiquidAssets(s), Money(Decimal.parse('20000'), 'CNY'));
    });

    test('empty snapshot returns zero', () {
      final s = snapshot();
      expect(computeInvestableAssets(s), Money.zero('CNY'));
      expect(computeLiquidAssets(s), Money.zero('CNY'));
    });
  });
}
