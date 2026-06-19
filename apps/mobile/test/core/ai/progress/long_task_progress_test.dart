import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/progress/long_task_progress.dart';

void main() {
  final startedAt = DateTime.utc(2026, 5, 24, 10);

  group('LongTaskProgress', () {
    test('indeterminate when ratio is null or NaN', () {
      final p = LongTaskProgress(id: 't', label: 'x', startedAt: startedAt);
      expect(p.isIndeterminate, isTrue);
      expect(p.normalisedRatio, isNull);

      final pNaN = p.copyWith(ratio: double.nan);
      expect(pNaN.isIndeterminate, isTrue);
    });

    test('normalisedRatio clamps to [0, 1]', () {
      final p = LongTaskProgress(
        id: 't',
        label: 'x',
        startedAt: startedAt,
        ratio: -0.5,
      );
      expect(p.normalisedRatio, 0);
      expect(p.copyWith(ratio: 1.5).normalisedRatio, 1);
      expect(p.copyWith(ratio: 0.42).normalisedRatio, closeTo(0.42, 1e-9));
    });

    test('elapsedFrom returns Duration.zero for past `now`', () {
      final p = LongTaskProgress(id: 't', label: 'x', startedAt: startedAt);
      final earlier = startedAt.subtract(const Duration(seconds: 5));
      expect(p.elapsedFrom(earlier), Duration.zero);
    });

    test('elapsedFrom reports forward time correctly', () {
      final p = LongTaskProgress(id: 't', label: 'x', startedAt: startedAt);
      final later = startedAt.add(const Duration(milliseconds: 2500));
      expect(p.elapsedFrom(later), const Duration(milliseconds: 2500));
    });

    test('copyWith preserves id + startedAt + replaces overridden fields', () {
      final p = LongTaskProgress(
        id: 'tool_run_1',
        label: 'before',
        startedAt: startedAt,
        ratio: 0.1,
        cancelable: false,
      );
      final next = p.copyWith(label: 'after', ratio: 0.5, cancelable: true);
      expect(next.id, p.id);
      expect(next.startedAt, p.startedAt);
      expect(next.label, 'after');
      expect(next.ratio, 0.5);
      expect(next.cancelable, isTrue);
    });

    test('round-trips through JSON', () {
      final p = LongTaskProgress(
        id: 'tool:t1',
        label: 'tool',
        startedAt: startedAt,
        detail: 'get_holdings',
        ratio: 0.4,
        cancelable: true,
      );
      final decoded = LongTaskProgress.fromJson(p.toJson());
      expect(decoded, p);
      expect(decoded.normalisedRatio, 0.4);
    });

    test('equality covers every observable field', () {
      final a = LongTaskProgress(
        id: 't',
        label: 'l',
        startedAt: startedAt,
        ratio: 0.5,
        detail: 'd',
        cancelable: true,
      );
      final b = LongTaskProgress(
        id: 't',
        label: 'l',
        startedAt: startedAt,
        ratio: 0.5,
        detail: 'd',
        cancelable: true,
      );
      final differs = a.copyWith(label: 'other');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(differs)));
    });
  });
}
