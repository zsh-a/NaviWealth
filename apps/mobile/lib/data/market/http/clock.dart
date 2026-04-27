/// Pluggable wall-clock so timing-sensitive code (cache TTLs, rate limiter
/// windows, retry backoff) is testable without `Future.delayed`.
abstract class Clock {
  DateTime now();
  Future<void> sleep(Duration duration);
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();

  @override
  Future<void> sleep(Duration duration) => Future<void>.delayed(duration);
}
