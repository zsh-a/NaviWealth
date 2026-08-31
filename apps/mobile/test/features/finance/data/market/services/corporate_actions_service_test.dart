import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/logging/crash_reporter.dart';
import 'package:naviwealth/features/finance/data/market/http/clock.dart';
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';
import 'package:naviwealth/features/finance/data/market/http/rate_limiter.dart';
import 'package:naviwealth/features/finance/data/market/http/retry_policy.dart';
import 'package:naviwealth/features/finance/data/market/providers/yfinance_corporate_action_provider.dart';
import 'package:naviwealth/features/finance/data/market/services/corporate_actions_service.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/corporate_action_cache.dart';
import 'package:naviwealth/features/finance/market/domain/corporate_action_provider.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';

import '../canned_adapter.dart';

const int _divTs = 1714521600; // 2024-05-01 UTC
const int _splitTs = 1659384000; // 2022-08-02 UTC

Map<String, Object?> _chartBody({
  String currency = 'USD',
  Map<String, Object?>? dividends,
  Map<String, Object?>? splits,
}) {
  final events = <String, Object?>{};
  if (dividends != null) events['dividends'] = dividends;
  if (splits != null) events['splits'] = splits;
  return <String, Object?>{
    'chart': <String, Object?>{
      'result': <Object?>[
        <String, Object?>{
          'meta': <String, Object?>{'symbol': 'AAPL', 'currency': currency},
          'events': events,
        },
      ],
    },
  };
}

({CorporateActionsService service, CannedAdapter adapter}) _build({
  DateTime? now,
  CorporateActionCache? cache,
}) {
  final adapter = CannedAdapter();
  final dio = Dio()..httpClientAdapter = adapter;
  // Disable retries so a single 500 → empty cache + log (instead of
  // looping through `RetryPolicy`'s default 3 attempts and inflating
  // test time / call count).
  final http = MarketHttpClient(
    providerName: 'yfinance',
    rateLimiter: RateLimiter(
      maxRequests: 100,
      window: const Duration(minutes: 1),
      clock: const SystemClock(),
    ),
    dio: dio,
    retryPolicy: const RetryPolicy(maxAttempts: 1),
    clock: const SystemClock(),
  );
  final service = CorporateActionsService(
    providers: [YFinanceCorporateActionProvider(http: http)],
    logger: AppLogger(
      environment: AppEnvironment.dev,
      crashReporter: const NoopCrashReporter(),
    ),
    successTtl: const Duration(hours: 12),
    cache: cache,
    errorTtl: const Duration(minutes: 15),
    now: now == null ? null : () => now,
  );
  return (service: service, adapter: adapter);
}

MarketCorporateAction _cachedDividend() => MarketCorporateAction(
  id: 'yfinance:chart:AAPL:dividend:cached',
  source: 'yfinance',
  dataset: 'chart',
  sourceKey: 'AAPL:dividend:cached',
  revisionHash: 'cached-revision',
  identityStrength: MarketCorporateActionIdentityStrength.weak,
  symbol: 'AAPL',
  market: AssetMarket.usStock,
  kind: MarketCorporateActionKind.distribution,
  status: MarketCorporateActionStatus.unknown,
  exDate: DateTime.utc(2026, 6, 15),
  currency: 'USD',
  cashPerShare: Decimal.parse('0.25'),
);

class _MemoryCache implements CorporateActionCache {
  _MemoryCache(this.result);

  CorporateActionFetchResult? result;
  int readCount = 0;
  int writeCount = 0;

  @override
  Future<void> invalidate({
    required String symbol,
    required AssetMarket market,
  }) async {
    result = null;
  }

  @override
  Future<CorporateActionFetchResult?> read({
    required String symbol,
    required AssetMarket market,
  }) async {
    readCount++;
    return result;
  }

  @override
  Future<void> write({
    required String symbol,
    required AssetMarket market,
    required CorporateActionFetchResult result,
  }) async {
    writeCount++;
  }
}

class _RecordingProvider implements CorporateActionProvider {
  CorporateActionFetchRequest? request;
  int fetchCount = 0;

  @override
  CorporateActionProviderCapabilities get capabilities =>
      const CorporateActionProviderCapabilities(
        supportedMarkets: {AssetMarket.usStock},
        supportsRecordDate: true,
        supportsPayDate: true,
        supportsRevisions: true,
        availableOnWeb: true,
      );

  @override
  String get name => 'recording';

  @override
  Future<CorporateActionFetchResult> fetch(
    CorporateActionFetchRequest request,
  ) async {
    this.request = request;
    fetchCount++;
    return CorporateActionFetchResult(
      provider: name,
      disposition: CorporateActionFetchDisposition.authoritativeEmpty,
      actions: const [],
      fetchedAt: DateTime.utc(2026, 6, 1),
    );
  }
}

void main() {
  group('CorporateActionsService', () {
    test('fetches and parses a happy-path response', () async {
      final harness = _build();
      harness.adapter.enqueue(
        '/chart/AAPL',
        _chartBody(
          dividends: <String, Object?>{
            '$_divTs': <String, Object?>{'date': _divTs, 'amount': 0.24},
          },
          splits: <String, Object?>{
            '$_splitTs': <String, Object?>{
              'date': _splitTs,
              'numerator': 4,
              'denominator': 1,
            },
          },
        ),
      );

      final out = await harness.service.getForSymbol('aapl');
      expect(out, hasLength(2));
      expect(
        out.where((e) => e.kind == MarketCorporateActionKind.distribution),
        hasLength(1),
      );
      expect(
        out.where((e) => e.kind == MarketCorporateActionKind.split),
        hasLength(1),
      );
      expect(out.first.symbol, 'AAPL', reason: 'symbol is uppercased');
    });

    test(
      'second call within TTL hits the cache (no extra HTTP request)',
      () async {
        final harness = _build();
        harness.adapter.enqueue(
          '/chart/AAPL',
          _chartBody(
            dividends: <String, Object?>{
              '$_divTs': <String, Object?>{'date': _divTs, 'amount': 0.24},
            },
          ),
        );

        await harness.service.getForSymbol('AAPL');
        await harness.service.getForSymbol('AAPL');
        // Single network call; the second resolved from cache.
        expect(harness.adapter.calls, hasLength(1));
      },
    );

    test(
      'concurrent calls for the same symbol dedupe to one HTTP fetch',
      () async {
        final harness = _build();
        harness.adapter.enqueue(
          '/chart/AAPL',
          _chartBody(
            dividends: <String, Object?>{
              '$_divTs': <String, Object?>{'date': _divTs, 'amount': 0.24},
            },
          ),
        );

        final future1 = harness.service.getForSymbol('AAPL');
        final future2 = harness.service.getForSymbol('AAPL');
        await Future.wait<List<MarketCorporateAction>>([future1, future2]);

        expect(harness.adapter.calls, hasLength(1));
      },
    );

    test('different symbols cache independently', () async {
      final harness = _build();
      harness.adapter
        ..enqueue(
          '/chart/AAPL',
          _chartBody(
            dividends: <String, Object?>{
              '$_divTs': <String, Object?>{'date': _divTs, 'amount': 0.24},
            },
          ),
        )
        ..enqueue(
          '/chart/MSFT',
          _chartBody(
            dividends: <String, Object?>{
              '$_divTs': <String, Object?>{'date': _divTs, 'amount': 0.75},
            },
          ),
        );

      final aapl = await harness.service.getForSymbol('AAPL');
      final msft = await harness.service.getForSymbol('MSFT');
      expect(aapl, hasLength(1));
      expect(msft, hasLength(1));
      expect(aapl.first.symbol, 'AAPL');
      expect(msft.first.symbol, 'MSFT');
    });

    test(
      'HTTP failure remains distinguishable and is cached briefly',
      () async {
        final harness = _build();
        harness.adapter.enqueueRaw(
          '/chart/AAPL',
          CannedResponse('server error', status: 500),
        );

        await expectLater(
          harness.service.getForSymbol('AAPL'),
          throwsA(isA<Exception>()),
        );

        // The cached failure remains an error without hammering Yahoo.
        await expectLater(
          harness.service.getForSymbol('AAPL'),
          throwsA(isA<Exception>()),
        );
        expect(harness.adapter.calls, hasLength(1));
      },
    );

    test('invalidate forces the next read to re-fetch', () async {
      final harness = _build();
      harness.adapter
        ..enqueue(
          '/chart/AAPL',
          _chartBody(
            dividends: <String, Object?>{
              '$_divTs': <String, Object?>{'date': _divTs, 'amount': 0.24},
            },
          ),
        )
        ..enqueue(
          '/chart/AAPL',
          _chartBody(
            dividends: <String, Object?>{
              '$_divTs': <String, Object?>{'date': _divTs, 'amount': 0.30},
            },
          ),
        );

      final first = await harness.service.getForSymbol('AAPL');
      await harness.service.invalidate('AAPL');
      final second = await harness.service.getForSymbol('AAPL');

      expect(harness.adapter.calls, hasLength(2));
      expect(first.first.cashPerShare.toString(), '0.24');
      expect(second.first.cashPerShare.toString(), '0.3');
    });

    test(
      'empty symbol returns empty list without hitting the network',
      () async {
        final harness = _build();
        final out = await harness.service.getForSymbol('   ');
        expect(out, isEmpty);
        expect(harness.adapter.calls, isEmpty);
      },
    );

    test('explicit range bypasses the default persistent cache', () async {
      final provider = _RecordingProvider();
      final cache = _MemoryCache(null);
      final service = CorporateActionsService(
        providers: [provider],
        logger: AppLogger(
          environment: AppEnvironment.dev,
          crashReporter: const NoopCrashReporter(),
        ),
        cache: cache,
      );
      final from = DateTime.utc(2024, 1, 1);
      final to = DateTime.utc(2026, 12, 31);

      final result = await service.fetchRange(
        CorporateActionFetchRequest(
          symbol: 'aapl',
          market: AssetMarket.usStock,
          from: from,
          to: to,
        ),
      );

      expect(
        result.disposition,
        CorporateActionFetchDisposition.authoritativeEmpty,
      );
      expect(provider.fetchCount, 1);
      expect(provider.request?.symbol, 'AAPL');
      expect(provider.request?.from, from);
      expect(provider.request?.to, to);
      expect(cache.readCount, 0);
      expect(cache.writeCount, 0);
    });

    test('fresh persistent cache avoids an HTTP request', () async {
      final now = DateTime.utc(2026, 6, 1, 12);
      final cache = _MemoryCache(
        CorporateActionFetchResult(
          provider: 'yfinance',
          disposition: CorporateActionFetchDisposition.success,
          actions: [_cachedDividend()],
          fetchedAt: now.subtract(const Duration(hours: 1)),
        ),
      );
      final harness = _build(now: now, cache: cache);

      final result = await harness.service.fetchForSymbol('AAPL');

      expect(result.disposition, CorporateActionFetchDisposition.success);
      expect(result.actions.single.cashPerShare.toString(), '0.25');
      expect(harness.adapter.calls, isEmpty);
    });

    test('expired cache becomes explicit stale fallback on failure', () async {
      final now = DateTime.utc(2026, 6, 1, 12);
      final cache = _MemoryCache(
        CorporateActionFetchResult(
          provider: 'yfinance',
          disposition: CorporateActionFetchDisposition.success,
          actions: [_cachedDividend()],
          fetchedAt: now.subtract(const Duration(days: 1)),
        ),
      );
      final harness = _build(now: now, cache: cache);
      harness.adapter.enqueueRaw(
        '/chart/AAPL',
        CannedResponse('server error', status: 500),
      );

      final result = await harness.service.fetchForSymbol('AAPL');
      final second = await harness.service.fetchForSymbol('AAPL');

      expect(result.disposition, CorporateActionFetchDisposition.stale);
      expect(result.actions, hasLength(1));
      expect(result.error, isNotNull);
      expect(result.warning, contains('cached'));
      expect(second.disposition, CorporateActionFetchDisposition.stale);
      expect(harness.adapter.calls, hasLength(1));
    });

    test('unsupported market does not call an unrelated provider', () async {
      final harness = _build();
      final result = await harness.service.fetchForSymbol('600519');
      expect(result.disposition, CorporateActionFetchDisposition.unsupported);
      expect(result.actions, isEmpty);
      expect(harness.adapter.calls, isEmpty);
    });

    test('currency falls back when yfinance omits the meta tag', () async {
      final harness = _build();
      harness.adapter.enqueue('/chart/BABA', <String, Object?>{
        'chart': <String, Object?>{
          'result': <Object?>[
            <String, Object?>{
              // No meta.currency field.
              'meta': <String, Object?>{'symbol': 'BABA'},
              'events': <String, Object?>{
                'dividends': <String, Object?>{
                  '$_divTs': <String, Object?>{'date': _divTs, 'amount': 0.10},
                },
              },
            },
          ],
        },
      });
      final out = await harness.service.getForSymbol('BABA');
      // Default fallback is USD (the comment in `_defaultCurrencyFor`).
      expect(out.single.currency, 'USD');
    });
  });
}
