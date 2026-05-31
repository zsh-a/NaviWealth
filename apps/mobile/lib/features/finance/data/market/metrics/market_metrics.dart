import 'dart:async';

/// In-memory market-data observability sink.
///
/// Counts requests, cache hits/misses, and provider fallback events. Designed
/// for a single-process mobile app — there is no aggregation across devices.
/// A debug screen can subscribe to [snapshots] for a live read of hit-rate,
/// error-rate, and provider health. Backend telemetry export is out of scope
/// and can be layered on top by listening to [snapshots].
class MarketMetrics {
  MarketMetrics();

  final _requests = <String, _Counter>{};
  final _cache = <String, _Counter>{};
  final _fallbacks = <String, int>{};
  final _latencies = <String, _LatencyAcc>{};
  final _controller = StreamController<MarketMetricsSnapshot>.broadcast();

  Stream<MarketMetricsSnapshot> get snapshots => _controller.stream;

  void recordRequest({
    required String provider,
    required String endpoint,
    required bool ok,
    required Duration latency,
    String? errorType,
  }) {
    final key = '$provider|$endpoint';
    final c = _requests.putIfAbsent(key, _Counter.new);
    c.total++;
    if (ok) {
      c.ok++;
    } else {
      c.errors++;
      if (errorType != null) {
        c.errorByType[errorType] = (c.errorByType[errorType] ?? 0) + 1;
      }
    }
    final l = _latencies.putIfAbsent(key, _LatencyAcc.new);
    l.add(latency);
    _emit();
  }

  void recordCache({required String endpoint, required CacheOutcome outcome}) {
    final c = _cache.putIfAbsent(endpoint, _Counter.new);
    switch (outcome) {
      case CacheOutcome.hitFresh:
        c.ok++;
        c.total++;
      case CacheOutcome.hitStale:
        c.stale++;
        c.total++;
      case CacheOutcome.miss:
        c.errors++;
        c.total++;
    }
    _emit();
  }

  void recordFallback({
    required String fromProvider,
    required String toProvider,
  }) {
    final key = '$fromProvider→$toProvider';
    _fallbacks[key] = (_fallbacks[key] ?? 0) + 1;
    _emit();
  }

  MarketMetricsSnapshot snapshot() => MarketMetricsSnapshot._(
    requests: {for (final e in _requests.entries) e.key: e.value._copy()},
    cache: {for (final e in _cache.entries) e.key: e.value._copy()},
    fallbacks: Map.unmodifiable(_fallbacks),
    latencies: {for (final e in _latencies.entries) e.key: e.value._snapshot()},
  );

  void _emit() {
    if (!_controller.hasListener) return;
    _controller.add(snapshot());
  }

  Future<void> dispose() => _controller.close();
}

enum CacheOutcome { hitFresh, hitStale, miss }

class _Counter {
  int total = 0;
  int ok = 0;
  int errors = 0;
  int stale = 0;
  final Map<String, int> errorByType = {};

  _Counter _copy() {
    final c = _Counter()
      ..total = total
      ..ok = ok
      ..errors = errors
      ..stale = stale;
    c.errorByType.addAll(errorByType);
    return c;
  }
}

class _LatencyAcc {
  int n = 0;
  Duration sum = Duration.zero;
  Duration max = Duration.zero;

  void add(Duration d) {
    n++;
    sum += d;
    if (d > max) max = d;
  }

  LatencyStats _snapshot() => LatencyStats(
    count: n,
    avg: n == 0
        ? Duration.zero
        : Duration(microseconds: sum.inMicroseconds ~/ n),
    max: max,
  );
}

class LatencyStats {
  const LatencyStats({
    required this.count,
    required this.avg,
    required this.max,
  });
  final int count;
  final Duration avg;
  final Duration max;
}

class CounterSnapshot {
  CounterSnapshot._(_Counter c)
    : total = c.total,
      ok = c.ok,
      errors = c.errors,
      stale = c.stale,
      errorByType = Map.unmodifiable(Map.of(c.errorByType));

  final int total;
  final int ok;
  final int errors;
  final int stale;
  final Map<String, int> errorByType;

  double get successRate => total == 0 ? 0 : ok / total;
  double get errorRate => total == 0 ? 0 : errors / total;
  double get hitRate => total == 0 ? 0 : (ok + stale) / total;
}

class MarketMetricsSnapshot {
  MarketMetricsSnapshot._({
    required Map<String, _Counter> requests,
    required Map<String, _Counter> cache,
    required this.fallbacks,
    required this.latencies,
  }) : requests = {
         for (final e in requests.entries) e.key: CounterSnapshot._(e.value),
       },
       cache = {
         for (final e in cache.entries) e.key: CounterSnapshot._(e.value),
       };

  final Map<String, CounterSnapshot> requests;
  final Map<String, CounterSnapshot> cache;
  final Map<String, int> fallbacks;
  final Map<String, LatencyStats> latencies;

  /// Aggregate cache hit rate across all endpoints.
  double get overallCacheHitRate {
    var total = 0;
    var hits = 0;
    for (final c in cache.values) {
      total += c.total;
      hits += c.ok + c.stale;
    }
    return total == 0 ? 0 : hits / total;
  }

  /// Aggregate provider error rate across all endpoints.
  double get overallProviderErrorRate {
    var total = 0;
    var errors = 0;
    for (final c in requests.values) {
      total += c.total;
      errors += c.errors;
    }
    return total == 0 ? 0 : errors / total;
  }
}
