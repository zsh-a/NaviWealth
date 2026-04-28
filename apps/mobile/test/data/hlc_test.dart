import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/hlc.dart';

void main() {
  group('Hlc', () {
    test('tick advances counter when wall is unchanged', () {
      const last = Hlc(wallMillis: 1000, counter: 3, nodeId: 'a');
      final next = Hlc.tick(lastSeen: last, nowMillis: 1000);
      expect(next.wallMillis, 1000);
      expect(next.counter, 4);
      expect(next.nodeId, 'a');
    });

    test('tick advances counter on backward wall jump', () {
      // The defining property: a clock going backward must NOT regress the
      // logical timestamp.
      const last = Hlc(wallMillis: 5000, counter: 0, nodeId: 'a');
      final next = Hlc.tick(lastSeen: last, nowMillis: 4000);
      expect(next.wallMillis, 5000);
      expect(next.counter, 1);
    });

    test('tick resets counter when wall moves forward', () {
      const last = Hlc(wallMillis: 1000, counter: 7, nodeId: 'a');
      final next = Hlc.tick(lastSeen: last, nowMillis: 2000);
      expect(next.wallMillis, 2000);
      expect(next.counter, 0);
    });

    test('merge respects max wall and bumps counter', () {
      const local = Hlc(wallMillis: 1000, counter: 2, nodeId: 'a');
      const remote = Hlc(wallMillis: 1500, counter: 9, nodeId: 'b');
      final merged = local.merge(remote, nowMillis: 800);
      expect(merged.wallMillis, 1500);
      expect(merged.counter, 10);
      expect(merged.nodeId, 'a');
    });

    test('merge ties on wall takes max(counter)+1', () {
      const local = Hlc(wallMillis: 1000, counter: 5, nodeId: 'a');
      const remote = Hlc(wallMillis: 1000, counter: 5, nodeId: 'b');
      final merged = local.merge(remote, nowMillis: 1000);
      expect(merged.wallMillis, 1000);
      expect(merged.counter, 6);
    });

    test('compareTo gives total order', () {
      const a = Hlc(wallMillis: 1000, counter: 1, nodeId: 'x');
      const b = Hlc(wallMillis: 1000, counter: 1, nodeId: 'y');
      const c = Hlc(wallMillis: 1000, counter: 2, nodeId: 'a');
      const d = Hlc(wallMillis: 2000, counter: 0, nodeId: 'a');
      final sorted = [d, c, b, a]..sort();
      expect(sorted, [a, b, c, d]);
    });

    test('round-trips through wire format', () {
      const hlc = Hlc(wallMillis: 1234567890, counter: 42, nodeId: 'dev-1');
      expect(Hlc.parse(hlc.toString()), hlc);
    });

    test('parse rejects malformed input', () {
      expect(() => Hlc.parse('not-an-hlc'), throwsFormatException);
      expect(() => Hlc.parse(':5-x'), throwsFormatException);
      expect(() => Hlc.parse('1:2-'), throwsFormatException);
    });
  });
}
