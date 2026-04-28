import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/domain/values/money.dart';

void main() {
  Money m(String amount, String currency) => Money.parse(amount, currency);

  group('Money', () {
    test('normalizes currency code to uppercase', () {
      expect(Money.fromInt(10, 'usd').currency, 'USD');
      expect(Money.fromInt(10, ' eur ').currency, 'EUR');
    });

    test('rejects empty currency', () {
      expect(() => Money.fromInt(1, ''), throwsArgumentError);
      expect(() => Money.fromInt(1, '   '), throwsArgumentError);
    });

    test('equality is by amount and currency', () {
      expect(m('1.23', 'USD'), equals(m('1.23', 'usd')));
      expect(m('1.23', 'USD'), isNot(equals(m('1.23', 'EUR'))));
      expect(m('1.23', 'USD'), isNot(equals(m('1.230001', 'USD'))));
    });

    test('+ and - require same currency', () {
      final a = m('10', 'USD');
      final b = m('2.5', 'USD');
      expect(a + b, m('12.5', 'USD'));
      expect(a - b, m('7.5', 'USD'));
    });

    test('+ across currencies throws CurrencyMismatchError', () {
      expect(
        () => m('10', 'USD') + m('10', 'EUR'),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });

    test('- across currencies throws CurrencyMismatchError', () {
      expect(
        () => m('10', 'USD') - m('10', 'EUR'),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });

    test('unary minus negates amount, preserves currency', () {
      expect(-m('1.5', 'JPY'), m('-1.5', 'JPY'));
    });

    test('scale multiplies amount without changing currency', () {
      expect(m('100', 'USD').scale(Decimal.parse('1.05')), m('105.00', 'USD'));
    });

    test('comparison operators reject mismatched currencies', () {
      expect(
        () => m('1', 'USD') < m('1', 'EUR'),
        throwsA(isA<CurrencyMismatchError>()),
      );
    });

    test('comparison operators work within a currency', () {
      expect(m('1', 'USD') < m('2', 'USD'), isTrue);
      expect(m('2', 'USD') >= m('2', 'USD'), isTrue);
    });

    test('uses Decimal so 0.1 + 0.2 is exactly 0.3 (no float drift)', () {
      expect(m('0.1', 'USD') + m('0.2', 'USD'), m('0.3', 'USD'));
    });

    test('zero / sign helpers reflect amount', () {
      expect(Money.zero('USD').isZero, isTrue);
      expect(m('-1', 'USD').isNegative, isTrue);
      expect(m('1', 'USD').isPositive, isTrue);
    });
  });
}
