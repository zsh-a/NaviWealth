import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/investment/domain/models/trade_fees.dart';

import '_helpers.dart';

void main() {
  group('TradeFees', () {
    test('zero fees sum to zero and report isZero', () {
      final fees = TradeFees.zero();
      expect(fees.total, Decimal.zero);
      expect(fees.isZero, isTrue);
    });

    test('total is the sum of every itemized bucket', () {
      final fees = TradeFees(
        commission: d('5'),
        stampDuty: d('1'),
        regulatory: d('0.02'),
        transferFee: d('0.50'),
        other: d('0.10'),
      );
      expect(fees.total, d('6.62'));
      expect(fees.isZero, isFalse);
    });

    test('rejects negative components', () {
      expect(
        () => TradeFees(commission: d('-1')),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => TradeFees(stampDuty: d('-0.01')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('copyWith replaces only the named buckets', () {
      final base = TradeFees(commission: d('5'), stampDuty: d('1'));
      final next = base.copyWith(stampDuty: d('2'), regulatory: d('0.5'));
      expect(next.commission, d('5'));
      expect(next.stampDuty, d('2'));
      expect(next.regulatory, d('0.5'));
      expect(next.transferFee, Decimal.zero);
    });

    test(
      'A-share sell example: commission + stamp duty + regulatory + transfer',
      () {
        // 卖出 10000 元 A 股: 佣金 0.025% (min 5), 印花税 0.05%, 监管费 0.002%,
        // 过户费 0.001%
        final fees = TradeFees(
          commission: d('5'),
          stampDuty: d('5'),
          regulatory: d('0.20'),
          transferFee: d('0.10'),
        );
        expect(fees.total, d('10.30'));
      },
    );

    test('equality is component-wise', () {
      expect(
        TradeFees(commission: d('1'), stampDuty: d('2')),
        equals(TradeFees(commission: d('1'), stampDuty: d('2'))),
      );
      expect(
        TradeFees(commission: d('1'), stampDuty: d('2')),
        isNot(equals(TradeFees(commission: d('1'), stampDuty: d('3')))),
      );
    });
  });
}
