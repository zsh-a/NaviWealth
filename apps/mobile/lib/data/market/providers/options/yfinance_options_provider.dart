import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';

import '../../../../domain/values/asset_market.dart';
import '../../../../domain/values/money.dart';
import '../../../../features/options_income/domain/option_contract.dart';
import '../../exceptions.dart';
import '../../http/market_http_client.dart';
import 'options_chain_provider.dart';

/// Yahoo Finance options-chain adapter.
///
/// Uses the same `query1.finance.yahoo.com/v7/finance/options/<symbol>`
/// endpoint as the `yfinance` (Python) library. Yahoo TOS bars commercial
/// redistribution — see `docs/market-data-providers.md`; the data is
/// consumed locally and never written to a synced table.
class YFinanceOptionsProvider implements OptionsChainProvider {
  YFinanceOptionsProvider({required MarketHttpClient http}) : _http = http;

  final MarketHttpClient _http;

  /// Per-symbol-per-expiration throttle. Maps "AAPL:2026-06-20" to its
  /// most recent successful response. The provider returns the cached
  /// payload (filtered to the requested DTE window) when called inside
  /// the [_perKeyTtl] window — design doc §4.1.
  final Map<String, _CachedChainPayload> _perKeyCache = {};
  static const Duration _perKeyTtl = Duration(minutes: 5);

  static const _base =
      'https://query1.finance.yahoo.com/v7/finance/options';

  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) NaviWealth/0.1';

  @override
  String get name => 'yfinance_options';

  @override
  Future<OptionsChainSnapshot> fetchChain(
    OptionsChainRequest request,
  ) async {
    final upper = request.underlying.toUpperCase();
    final cached = _perKeyCache[upper];
    final now = DateTime.now().toUtc();
    if (cached != null && now.difference(cached.fetchedAt) < _perKeyTtl) {
      return _projection(cached, request);
    }

    final firstResp = await _fetchOnce(upper, expirationEpoch: null);
    final expirations = firstResp.expirations;
    final picked = _pickExpirations(
      expirations: expirations,
      minDte: request.minDte,
      maxDte: request.maxDte,
      asOf: now,
    );

    final contracts = <OptionContract>[];
    final visited = <int>{};
    if (firstResp.firstExpirationEpoch != null) {
      visited.add(firstResp.firstExpirationEpoch!);
      contracts.addAll(firstResp.contracts);
    }
    for (final epoch in picked) {
      if (visited.contains(epoch)) continue;
      final extra = await _fetchOnce(upper, expirationEpoch: epoch);
      contracts.addAll(extra.contracts);
      visited.add(epoch);
    }

    final payload = _CachedChainPayload(
      currency: firstResp.currency,
      underlyingPriceRaw: firstResp.underlyingPriceRaw,
      fetchedAt: now,
      contracts: contracts,
    );
    _perKeyCache[upper] = payload;
    return _projection(payload, request);
  }

  Future<_RawChain> _fetchOnce(
    String symbol, {
    int? expirationEpoch,
  }) async {
    final response = await _http.send<Map<String, dynamic>>(
      RequestOptions(
        path: '$_base/${Uri.encodeComponent(symbol)}',
        method: 'GET',
        responseType: ResponseType.json,
        queryParameters: {
          'date': ?expirationEpoch,
        },
        headers: const {'User-Agent': _userAgent},
      ),
      endpoint: 'getOptionsChain',
    );
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw ProviderResponseException(
        'options response not an object',
        provider: name,
      );
    }
    final envelope = body['optionChain'];
    if (envelope is! Map<String, dynamic>) {
      throw ProviderResponseException(
        'optionChain envelope missing',
        provider: name,
      );
    }
    final err = envelope['error'];
    if (err is Map<String, dynamic>) {
      final code = (err['code'] as String?) ?? 'unknown';
      final desc = (err['description'] as String?) ?? '';
      if (code.toLowerCase().contains('not')) {
        throw SymbolNotFoundException('$symbol: $desc', provider: name);
      }
      throw ProviderResponseException('$code: $desc', provider: name);
    }
    final results = (envelope['result'] as List?) ?? const [];
    if (results.isEmpty) {
      throw SymbolNotFoundException(
        '$symbol returned no option chain result',
        provider: name,
      );
    }
    final result = _expectMap(results.first, 'optionChain.result[0]');
    final quote = _expectMap(result['quote'], 'quote');
    final currency =
        (quote['currency'] as String?)?.toUpperCase() ?? 'USD';
    final underlyingPriceRaw =
        (quote['regularMarketPrice'] as num?)?.toString() ??
            (quote['ask'] as num?)?.toString() ??
            (quote['bid'] as num?)?.toString();
    if (underlyingPriceRaw == null) {
      throw ProviderResponseException(
        'quote.regularMarketPrice missing for $symbol',
        provider: name,
      );
    }

    final expirations = ((result['expirationDates'] as List?) ?? const [])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList();
    final options = (result['options'] as List?) ?? const [];
    final contracts = <OptionContract>[];
    int? firstExpirationEpoch;
    if (options.isNotEmpty) {
      final expSlice = _expectMap(options.first, 'options[0]');
      final expEpoch =
          (expSlice['expirationDate'] as num?)?.toInt();
      firstExpirationEpoch = expEpoch;
      final expiration = expEpoch == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expEpoch * 1000, isUtc: true);
      if (expiration != null) {
        final calls = ((expSlice['calls'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>();
        final puts = ((expSlice['puts'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>();
        final underlyingMoney = Money.parse(underlyingPriceRaw, currency);
        for (final raw in calls) {
          final c = _normalize(
            raw: raw,
            type: OptionType.call,
            underlying: symbol,
            currency: currency,
            expiration: expiration,
            underlyingPrice: underlyingMoney,
            fetchedAt: DateTime.now().toUtc(),
          );
          if (c != null) contracts.add(c);
        }
        for (final raw in puts) {
          final c = _normalize(
            raw: raw,
            type: OptionType.put,
            underlying: symbol,
            currency: currency,
            expiration: expiration,
            underlyingPrice: underlyingMoney,
            fetchedAt: DateTime.now().toUtc(),
          );
          if (c != null) contracts.add(c);
        }
      }
    }
    return _RawChain(
      currency: currency,
      underlyingPriceRaw: underlyingPriceRaw,
      expirations: expirations,
      firstExpirationEpoch: firstExpirationEpoch,
      contracts: contracts,
    );
  }

  OptionContract? _normalize({
    required Map<String, dynamic> raw,
    required OptionType type,
    required String underlying,
    required String currency,
    required DateTime expiration,
    required Money underlyingPrice,
    required DateTime fetchedAt,
  }) {
    final symbol = raw['contractSymbol'];
    final strikeRaw = raw['strike'];
    final bidRaw = raw['bid'];
    final askRaw = raw['ask'];
    if (symbol is! String || strikeRaw is! num) return null;
    final strike = Money(_decimal(strikeRaw), currency);
    final bid = Money(_decimal(_safeNum(bidRaw)), currency);
    final ask = Money(_decimal(_safeNum(askRaw)), currency);
    final mid = _midpoint(bid: bid, ask: ask, lastFallback: raw['lastPrice']);
    final spread = _spreadPct(bid: bid.amount, ask: ask.amount, mid: mid.amount);
    final dte = expiration
        .toUtc()
        .difference(DateTime(fetchedAt.year, fetchedAt.month, fetchedAt.day))
        .inDays;
    return OptionContract(
      underlying: underlying,
      market: AssetMarket.usStock,
      optionSymbol: symbol,
      type: type,
      expiration: DateTime.utc(
        expiration.year,
        expiration.month,
        expiration.day,
      ),
      dte: dte < 0 ? 0 : dte,
      strike: strike,
      bid: bid,
      ask: ask,
      mid: mid,
      volume: (raw['volume'] as num?)?.toInt() ?? 0,
      openInterest: (raw['openInterest'] as num?)?.toInt() ?? 0,
      impliedVolatility:
          (raw['impliedVolatility'] as num?) == null
              ? null
              : _decimal(raw['impliedVolatility'] as num),
      delta: null, // yfinance does not return greeks.
      underlyingPrice: underlyingPrice,
      bidAskSpreadPct: spread,
      fetchedAt: fetchedAt,
    );
  }

  Money _midpoint({
    required Money bid,
    required Money ask,
    required Object? lastFallback,
  }) {
    final hasBid = bid.amount > Decimal.zero;
    final hasAsk = ask.amount > Decimal.zero;
    if (hasBid && hasAsk) {
      final sum = bid.amount + ask.amount;
      final midAmount =
          (sum / Decimal.fromInt(2)).toDecimal(scaleOnInfinitePrecision: 6);
      return Money(midAmount, bid.currency).rounded();
    }
    if (hasAsk) return ask;
    if (hasBid) return bid;
    if (lastFallback is num && lastFallback > 0) {
      return Money(_decimal(lastFallback), bid.currency);
    }
    return Money.zero(bid.currency);
  }

  Decimal _spreadPct({
    required Decimal bid,
    required Decimal ask,
    required Decimal mid,
  }) {
    if (mid <= Decimal.zero) return Decimal.one;
    final diff = ask - bid;
    final dec = (diff / mid).toDecimal(scaleOnInfinitePrecision: 6);
    if (dec < Decimal.zero) return Decimal.zero;
    if (dec > Decimal.one) return Decimal.one;
    return dec;
  }

  List<int> _pickExpirations({
    required List<int> expirations,
    required int minDte,
    required int maxDte,
    required DateTime asOf,
  }) {
    final today = DateTime.utc(asOf.year, asOf.month, asOf.day);
    final picked = <int>[];
    for (final epoch in expirations) {
      final exp = DateTime.fromMillisecondsSinceEpoch(
        epoch * 1000,
        isUtc: true,
      );
      final dte = DateTime.utc(exp.year, exp.month, exp.day)
          .difference(today)
          .inDays;
      if (dte < minDte || dte > maxDte) continue;
      picked.add(epoch);
    }
    return picked;
  }

  OptionsChainSnapshot _projection(
    _CachedChainPayload payload,
    OptionsChainRequest request,
  ) {
    final filtered = payload.contracts
        .where((c) => c.dte >= request.minDte && c.dte <= request.maxDte)
        .toList(growable: false);
    return OptionsChainSnapshot(
      underlying: request.underlying.toUpperCase(),
      underlyingPriceRaw: payload.underlyingPriceRaw,
      currency: payload.currency,
      contracts: filtered,
      fetchedAt: payload.fetchedAt,
    );
  }

  Map<String, dynamic> _expectMap(dynamic value, String path) {
    if (value is Map<String, dynamic>) return value;
    throw ProviderResponseException(
      '$path expected object, got ${value.runtimeType}',
      provider: name,
    );
  }

  Decimal _decimal(num value) => Decimal.parse(value.toString());

  num _safeNum(Object? value) => value is num ? value : 0;
}

class _CachedChainPayload {
  const _CachedChainPayload({
    required this.currency,
    required this.underlyingPriceRaw,
    required this.fetchedAt,
    required this.contracts,
  });

  final String currency;
  final String underlyingPriceRaw;
  final DateTime fetchedAt;
  final List<OptionContract> contracts;
}

class _RawChain {
  const _RawChain({
    required this.currency,
    required this.underlyingPriceRaw,
    required this.expirations,
    required this.firstExpirationEpoch,
    required this.contracts,
  });

  final String currency;
  final String underlyingPriceRaw;
  final List<int> expirations;
  final int? firstExpirationEpoch;
  final List<OptionContract> contracts;
}

extension on Money {
  /// Rounds the amount to 4 decimal places. yfinance returns float strike
  /// prices like `190.0000000000001`; we keep four digits for display.
  Money rounded() {
    final raw = amount;
    final rounded = Decimal.parse(raw.toStringAsFixed(4));
    return Money(rounded, currency);
  }
}
