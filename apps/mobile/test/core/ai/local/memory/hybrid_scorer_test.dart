import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/local/memory/hybrid_scorer.dart';

void main() {
  group('hybridScore', () {
    test('weights sum to 1.0', () {
      const sum = kWeightSemantic +
          kWeightImportance +
          kWeightEntity +
          kWeightRecency +
          kWeightConfidence;
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('all-max inputs produce 1.0', () {
      final s = hybridScore(
        semanticSim: 1.0,
        importance: 1.0,
        entityOverlap: 1.0,
        recency: 1.0,
        confidence: 1.0,
      );
      expect(s, closeTo(1.0, 1e-9));
    });

    test('all-zero inputs produce 0.0', () {
      final s = hybridScore(
        semanticSim: 0.0,
        importance: 0.0,
        entityOverlap: 0.0,
        recency: 0.0,
        confidence: 0.0,
      );
      expect(s, 0.0);
    });

    test('null semantic clamps to 0 contribution (other weights still rank)',
        () {
      final withNull = hybridScore(
        semanticSim: null,
        importance: 1.0,
        entityOverlap: 1.0,
        recency: 1.0,
        confidence: 1.0,
      );
      // 1 - 0.35 = 0.65 expected.
      expect(withNull, closeTo(0.65, 1e-9));
    });

    test('out-of-range inputs are clamped to [0, 1]', () {
      final low = hybridScore(
        semanticSim: -0.5,
        importance: -1,
        entityOverlap: -2,
        recency: -1,
        confidence: -1,
      );
      expect(low, 0.0);
      final high = hybridScore(
        semanticSim: 5,
        importance: 5,
        entityOverlap: 5,
        recency: 5,
        confidence: 5,
      );
      expect(high, closeTo(1.0, 1e-9));
    });

    test('semantic-only contribution equals 0.35', () {
      final s = hybridScore(
        semanticSim: 1.0,
        importance: 0,
        entityOverlap: 0,
        recency: 0,
        confidence: 0,
      );
      expect(s, closeTo(0.35, 1e-9));
    });
  });

  group('entityOverlap (Jaccard)', () {
    test('identical sets → 1', () {
      expect(entityOverlap({'NVDA', 'put'}, {'NVDA', 'put'}), 1.0);
    });

    test('disjoint sets → 0', () {
      expect(entityOverlap({'NVDA'}, {'AAPL'}), 0.0);
    });

    test('partial overlap → fraction', () {
      // |{NVDA}| / |{NVDA, put, AAPL}| = 1/3
      final v = entityOverlap({'NVDA', 'put'}, {'NVDA', 'AAPL'});
      expect(v, closeTo(1 / 3, 1e-9));
    });

    test('empty side → 0', () {
      expect(entityOverlap(const {}, {'NVDA'}), 0.0);
      expect(entityOverlap({'NVDA'}, const {}), 0.0);
    });
  });

  group('recencyScore (half-life decay)', () {
    final now = DateTime.utc(2026, 5, 24);

    test('now → 1.0', () {
      expect(recencyScore(now, now), closeTo(1.0, 1e-9));
    });

    test('one half-life ago → ~0.5', () {
      final past = now.subtract(const Duration(days: 30));
      expect(recencyScore(past, now), closeTo(0.5, 1e-3));
    });

    test('two half-lives ago → ~0.25', () {
      final past = now.subtract(const Duration(days: 60));
      expect(recencyScore(past, now), closeTo(0.25, 1e-3));
    });

    test('future timestamps clamp to 1.0', () {
      final future = now.add(const Duration(days: 1));
      expect(recencyScore(future, now), 1.0);
    });

    test('custom half-life respected', () {
      final past = now.subtract(const Duration(days: 7));
      final score = recencyScore(past, now,
          halfLife: const Duration(days: 7));
      expect(score, closeTo(0.5, 1e-3));
    });
  });
}
