import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/charts/charts.dart';

void main() {
  group('downsampleLttb', () {
    test('returns input unchanged when target ≥ length', () {
      final pts = List.generate(50, (i) => ChartPoint(x: i.toDouble(), y: 0));
      expect(downsampleLttb(pts, 50), same(pts));
      expect(downsampleLttb(pts, 100), same(pts));
    });

    test('returns input unchanged for target < 3', () {
      final pts = List.generate(50, (i) => ChartPoint(x: i.toDouble(), y: 0));
      expect(downsampleLttb(pts, 2), same(pts));
    });

    test('preserves first and last points', () {
      final pts = List.generate(
        2000,
        (i) => ChartPoint(x: i.toDouble(), y: math.sin(i / 30)),
      );
      final out = downsampleLttb(pts, 200);
      expect(out.first, same(pts.first));
      expect(out.last, same(pts.last));
      expect(out.length, lessThanOrEqualTo(200));
    });

    test('preserves an obvious peak', () {
      // Flat line 0..0 with a single spike at index 250.
      final pts = List<ChartPoint>.generate(
        500,
        (i) => ChartPoint(x: i.toDouble(), y: i == 250 ? 100 : 0),
      );
      final out = downsampleLttb(pts, 50);
      expect(
        out.any((p) => p.y == 100),
        isTrue,
        reason: 'spike must survive downsampling',
      );
    });

    test('forwards meta from chosen original points', () {
      final pts = List<ChartPoint>.generate(
        1000,
        (i) => ChartPoint(x: i.toDouble(), y: i.toDouble(), meta: 'p$i'),
      );
      final out = downsampleLttb(pts, 100);
      // Every output point's meta should be a string of the form "p<i>" — i.e.
      // it came straight from an input point, no synthesis happened.
      for (final p in out) {
        expect(p.meta, isA<String>());
        expect((p.meta as String).startsWith('p'), isTrue);
      }
    });

    test('benchmark: 1800 → 500 stays under 5 ms', () {
      // 5y daily series.
      final pts = List<ChartPoint>.generate(
        1800,
        (i) => ChartPoint(x: i.toDouble(), y: math.sin(i / 50) * 100 + i),
      );
      final stopwatch = Stopwatch()..start();
      // Warm up + measure 10 runs.
      for (int i = 0; i < 10; i++) {
        downsampleLttb(pts, 500);
      }
      stopwatch.stop();
      final perRunMs = stopwatch.elapsedMicroseconds / 10 / 1000;
      // CI guard: 4× expected budget so transient noise doesn't flake.
      expect(
        perRunMs,
        lessThan(5.0),
        reason: 'LTTB regressed: $perRunMs ms/run',
      );
    });

    test('maybeDownsample respects enabled flag', () {
      final pts = List.generate(
        1000,
        (i) => ChartPoint(x: i.toDouble(), y: i.toDouble()),
      );
      expect(maybeDownsample(pts, target: 100, enabled: false), same(pts));
      expect(
        maybeDownsample(pts, target: 100, enabled: true).length,
        lessThanOrEqualTo(100),
      );
    });
  });
}
