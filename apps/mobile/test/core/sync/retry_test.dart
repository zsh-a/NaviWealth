import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/retry.dart';

void main() {
  group('BackoffPolicy', () {
    // SP-I-6
    test('attempts 0..3 follow ~ exponential schedule', () {
      const policy = BackoffPolicy(jitter: 0); // disable jitter for assertion
      final r = Random(0);
      expect(policy.delay(0, random: r), const Duration(seconds: 1));
      expect(policy.delay(1, random: r), const Duration(seconds: 2));
      expect(policy.delay(2, random: r), const Duration(seconds: 4));
      expect(policy.delay(3, random: r), const Duration(seconds: 8));
    });

    test('caps at 5 minutes', () {
      const policy = BackoffPolicy(jitter: 0);
      // 2^20 seconds is way past the cap.
      expect(policy.delay(20), const Duration(minutes: 5));
    });

    test('jitter stays within +/- 20%', () {
      const policy = BackoffPolicy();
      final r = Random(123);
      for (var i = 0; i < 100; i++) {
        final d = policy.delay(2, random: r);
        // Base for attempt 2 with multiplier 2 and initial 1s = 4s.
        expect(d.inMilliseconds, greaterThanOrEqualTo(3200));
        expect(d.inMilliseconds, lessThanOrEqualTo(4800));
      }
    });
  });
}
