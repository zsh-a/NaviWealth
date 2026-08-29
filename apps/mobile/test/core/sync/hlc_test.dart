import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';

void main() {
  group('canonical string form', () {
    test('round-trips through parse', () {
      const hlc = Hlc(
        wallMillis: 1_700_000_000_000,
        counter: 0x00ff,
        nodeId: 'dev-1',
      );
      expect(Hlc.parse(hlc.toString()), hlc);
      expect(Hlc.parse(hlc.toString()).toString(), hlc.toString());
    });

    test('zero-pads the hex counter so string order matches tuple order', () {
      const a = Hlc(wallMillis: 100, counter: 0x000f, nodeId: 'dev-1');
      const b = Hlc(wallMillis: 100, counter: 0x0010, nodeId: 'dev-1');
      expect(a < b, isTrue);
      expect(a.toString().compareTo(b.toString()) < 0, isTrue);
    });

    test('rejects malformed input', () {
      expect(() => Hlc.parse(''), throwsFormatException);
      expect(() => Hlc.parse('nodelimiter'), throwsFormatException);
      expect(
        () => Hlc.parse('100.0f-dev'),
        throwsFormatException,
        reason: 'counter must be 4 hex digits',
      );
      expect(
        () => Hlc.parse('100.00ff-'),
        throwsFormatException,
        reason: 'nodeId required',
      );
      expect(
        () => Hlc.parse('-1.00ff-dev'),
        throwsFormatException,
        reason: 'wall must be non-negative',
      );
    });
  });

  group('Hlc.tick', () {
    test('advances the wall clock when it leads', () {
      const last = Hlc(wallMillis: 100, counter: 7, nodeId: 'dev-1');
      final next = Hlc.tick(lastSeen: last, nowMillis: 200);
      expect(next, const Hlc(wallMillis: 200, counter: 0, nodeId: 'dev-1'));
    });

    test('bumps the counter within the same millisecond', () {
      const last = Hlc(wallMillis: 100, counter: 7, nodeId: 'dev-1');
      final next = Hlc.tick(lastSeen: last, nowMillis: 100);
      expect(next, const Hlc(wallMillis: 100, counter: 8, nodeId: 'dev-1'));
    });

    test('carries overflow into the next millisecond', () {
      const last = Hlc(
        wallMillis: 100,
        counter: Hlc.counterMax,
        nodeId: 'dev-1',
      );
      final next = Hlc.tick(lastSeen: last, nowMillis: 100);
      expect(next, const Hlc(wallMillis: 101, counter: 0, nodeId: 'dev-1'));
    });

    test('never regresses behind a higher lastSeen wall clock', () {
      const last = Hlc(wallMillis: 500, counter: 2, nodeId: 'dev-1');
      final next = Hlc.tick(lastSeen: last, nowMillis: 100);
      expect(next >= last, isTrue);
    });
  });

  group('Hlc.merge', () {
    const local = Hlc(wallMillis: 100, counter: 5, nodeId: 'local');
    const remote = Hlc(wallMillis: 100, counter: 3, nodeId: 'remote');

    test('wall clock leads both → wall + counter 0', () {
      final merged = local.merge(remote, nowMillis: 200);
      expect(merged, const Hlc(wallMillis: 200, counter: 0, nodeId: 'local'));
    });

    test('local leads → local counter + 1', () {
      final merged = local.merge(remote, nowMillis: 100);
      expect(merged, const Hlc(wallMillis: 100, counter: 6, nodeId: 'local'));
    });

    test('remote leads → remote wall + counter + 1', () {
      const ahead = Hlc(wallMillis: 300, counter: 2, nodeId: 'remote');
      final merged = local.merge(ahead, nowMillis: 100);
      expect(merged, const Hlc(wallMillis: 300, counter: 3, nodeId: 'local'));
    });

    test('tied wall clocks → max(counter) + 1', () {
      const tiedHigher = Hlc(wallMillis: 100, counter: 9, nodeId: 'remote');
      final merged = local.merge(tiedHigher, nowMillis: 50);
      expect(merged, const Hlc(wallMillis: 100, counter: 10, nodeId: 'local'));
    });

    test('merged clock is never behind either input', () {
      final merged = local.merge(remote, nowMillis: 100);
      expect(merged > local, isTrue);
    });
  });

  group('comparison', () {
    test('nodeId is only the final tie-breaker', () {
      const a = Hlc(wallMillis: 100, counter: 1, nodeId: 'aaa');
      const b = Hlc(wallMillis: 100, counter: 1, nodeId: 'bbb');
      expect(a < b, isTrue);
      expect(a.compareTo(b), lessThan(0));
    });

    test('equality ignores nothing', () {
      const a = Hlc(wallMillis: 100, counter: 1, nodeId: 'dev-1');
      expect(a, const Hlc(wallMillis: 100, counter: 1, nodeId: 'dev-1'));
      expect(a, isNot(const Hlc(wallMillis: 100, counter: 2, nodeId: 'dev-1')));
      expect(
        a.hashCode,
        const Hlc(wallMillis: 100, counter: 1, nodeId: 'dev-1').hashCode,
      );
    });
  });
}
