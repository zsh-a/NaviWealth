import 'dart:async';
import 'dart:collection';

import 'clock.dart';

/// Sliding-window rate limiter — allows at most [maxRequests] in any
/// [window] interval. `acquire()` returns immediately if there is capacity
/// or sleeps until the oldest in-window timestamp ages out.
///
/// Why sliding window vs. token bucket: most third-party quote APIs publish
/// their limits as "N per minute" and reject *before* the next window ticks
/// over. A naive token bucket can leak a burst at the boundary; the sliding
/// window prevents that without much extra bookkeeping.
class RateLimiter {
  RateLimiter({
    required this.maxRequests,
    required this.window,
    Clock clock = const SystemClock(),
  }) : assert(maxRequests > 0),
       assert(window > Duration.zero),
       _clock = clock;

  final int maxRequests;
  final Duration window;
  final Clock _clock;
  final Queue<DateTime> _hits = Queue<DateTime>();
  Future<void>? _waiting;

  Future<void> acquire() async {
    // Serialise concurrent acquire() calls so multiple awaiters don't race
    // past a near-capacity window in the same tick.
    while (_waiting != null) {
      await _waiting;
    }
    final completer = Completer<void>();
    _waiting = completer.future;
    try {
      await _admit();
    } finally {
      completer.complete();
      _waiting = null;
    }
  }

  Future<void> _admit() async {
    while (true) {
      final now = _clock.now();
      _evictExpired(now);
      if (_hits.length < maxRequests) {
        _hits.add(now);
        return;
      }
      final oldest = _hits.first;
      final waitFor = window - now.difference(oldest);
      if (waitFor <= Duration.zero) {
        // Race: a hit just expired. Loop and re-evaluate.
        continue;
      }
      await _clock.sleep(waitFor);
    }
  }

  void _evictExpired(DateTime now) {
    while (_hits.isNotEmpty && now.difference(_hits.first) >= window) {
      _hits.removeFirst();
    }
  }

  /// Currently used slots in the window. Useful for metrics / debugging.
  int get inFlight {
    _evictExpired(_clock.now());
    return _hits.length;
  }
}
