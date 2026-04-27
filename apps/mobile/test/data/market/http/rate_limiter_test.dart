import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/market/http/rate_limiter.dart';

import '../fake_clock.dart';

void main() {
  group('RateLimiter', () {
    test(
      'admits up to maxRequests within the window without sleeping',
      () async {
        final clock = FakeClock();
        final limiter = RateLimiter(
          maxRequests: 3,
          window: const Duration(seconds: 60),
          clock: clock,
        );

        for (var i = 0; i < 3; i++) {
          await limiter.acquire();
        }

        expect(limiter.inFlight, 3);
        expect(clock.totalSlept, Duration.zero);
      },
    );

    test('sleeps the caller until the oldest hit ages out', () async {
      final clock = FakeClock();
      final limiter = RateLimiter(
        maxRequests: 2,
        window: const Duration(seconds: 60),
        clock: clock,
      );

      await limiter.acquire();
      clock.advance(const Duration(seconds: 10));
      await limiter.acquire();

      // Third call must wait 50s for the first hit to leave the 60s window.
      await limiter.acquire();

      expect(clock.totalSlept, const Duration(seconds: 50));
    });

    test('expired hits do not count against the budget', () async {
      final clock = FakeClock();
      final limiter = RateLimiter(
        maxRequests: 1,
        window: const Duration(seconds: 30),
        clock: clock,
      );

      await limiter.acquire();
      clock.advance(const Duration(seconds: 35));
      await limiter.acquire();

      expect(clock.totalSlept, Duration.zero);
      expect(limiter.inFlight, 1);
    });
  });
}
