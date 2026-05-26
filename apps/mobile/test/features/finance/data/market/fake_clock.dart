import 'package:naviwealth/features/finance/data/market/http/clock.dart';

/// Manually-advanced clock for deterministic tests of TTLs, retry backoff,
/// and rate-limit windows.
class FakeClock implements Clock {
  FakeClock([DateTime? start]) : _now = start ?? DateTime.utc(2026, 4, 28, 12);

  DateTime _now;
  Duration totalSlept = Duration.zero;

  @override
  DateTime now() => _now;

  void advance(Duration d) {
    _now = _now.add(d);
  }

  @override
  Future<void> sleep(Duration duration) async {
    totalSlept += duration;
    advance(duration);
  }
}
