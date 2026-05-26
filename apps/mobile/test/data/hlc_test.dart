import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/domain/hlc.dart';

void main() {
  group('Hlc', () {
    // SP-A-1
    test('tick advances counter when wall is unchanged', () {
      const last = Hlc(wallMillis: 1000, counter: 3, nodeId: 'a');
      final next = Hlc.tick(lastSeen: last, nowMillis: 1000);
      expect(next.wallMillis, 1000);
      expect(next.counter, 4);
      expect(next.nodeId, 'a');
    });

    // SP-A-3 / clock regression
    test('tick advances counter on backward wall jump', () {
      const last = Hlc(wallMillis: 5000, counter: 0, nodeId: 'a');
      final next = Hlc.tick(lastSeen: last, nowMillis: 4000);
      expect(next.wallMillis, 5000);
      expect(next.counter, 1);
    });

    // SP-A-2
    test('tick resets counter when wall moves forward', () {
      const last = Hlc(wallMillis: 1000, counter: 7, nodeId: 'a');
      final next = Hlc.tick(lastSeen: last, nowMillis: 2000);
      expect(next.wallMillis, 2000);
      expect(next.counter, 0);
    });

    // SP-A-5
    test('tick on counter overflow bumps wall', () {
      const last = Hlc(wallMillis: 1000, counter: Hlc.counterMax, nodeId: 'a');
      final next = Hlc.tick(lastSeen: last, nowMillis: 1000);
      expect(next.wallMillis, 1001);
      expect(next.counter, 0);
    });

    // SP-A-4
    test('merge respects max wall and bumps counter', () {
      const local = Hlc(wallMillis: 1000, counter: 3, nodeId: 'a');
      const remote = Hlc(wallMillis: 1500, counter: 7, nodeId: 'b');
      final merged = local.merge(remote, nowMillis: 1200);
      expect(merged.wallMillis, 1500);
      expect(merged.counter, 8);
      expect(merged.nodeId, 'a');
    });

    test('merge ties on wall takes max(counter)+1', () {
      const local = Hlc(wallMillis: 1000, counter: 5, nodeId: 'a');
      const remote = Hlc(wallMillis: 1000, counter: 5, nodeId: 'b');
      final merged = local.merge(remote, nowMillis: 1000);
      expect(merged.wallMillis, 1000);
      expect(merged.counter, 6);
    });

    test('merge picks now when it leads both', () {
      const local = Hlc(wallMillis: 1000, counter: 9, nodeId: 'a');
      const remote = Hlc(wallMillis: 1500, counter: 9, nodeId: 'b');
      final merged = local.merge(remote, nowMillis: 2000);
      expect(merged.wallMillis, 2000);
      expect(merged.counter, 0);
    });

    test('compareTo gives total order', () {
      const a = Hlc(wallMillis: 1000, counter: 1, nodeId: 'x');
      const b = Hlc(wallMillis: 1000, counter: 1, nodeId: 'y');
      const c = Hlc(wallMillis: 1000, counter: 2, nodeId: 'a');
      const d = Hlc(wallMillis: 2000, counter: 0, nodeId: 'a');
      final sorted = [d, c, b, a]..sort();
      expect(sorted, [a, b, c, d]);
    });

    // SP-A-6
    test('round-trips through canonical wire format', () {
      const hlc = Hlc(wallMillis: 1234567890, counter: 42, nodeId: 'dev-1');
      expect(hlc.toString(), '1234567890.002a-dev-1');
      expect(Hlc.parse(hlc.toString()), hlc);
    });

    test('serialised counter is zero-padded 4-hex', () {
      const hlc = Hlc(
        wallMillis: 1714291200000,
        counter: 1,
        nodeId: '1f5b0c3a-4e2d-4d31-9b77-3f7c1f0d2c01',
      );
      expect(
        hlc.toString(),
        '1714291200000.0001-1f5b0c3a-4e2d-4d31-9b77-3f7c1f0d2c01',
      );
    });

    // SP-A-7. Spec assumes phys_ms is a Unix-millis value (so all 13 digits
    // for the next ~250 years). Keep the fuzz inside that width so plain lex
    // ordering matches numeric ordering.
    test('lex order on serialised form matches tuple order (fuzz)', () {
      final rng = Random(42);
      const minWall = 1000000000000; // 10^12
      // Random.nextInt is capped at 2^32; combine two draws to span 13 digits.
      int randomWall() {
        final hi = rng.nextInt(9000); // 0..8999
        final lo = rng.nextInt(1000000000); // 0..1e9 - 1
        return minWall + hi * 1000000000 + lo;
      }

      const fixedNode = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      for (var i = 0; i < 1000; i++) {
        final a = Hlc(
          wallMillis: randomWall(),
          counter: rng.nextInt(Hlc.counterMax + 1),
          nodeId: fixedNode,
        );
        final b = Hlc(
          wallMillis: randomWall(),
          counter: rng.nextInt(Hlc.counterMax + 1),
          nodeId: fixedNode,
        );
        final tupleCmp = a.compareTo(b).sign;
        final lexCmp = a.toString().compareTo(b.toString()).sign;
        expect(lexCmp, tupleCmp, reason: 'a=$a b=$b');
      }
    });

    test('parse rejects malformed input', () {
      expect(() => Hlc.parse('not-an-hlc'), throwsFormatException);
      expect(() => Hlc.parse('.5-x'), throwsFormatException);
      expect(() => Hlc.parse('1.0001-'), throwsFormatException);
      // Old colon format must not parse.
      expect(() => Hlc.parse('1:2-x'), throwsFormatException);
      // Counter must be 4-hex, not arbitrary length.
      expect(() => Hlc.parse('1.1-x'), throwsFormatException);
      // Negative wall.
      expect(() => Hlc.parse('-1.0001-x'), throwsFormatException);
    });
  });
}
