import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/market/http/clock.dart';
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';
import 'package:naviwealth/features/finance/data/market/http/rate_limiter.dart';
import 'package:naviwealth/features/finance/data/market/http/retry_policy.dart';
import 'package:naviwealth/features/finance/data/market/providers/eastmoney_corporate_action_provider.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/corporate_action_provider.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';

import '../canned_adapter.dart';

({EastmoneyCorporateActionProvider provider, CannedAdapter adapter}) _build({
  bool available = true,
}) {
  final adapter = CannedAdapter();
  final dio = Dio()..httpClientAdapter = adapter;
  final http = MarketHttpClient(
    providerName: 'eastmoney',
    rateLimiter: RateLimiter(
      maxRequests: 100,
      window: const Duration(minutes: 1),
      clock: const SystemClock(),
    ),
    dio: dio,
    retryPolicy: const RetryPolicy(maxAttempts: 1),
    clock: const SystemClock(),
  );
  return (
    provider: EastmoneyCorporateActionProvider(
      http: http,
      available: available,
      now: () => DateTime.utc(2026, 8, 20),
    ),
    adapter: adapter,
  );
}

CorporateActionFetchRequest _request() => CorporateActionFetchRequest(
  symbol: '600519',
  market: AssetMarket.cnA,
  from: DateTime.utc(2020),
  to: DateTime.utc(2030),
);

Map<String, Object?> _body({List<Object?>? data, int pages = 1}) => {
  'result': {
    'pages': pages,
    'count': data?.length ?? 0,
    'data': data ?? const <Object?>[],
  },
};

void main() {
  group('EastmoneyCorporateActionProvider', () {
    test('normalizes per-ten cash and stock ratios to per share', () async {
      final harness = _build();
      harness.adapter.enqueue(
        'RPT_SHAREBONUS_DET',
        _body(
          data: [
            {
              'SECURITY_CODE': '600519',
              'REPORT_DATE': '2025-12-31 00:00:00',
              'PLAN_NOTICE_DATE': '2026-03-30 00:00:00',
              'PRETAX_BONUS_RMB': 276.24,
              'BONUS_RATIO': 1,
              'IT_RATIO': 2,
              'BONUS_IT_RATIO': 3,
              'EQUITY_RECORD_DATE': '2026-06-18 00:00:00',
              'EX_DIVIDEND_DATE': '2026-06-19 00:00:00',
              'PAY_DATE': '2026-06-19 00:00:00',
              'ASSIGN_PROGRESS': '实施分配',
              'IMPL_PLAN_PROFILE': '10派276.24元送1股转2股',
            },
          ],
        ),
      );

      final result = await harness.provider.fetch(_request());
      expect(result.disposition, CorporateActionFetchDisposition.success);
      final action = result.actions.single;
      expect(action.cashPerShare.toString(), '27.624');
      expect(action.bonusRatio.toString(), '0.1');
      expect(action.capitalizationRatio.toString(), '0.2');
      expect(action.totalStockDistributionRatio.toString(), '0.3');
      expect(action.currency, 'CNY');
      expect(action.status, MarketCorporateActionStatus.implemented);
      expect(action.recordDate, DateTime.utc(2026, 6, 18));
      expect(action.exDate, DateTime.utc(2026, 6, 19));
      expect(action.payDate, DateTime.utc(2026, 6, 19));
      expect(
        action.identityStrength,
        MarketCorporateActionIdentityStrength.strong,
      );
    });

    test(
      'same normalized payload produces stable identity and revision',
      () async {
        final harness = _build();
        final body = _body(
          data: [
            {
              'SECURITY_CODE': '600519',
              'REPORT_DATE': '2025-12-31',
              'PRETAX_BONUS_RMB': 20,
              'EX_DIVIDEND_DATE': '2026-06-19',
              'ASSIGN_PROGRESS': '实施分配',
            },
          ],
        );
        harness.adapter
          ..enqueue('RPT_SHAREBONUS_DET', body)
          ..enqueue('RPT_SHAREBONUS_DET', body);

        final first = await harness.provider.fetch(_request());
        final second = await harness.provider.fetch(_request());
        expect(first.actions.single.id, second.actions.single.id);
        expect(
          first.actions.single.revisionHash,
          second.actions.single.revisionHash,
        );
      },
    );

    test('disabled Web adapter returns unsupported without HTTP', () async {
      final harness = _build(available: false);
      final result = await harness.provider.fetch(_request());
      expect(result.disposition, CorporateActionFetchDisposition.unsupported);
      expect(result.actions, isEmpty);
      expect(harness.adapter.calls, isEmpty);
    });

    test('null result is an authoritative empty response', () async {
      final harness = _build();
      harness.adapter.enqueue('RPT_SHAREBONUS_DET', {'result': null});
      final result = await harness.provider.fetch(_request());
      expect(
        result.disposition,
        CorporateActionFetchDisposition.authoritativeEmpty,
      );
      expect(result.actions, isEmpty);
    });
  });
}
