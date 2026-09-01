import 'package:dio/dio.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/corporate_action_provider.dart';

import 'yfinance_corporate_actions.dart';

class YFinanceCorporateActionProvider implements CorporateActionProvider {
  YFinanceCorporateActionProvider({
    required MarketHttpClient http,
    DateTime Function()? now,
  }) : _http = http,
       _now = now ?? (() => DateTime.now().toUtc());

  final MarketHttpClient _http;
  final DateTime Function() _now;

  static const String _chartBase =
      'https://query1.finance.yahoo.com/v8/finance/chart';
  static const String _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';

  @override
  String get name => 'yfinance';

  @override
  CorporateActionProviderCapabilities get capabilities =>
      const CorporateActionProviderCapabilities(
        supportedMarkets: {AssetMarket.usStock, AssetMarket.hkStock},
        supportsRecordDate: false,
        supportsPayDate: false,
        supportsRevisions: false,
        availableOnWeb: true,
      );

  @override
  Future<CorporateActionFetchResult> fetch(
    CorporateActionFetchRequest request,
  ) async {
    if (!capabilities.supportedMarkets.contains(request.market)) {
      return CorporateActionFetchResult(
        provider: name,
        disposition: CorporateActionFetchDisposition.unsupported,
        actions: const [],
        fetchedAt: _now(),
      );
    }

    final symbol = request.symbol.trim().toUpperCase();
    if (symbol.isEmpty) {
      return CorporateActionFetchResult(
        provider: name,
        disposition: CorporateActionFetchDisposition.authoritativeEmpty,
        actions: const [],
        fetchedAt: _now(),
      );
    }

    final response = await _http.send<Map<String, dynamic>>(
      RequestOptions(
        path: '$_chartBase/${Uri.encodeComponent(symbol)}',
        method: 'GET',
        responseType: ResponseType.json,
        queryParameters: <String, Object?>{
          'interval': '1d',
          'period1': (request.from.toUtc().millisecondsSinceEpoch ~/ 1000)
              .toString(),
          'period2':
              (request.to
                          .toUtc()
                          .add(const Duration(days: 1))
                          .millisecondsSinceEpoch ~/
                      1000)
                  .toString(),
          'events': 'div,splits',
        },
        headers: const <String, Object?>{'User-Agent': _userAgent},
      ),
      endpoint: 'corporateActions',
    );
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw const ProviderResponseException(
        'chart response not an object',
        provider: 'yfinance',
      );
    }
    final currency = _currencyOf(body) ?? _defaultCurrencyFor(symbol);
    final parsed = parseYahooMarketCorporateActionsDetailed(
      responseBody: body,
      symbol: symbol,
      currency: currency,
      market: request.market,
    );
    if (!parsed.envelopeValid ||
        (parsed.actions.isEmpty && parsed.droppedRows > 0)) {
      throw ProviderResponseException(
        parsed.errorMessage ??
            'chart events contained no valid corporate-action rows',
        provider: name,
      );
    }
    return CorporateActionFetchResult(
      provider: name,
      disposition: parsed.droppedRows > 0
          ? CorporateActionFetchDisposition.partial
          : parsed.actions.isEmpty
          ? CorporateActionFetchDisposition.authoritativeEmpty
          : CorporateActionFetchDisposition.success,
      actions: parsed.actions,
      fetchedAt: _now(),
      warning: parsed.droppedRows > 0
          ? 'Dropped ${parsed.droppedRows} malformed event row(s).'
          : null,
    );
  }

  String? _currencyOf(Map<String, dynamic> body) {
    final chart = body['chart'];
    if (chart is! Map) return null;
    final results = chart['result'];
    if (results is! List || results.isEmpty) return null;
    final first = results.first;
    if (first is! Map) return null;
    final meta = first['meta'];
    if (meta is! Map) return null;
    final currency = meta['currency'];
    return currency is String ? currency.toUpperCase() : null;
  }

  String _defaultCurrencyFor(String symbol) {
    if (symbol.endsWith('.HK')) return 'HKD';
    return 'USD';
  }
}
