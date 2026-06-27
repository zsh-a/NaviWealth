import 'dart:math';

/// Exponential backoff calculator (`docs/sync/sync-v2.md` §7.4).
///
/// Schedule: 1s, 2s, 4s, … capped at 5min. Reset on any successful push or
/// pull. A small jitter avoids thundering-herd when many devices sync after
/// a brief outage.
class BackoffPolicy {
  const BackoffPolicy({
    this.initial = const Duration(seconds: 1),
    this.cap = const Duration(minutes: 5),
    this.multiplier = 2.0,
    this.jitter = 0.2,
  });

  final Duration initial;
  final Duration cap;
  final double multiplier;
  final double jitter;

  /// Compute the backoff delay for [attempt] (0-based). Random instance is
  /// injected for testability.
  Duration delay(int attempt, {Random? random}) {
    if (attempt < 0) attempt = 0;
    final base = (initial.inMilliseconds * pow(multiplier, attempt))
        .clamp(0, cap.inMilliseconds.toDouble())
        .toDouble();
    final r = random ?? Random();
    final jitterMs = base * jitter * (r.nextDouble() * 2 - 1);
    final ms = (base + jitterMs).round().clamp(0, cap.inMilliseconds);
    return Duration(milliseconds: ms);
  }
}
