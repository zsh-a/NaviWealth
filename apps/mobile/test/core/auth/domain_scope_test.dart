import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';

void main() {
  group('DomainScope', () {
    test('wire round-trips through tryParse', () {
      for (final scope in DomainScope.values) {
        expect(DomainScope.tryParse(scope.wire), scope);
      }
    });

    test('tryParse returns null for unknown values', () {
      expect(DomainScope.tryParse('time'), isNull);
      expect(DomainScope.tryParse(''), isNull);
    });
  });

  group('DomainOptIns', () {
    test('financeOnly contains finance and excludes health', () {
      final opts = DomainOptIns.financeOnly;
      expect(opts.contains(DomainScope.finance), isTrue);
      expect(opts.contains(DomainScope.health), isFalse);
      expect(opts.toWire(), ['finance']);
    });

    test('finance is the seed domain — cannot be opted out', () {
      final opts = DomainOptIns.financeOnly.withScope(
        DomainScope.finance,
        enabled: false,
      );
      expect(opts.contains(DomainScope.finance), isTrue);
    });

    test('withScope adds and removes secondary domains', () {
      final on = DomainOptIns.financeOnly.withScope(
        DomainScope.health,
        enabled: true,
      );
      expect(on.contains(DomainScope.health), isTrue);
      expect(on.toWire(), <String>['finance', 'health']);

      final off = on.withScope(DomainScope.health, enabled: false);
      expect(off.contains(DomainScope.health), isFalse);
      expect(off.toWire(), <String>['finance']);
    });

    test('fromWire is tolerant of unknown values and always seeds finance', () {
      final opts = DomainOptIns.fromWire(<String>['health', 'time']);
      expect(opts.contains(DomainScope.finance), isTrue);
      expect(opts.contains(DomainScope.health), isTrue);
      expect(opts.toWire(), <String>['finance', 'health']);
    });

    test('toWire is sorted for determinism', () {
      final opts = DomainOptIns(<DomainScope>{
        DomainScope.health,
        DomainScope.finance,
      });
      expect(opts.toWire(), <String>['finance', 'health']);
    });

    test('equality is content-based', () {
      final a = DomainOptIns(<DomainScope>{
        DomainScope.finance,
        DomainScope.health,
      });
      final b = DomainOptIns(<DomainScope>{
        DomainScope.health,
        DomainScope.finance,
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
