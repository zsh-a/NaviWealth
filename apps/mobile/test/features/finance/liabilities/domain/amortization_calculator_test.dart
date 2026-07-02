import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/liabilities/domain/amortization_calculator.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  final calc = AmortizationCalculator();
  final start = DateTime.utc(2026, 1, 1);

  group('AmortizationCalculator.equalInstallment', () {
    test('produces termMonths rows with non-increasing remaining balance', () {
      final rows = calc.generate(
        principal: d('1000000'),
        annualInterestRate: d('0.0485'),
        termMonths: 240,
        startDate: start,
        method: RepaymentMethod.equalInstallment,
      );

      expect(rows, hasLength(240));
      // Schedule must end at exactly zero — the final period absorbs any
      // intermediate rounding so cumulative principal == loan amount.
      expect(rows.last.remainingBalance, Decimal.zero);
      // Balance never grows.
      for (var i = 1; i < rows.length; i++) {
        expect(
          rows[i].remainingBalance <= rows[i - 1].remainingBalance,
          isTrue,
          reason: 'period $i balance regressed',
        );
      }
    });

    test('cumulative principal equals original loan exactly', () {
      final rows = calc.generate(
        principal: d('1000000'),
        annualInterestRate: d('0.0485'),
        termMonths: 240,
        startDate: start,
        method: RepaymentMethod.equalInstallment,
      );
      final sum = rows.fold<Decimal>(
        Decimal.zero,
        (s, r) => s + r.principalPayment,
      );
      expect(sum, d('1000000'));
    });

    test('total payment is constant in non-final periods', () {
      final rows = calc.generate(
        principal: d('1000000'),
        annualInterestRate: d('0.0485'),
        termMonths: 60,
        startDate: start,
        method: RepaymentMethod.equalInstallment,
      );
      final firstTotal = rows.first.totalPayment;
      // All periods *except* the last (which absorbs the residual) should
      // share the same total payment to within a cent.
      for (var i = 1; i < rows.length - 1; i++) {
        final delta = (rows[i].totalPayment - firstTotal).abs();
        expect(
          delta <= d('0.01'),
          isTrue,
          reason:
              'period ${i + 1} total ${rows[i].totalPayment} '
              'differs from first $firstTotal',
        );
      }
    });

    test('handles zero interest by spreading principal evenly', () {
      final rows = calc.generate(
        principal: d('12000'),
        annualInterestRate: Decimal.zero,
        termMonths: 12,
        startDate: start,
        method: RepaymentMethod.equalInstallment,
      );
      expect(rows.length, 12);
      for (final r in rows) {
        expect(r.principalPayment, d('1000'));
        expect(r.interestPayment, Decimal.zero);
      }
      expect(rows.last.remainingBalance, Decimal.zero);
    });

    test('monthly payment helper matches schedule rows', () {
      final mp = calc.monthlyPaymentForEqualInstallment(
        principal: d('1000000'),
        annualInterestRate: d('0.06'),
        termMonths: 360,
      );
      // Standard 30y @ 6% on 1M ≈ 5995.51; allow a 1-cent tolerance for
      // intermediate-scale rounding.
      expect((mp - d('5995.51')).abs() <= d('0.01'), isTrue);
    });
  });

  group('AmortizationCalculator.equalPrincipal', () {
    test('principal share is constant except for final-period residual', () {
      final rows = calc.generate(
        principal: d('120000'),
        annualInterestRate: d('0.05'),
        termMonths: 12,
        startDate: start,
        method: RepaymentMethod.equalPrincipal,
      );
      expect(rows, hasLength(12));
      for (var i = 0; i < rows.length - 1; i++) {
        expect(rows[i].principalPayment, d('10000'));
      }
      expect(rows.last.remainingBalance, Decimal.zero);
    });

    test('total payment is monotonically non-increasing', () {
      final rows = calc.generate(
        principal: d('500000'),
        annualInterestRate: d('0.0485'),
        termMonths: 60,
        startDate: start,
        method: RepaymentMethod.equalPrincipal,
      );
      for (var i = 1; i < rows.length; i++) {
        expect(
          rows[i].totalPayment <= rows[i - 1].totalPayment,
          isTrue,
          reason: 'period ${i + 1} total grew vs prior',
        );
      }
    });

    test('cumulative principal equals original loan exactly', () {
      final rows = calc.generate(
        principal: d('500000'),
        annualInterestRate: d('0.0485'),
        termMonths: 60,
        startDate: start,
        method: RepaymentMethod.equalPrincipal,
      );
      final sum = rows.fold<Decimal>(
        Decimal.zero,
        (s, r) => s + r.principalPayment,
      );
      expect(sum, d('500000'));
    });
  });

  group('AmortizationCalculator dueDate', () {
    test('first period is one month after origination', () {
      final rows = calc.generate(
        principal: d('1000'),
        annualInterestRate: d('0.05'),
        termMonths: 3,
        startDate: DateTime.utc(2026, 1, 15),
        method: RepaymentMethod.equalInstallment,
      );
      expect(rows[0].dueDate, DateTime.utc(2026, 2, 15));
      expect(rows[1].dueDate, DateTime.utc(2026, 3, 15));
      expect(rows[2].dueDate, DateTime.utc(2026, 4, 15));
    });

    test('clamps day of month so Jan-31 + 1 month → Feb-28/29', () {
      final rows = calc.generate(
        principal: d('1000'),
        annualInterestRate: d('0.05'),
        termMonths: 2,
        startDate: DateTime.utc(2026, 1, 31),
        method: RepaymentMethod.equalInstallment,
      );
      // 2026 is not a leap year, so Feb has 28 days.
      expect(rows[0].dueDate, DateTime.utc(2026, 2, 28));
      // Restoration of the original day-of-month on a longer month is
      // intentional: "31st of the month" should land on the 31st when the
      // calendar allows it.
      expect(rows[1].dueDate, DateTime.utc(2026, 3, 31));
    });
  });

  group('AmortizationCalculator validation', () {
    test('rejects non-positive principal', () {
      expect(
        () => calc.generate(
          principal: Decimal.zero,
          annualInterestRate: d('0.05'),
          termMonths: 12,
          startDate: start,
          method: RepaymentMethod.equalInstallment,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects zero or negative term', () {
      expect(
        () => calc.generate(
          principal: d('1000'),
          annualInterestRate: d('0.05'),
          termMonths: 0,
          startDate: start,
          method: RepaymentMethod.equalPrincipal,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects negative interest rate', () {
      expect(
        () => calc.generate(
          principal: d('1000'),
          annualInterestRate: d('-0.01'),
          termMonths: 12,
          startDate: start,
          method: RepaymentMethod.equalInstallment,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
