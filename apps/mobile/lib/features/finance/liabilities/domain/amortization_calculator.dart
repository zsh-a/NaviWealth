import 'package:decimal/decimal.dart';

import 'package:naviwealth/features/finance/domain/models/enums.dart';

/// One row in a generated amortization schedule. The shape mirrors
/// `AmortizationEntry` in the data layer (period index, dates, principal /
/// interest split, remaining balance) but without sync metadata — these are
/// pure plan rows produced by [AmortizationCalculator] before they ever
/// touch the database.
class AmortizationRow {
  const AmortizationRow({
    required this.periodIndex,
    required this.dueDate,
    required this.principalPayment,
    required this.interestPayment,
    required this.remainingBalance,
  });

  /// 1-based period index. Period 1 is the *first* payment after the loan
  /// disburses. Drift / sync tables also use 1-based for consistency with
  /// human-readable schedules.
  final int periodIndex;
  final DateTime dueDate;
  final Decimal principalPayment;
  final Decimal interestPayment;

  /// Outstanding principal *after* this period's payment is applied.
  final Decimal remainingBalance;

  Decimal get totalPayment => principalPayment + interestPayment;
}

/// Pure-functional amortization schedule generator. Stateless and side-effect
/// free; the persistence layer wraps it to materialize rows into the
/// `amortization_entries` table once per liability.
///
/// Decimal arithmetic uses a fixed [scale] for every division so cumulative
/// rounding error doesn't drift across periods. The final period absorbs the
/// rounding residual: its principal payment is set to whatever remaining
/// balance is left, ensuring the schedule sums *exactly* to the original
/// principal.
class AmortizationCalculator {
  AmortizationCalculator({this.scale = 10});

  /// Decimal places kept on intermediate divisions. 10 covers cent-precision
  /// for principals up to a few billion without overflow risk on the Decimal
  /// implementation.
  final int scale;

  /// Generate a full amortization schedule.
  ///
  /// - [annualInterestRate] is a fraction (0.0485 == 4.85% APR), not a
  ///   percent. Zero-rate loans are supported for both methods.
  /// - [termMonths] must be > 0; the schedule has exactly that many rows.
  /// - [startDate] is the disbursement date. Period 1 is due one month
  ///   later — the conventional "first payment one month after origination"
  ///   schedule.
  List<AmortizationRow> generate({
    required Decimal principal,
    required Decimal annualInterestRate,
    required int termMonths,
    required DateTime startDate,
    required RepaymentMethod method,
  }) {
    if (principal.sign <= 0) {
      throw ArgumentError.value(principal, 'principal', 'must be positive');
    }
    if (annualInterestRate.sign < 0) {
      throw ArgumentError.value(
        annualInterestRate,
        'annualInterestRate',
        'must be non-negative',
      );
    }
    if (termMonths <= 0) {
      throw ArgumentError.value(termMonths, 'termMonths', 'must be > 0');
    }

    final monthlyRate = (annualInterestRate / Decimal.fromInt(12)).toDecimal(
      scaleOnInfinitePrecision: scale,
    );

    switch (method) {
      case RepaymentMethod.equalInstallment:
        return _equalInstallment(
          principal: principal,
          monthlyRate: monthlyRate,
          termMonths: termMonths,
          startDate: startDate,
        );
      case RepaymentMethod.equalPrincipal:
        return _equalPrincipal(
          principal: principal,
          monthlyRate: monthlyRate,
          termMonths: termMonths,
          startDate: startDate,
        );
    }
  }

  /// Equal-installment monthly payment formula:
  ///   M = P * r * (1+r)^n / ((1+r)^n - 1)
  /// degenerating to P / n when r == 0.
  ///
  /// Public so the UI can preview "your monthly payment will be X" before
  /// the user confirms the schedule.
  Decimal monthlyPaymentForEqualInstallment({
    required Decimal principal,
    required Decimal annualInterestRate,
    required int termMonths,
  }) {
    if (termMonths <= 0) {
      throw ArgumentError.value(termMonths, 'termMonths', 'must be > 0');
    }
    final monthlyRate = (annualInterestRate / Decimal.fromInt(12)).toDecimal(
      scaleOnInfinitePrecision: scale,
    );
    return _equalInstallmentPayment(principal, monthlyRate, termMonths);
  }

  Decimal _equalInstallmentPayment(
    Decimal principal,
    Decimal monthlyRate,
    int termMonths,
  ) {
    if (monthlyRate.sign == 0) {
      return (principal / Decimal.fromInt(termMonths)).toDecimal(
        scaleOnInfinitePrecision: scale,
      );
    }
    final onePlusR = Decimal.one + monthlyRate;
    final pow = _pow(onePlusR, termMonths);
    final numerator = principal * monthlyRate * pow;
    final denominator = pow - Decimal.one;
    return (numerator / denominator).toDecimal(scaleOnInfinitePrecision: scale);
  }

  List<AmortizationRow> _equalInstallment({
    required Decimal principal,
    required Decimal monthlyRate,
    required int termMonths,
    required DateTime startDate,
  }) {
    final payment = _equalInstallmentPayment(
      principal,
      monthlyRate,
      termMonths,
    );
    final rows = <AmortizationRow>[];
    var balance = principal;
    for (var i = 1; i <= termMonths; i++) {
      final interest = (balance * monthlyRate);
      Decimal principalShare;
      Decimal totalPayment;
      if (i == termMonths) {
        // Last period: pay off whatever's left so cumulative principal
        // equals the original loan exactly. Avoids a 1-cent residual on
        // long mortgages caused by intermediate scale truncation.
        principalShare = balance;
        totalPayment = principalShare + interest;
      } else {
        principalShare = payment - interest;
        totalPayment = payment;
      }
      balance = balance - principalShare;
      rows.add(
        AmortizationRow(
          periodIndex: i,
          dueDate: _addMonths(startDate, i),
          principalPayment: principalShare,
          interestPayment: totalPayment - principalShare,
          remainingBalance: balance,
        ),
      );
    }
    return rows;
  }

  List<AmortizationRow> _equalPrincipal({
    required Decimal principal,
    required Decimal monthlyRate,
    required int termMonths,
    required DateTime startDate,
  }) {
    final principalShare = (principal / Decimal.fromInt(termMonths)).toDecimal(
      scaleOnInfinitePrecision: scale,
    );
    final rows = <AmortizationRow>[];
    var balance = principal;
    for (var i = 1; i <= termMonths; i++) {
      final interest = balance * monthlyRate;
      final share = i == termMonths ? balance : principalShare;
      balance = balance - share;
      rows.add(
        AmortizationRow(
          periodIndex: i,
          dueDate: _addMonths(startDate, i),
          principalPayment: share,
          interestPayment: interest,
          remainingBalance: balance,
        ),
      );
    }
    return rows;
  }

  /// Integer power for [Decimal]. The Decimal package doesn't ship one, but
  /// amortization only needs positive integer exponents (term in months).
  Decimal _pow(Decimal base, int exponent) {
    var result = Decimal.one;
    var current = base;
    var e = exponent;
    while (e > 0) {
      if (e & 1 == 1) {
        result = (result * current);
      }
      e >>= 1;
      if (e > 0) {
        current = (current * current);
      }
    }
    return result;
  }

  /// Adds [months] calendar months to [date], clamping the day-of-month so
  /// "Jan 31 + 1 month" → "Feb 28/29" rather than overflowing into March.
  /// This matches how loan servicers actually schedule due dates. UTC-ness
  /// is preserved so callers feeding UTC origination dates get UTC due
  /// dates back.
  DateTime _addMonths(DateTime date, int months) {
    final year = date.year + (date.month - 1 + months) ~/ 12;
    final month = (date.month - 1 + months) % 12 + 1;
    final daysInTargetMonth =
        (date.isUtc
                ? DateTime.utc(year, month + 1, 0)
                : DateTime(year, month + 1, 0))
            .day;
    final day = date.day > daysInTargetMonth ? daysInTargetMonth : date.day;
    return date.isUtc
        ? DateTime.utc(
            year,
            month,
            day,
            date.hour,
            date.minute,
            date.second,
            date.millisecond,
            date.microsecond,
          )
        : DateTime(
            year,
            month,
            day,
            date.hour,
            date.minute,
            date.second,
            date.millisecond,
            date.microsecond,
          );
  }
}
