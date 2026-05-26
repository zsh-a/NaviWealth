import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/market/metrics/market_metrics.dart';

void main() {
  group('MarketMetrics', () {
    test('aggregates request success/error and exposes rates', () {
      final m = MarketMetrics();
      addTearDown(m.dispose);

      m.recordRequest(
        provider: 'yfinance',
        endpoint: 'getQuote',
        ok: true,
        latency: const Duration(milliseconds: 80),
      );
      m.recordRequest(
        provider: 'yfinance',
        endpoint: 'getQuote',
        ok: false,
        latency: const Duration(milliseconds: 200),
        errorType: 'NetworkException',
      );

      final snap = m.snapshot();
      final c = snap.requests['yfinance|getQuote']!;
      expect(c.total, 2);
      expect(c.ok, 1);
      expect(c.errors, 1);
      expect(c.successRate, 0.5);
      expect(c.errorByType['NetworkException'], 1);
      expect(snap.overallProviderErrorRate, 0.5);
    });

    test('cache outcomes drive hit-rate computation', () {
      final m = MarketMetrics();
      addTearDown(m.dispose);

      m.recordCache(endpoint: 'getQuote', outcome: CacheOutcome.hitFresh);
      m.recordCache(endpoint: 'getQuote', outcome: CacheOutcome.hitStale);
      m.recordCache(endpoint: 'getQuote', outcome: CacheOutcome.miss);
      m.recordCache(endpoint: 'getQuote', outcome: CacheOutcome.miss);

      final snap = m.snapshot();
      expect(snap.cache['getQuote']!.total, 4);
      expect(snap.cache['getQuote']!.hitRate, 0.5);
      expect(snap.overallCacheHitRate, 0.5);
    });

    test('records fallback transitions', () {
      final m = MarketMetrics();
      addTearDown(m.dispose);
      m.recordFallback(fromProvider: 'yfinance', toProvider: 'sina');
      m.recordFallback(fromProvider: 'yfinance', toProvider: 'sina');
      final snap = m.snapshot();
      expect(snap.fallbacks['yfinance→sina'], 2);
    });
  });
}
