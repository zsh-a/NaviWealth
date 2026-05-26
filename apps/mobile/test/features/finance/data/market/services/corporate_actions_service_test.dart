import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/logging/crash_reporter.dart';
import 'package:naviwealth/features/finance/data/market/http/clock.dart';
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';
import 'package:naviwealth/features/finance/data/market/http/rate_limiter.dart';
import 'package:naviwealth/features/finance/data/market/http/retry_policy.dart';
import 'package:naviwealth/features/finance/data/market/services/corporate_actions_service.dart';
import 'package:naviwealth/features/investment/domain/reporting/event_timeline.dart';

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
    http: http,
    logger: AppLogger(
      environment: AppEnvironment.dev,
      crashReporter: const NoopCrashReporter(),
    ),
    successTtl: const Duration(hours: 12),
    errorTtl: const Duration(minutes: 15),
    now: now == null ? null : () => now,
  );
  return (service: service, adapter: adapter);
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
        out.where((e) => e.kind == CorporateActionKind.cashDividend),
        hasLength(1),
      );
      expect(
        out.where((e) => e.kind == CorporateActionKind.split),
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
        await Future.wait<List<CorporateActionEvent>>([future1, future2]);

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
      'HTTP failure returns empty list and caches the error briefly',
      () async {
        final harness = _build();
        harness.adapter.enqueueRaw(
          '/chart/AAPL',
          CannedResponse('server error', status: 500),
        );

        final out = await harness.service.getForSymbol('AAPL');
        expect(out, isEmpty);

        // Second read within the error TTL should not re-fetch — the
        // service caches the failure so it doesn't hammer Yahoo on
        // transient outages.
        final again = await harness.service.getForSymbol('AAPL');
        expect(again, isEmpty);
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
      harness.service.invalidate('AAPL');
      final second = await harness.service.getForSymbol('AAPL');

      expect(harness.adapter.calls, hasLength(2));
      expect(first.first.cashAmount.toString(), '0.24');
      expect(second.first.cashAmount.toString(), '0.3');
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
