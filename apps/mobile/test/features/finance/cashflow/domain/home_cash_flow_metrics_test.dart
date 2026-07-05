import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_kind.dart';
import 'package:naviwealth/features/finance/cashflow/domain/home_cash_flow_metrics.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';

void main() {
  group('passiveIncomeHomeMetrics', () {
    test(
      'uses dividend, interest, and other income from the monthly summary',
      () {
        final metrics = passiveIncomeHomeMetrics(
          _summary([
            _bucket('2026-05', CashFlowKind.dividend, '10'),
            _bucket('2026-04', CashFlowKind.interest, '5'),
            _bucket('2025-06', CashFlowKind.otherIncome, '2'),
            _bucket('2026-05', CashFlowKind.salary, '1000'),
            _bucket('2025-05', CashFlowKind.dividend, '4'),
          ]),
          now: DateTime.utc(2026, 5, 17),
        );

        expect(metrics.totalTtm.amount, d('17'));
        expect(metrics.previousTtm.amount, d('4'));
        expect(metrics.monthlyTotals, hasLength(12));
        expect(metrics.monthlyTotals.last.amount, d('10'));
        expect(metrics.changeRatio, closeTo(3.25, 0.000001));
      },
    );

    test('empty state does not report data', () {
      final metrics = passiveIncomeHomeMetrics(
        _summary([]),
        now: DateTime.utc(2026, 5, 17),
      );

      expect(metrics.hasData, isFalse);
      expect(metrics.changeRatio, isNull);
    });
  });

  group('monthlyCashFlowHomeMetrics', () {
    test(
      'derives current-month inflow, outflow, net, and 3-month baseline',
      () {
        final metrics = monthlyCashFlowHomeMetrics(
          _summary([
            _bucket('2026-05', CashFlowKind.salary, '5000'),
            _bucket('2026-05', CashFlowKind.dividend, '50'),
            _bucket('2026-05', CashFlowKind.expense, '-1800'),
            _bucket('2026-05', CashFlowKind.transfer, '999'),
            _bucket('2026-04', CashFlowKind.salary, '3000'),
            _bucket('2026-04', CashFlowKind.expense, '-1000'),
            _bucket('2026-03', CashFlowKind.expense, '-500'),
            _bucket('2026-02', CashFlowKind.salary, '1000'),
          ]),
          now: DateTime.utc(2026, 5, 17),
        );

        expect(metrics.monthKey, '2026-05');
        expect(metrics.inflow.amount, d('5050'));
        expect(metrics.outflow.amount, d('1800'));
        expect(metrics.net.amount, d('3250'));
        expect(metrics.trailingAverageNet.amount, d('833.333333'));
        expect(metrics.hasData, isTrue);
      },
    );
  });
}

CashFlowSummary _summary(List<CashFlowBucket> buckets) {
  return CashFlowSummary(
    period: CashFlowPeriod.month,
    baseCurrency: 'CNY',
    buckets: buckets,
    totalInBase: Money.zero('CNY'),
  );
}

CashFlowBucket _bucket(String key, CashFlowKind kind, String amount) {
  return CashFlowBucket(
    key: key,
    kind: kind,
    currency: 'CNY',
    totalInBase: Money(d(amount), 'CNY'),
    originalTotal: Money(d(amount), 'CNY'),
    count: 1,
  );
}

Decimal d(String value) => Decimal.parse(value);
