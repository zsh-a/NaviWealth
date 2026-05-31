import 'package:decimal/decimal.dart';

/// Immutable monetary amount in a single currency.
///
/// All money math in the app routes through this type so that currency
/// mixing is rejected at the domain boundary rather than producing silently
/// wrong totals. Amounts are stored as [Decimal] (not [double]) — see
/// "所有金额使用 Decimal 而非 double" decision.
class Money implements Comparable<Money> {
  Money(this.amount, String currency) : currency = _normalizeCurrency(currency);

  /// Construct from an integer minor-unit-free amount (e.g. `Money.fromInt(10, 'USD')`
  /// for $10, not 10 cents).
  factory Money.fromInt(int amount, String currency) =>
      Money(Decimal.fromInt(amount), currency);

  /// Parse a decimal string. Throws [FormatException] on invalid input.
  factory Money.parse(String amount, String currency) =>
      Money(Decimal.parse(amount), currency);

  /// Zero in [currency].
  factory Money.zero(String currency) => Money(Decimal.zero, currency);

  final Decimal amount;
  final String currency;

  bool get isZero => amount == Decimal.zero;
  bool get isNegative => amount < Decimal.zero;
  bool get isPositive => amount > Decimal.zero;

  Money operator +(Money other) {
    _requireSameCurrency(other, '+');
    return Money(amount + other.amount, currency);
  }

  Money operator -(Money other) {
    _requireSameCurrency(other, '-');
    return Money(amount - other.amount, currency);
  }

  Money operator -() => Money(-amount, currency);

  /// Scale by a unitless factor (e.g. an FX rate or a quantity multiplier).
  /// Currency is preserved — use [CurrencyConverter] to change currencies.
  Money scale(Decimal factor) => Money(amount * factor, currency);

  @override
  int compareTo(Money other) {
    _requireSameCurrency(other, 'compare');
    return amount.compareTo(other.amount);
  }

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is Money && other.amount == amount && other.currency == currency;

  @override
  int get hashCode => Object.hash(amount, currency);

  @override
  String toString() => '$amount $currency';

  void _requireSameCurrency(Money other, String op) {
    if (other.currency != currency) {
      throw CurrencyMismatchError(currency, other.currency, op);
    }
  }

  static String _normalizeCurrency(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(code, 'currency', 'must not be empty');
    }
    return trimmed.toUpperCase();
  }
}

/// Thrown when a binary [Money] operation is attempted across currencies.
class CurrencyMismatchError extends StateError {
  CurrencyMismatchError(this.left, this.right, this.operation)
    : super(
        'Cannot apply "$operation" across currencies: $left vs $right. '
        'Convert via CurrencyConverter first.',
      );

  final String left;
  final String right;
  final String operation;
}
