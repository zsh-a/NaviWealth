/// Clock abstraction so the SyncEngine can be driven by a fake in tests.
///
/// Real implementations read [DateTime.now]. Tests inject deterministic
/// values so HLC arithmetic and backoff timing are reproducible.
abstract class Clock {
  const Clock();

  int nowMillis();

  DateTime now() =>
      DateTime.fromMillisecondsSinceEpoch(nowMillis(), isUtc: true);
}

class SystemClock extends Clock {
  const SystemClock();

  @override
  int nowMillis() => DateTime.now().millisecondsSinceEpoch;
}

class FixedClock extends Clock {
  FixedClock(this._now);
  int _now;

  @override
  int nowMillis() => _now;

  void set(int millis) => _now = millis;
  void advance(Duration delta) => _now += delta.inMilliseconds;
}
