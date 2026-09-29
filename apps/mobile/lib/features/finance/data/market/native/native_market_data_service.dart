import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/historical_bar.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/features/finance/market/domain/symbol_info.dart';

import '../cache/cache_policy.dart';
import '../exceptions.dart';
import '../http/clock.dart';
import 'market_bridge.dart';
import 'market_snapshot_cache.dart';

/// Shared Android/macOS A-share route. Other markets and metadata search retain
/// the existing service. Rust exclusively owns upstream retries and fallback.
class NativeMarketDataService implements MarketDataService {
  NativeMarketDataService({
    required this.dartMarkets,
    required this.cache,
    this.request = requestNativeMarket,
    this.clock = const SystemClock(),
    this.policy = const MarketCachePolicy(),
  });

  final MarketDataService dartMarkets;
  final MarketSnapshotCache cache;
  final MarketRequest request;
  final Clock clock;
  final MarketCachePolicy policy;
  final _pending = <String, Future<_Snapshot>>{};

  bool _isChina(String symbol, AssetMarket? market) =>
      market == AssetMarket.cnA ||
      ((market == null || market == AssetMarket.unknown) &&
          (inferAssetMarket(symbol) == AssetMarket.cnA ||
              RegExp(
                r'^(SH|SZ|BJ)\d{6}$|^\d{6}\.(SH|SS|SZ|BJ)$',
                caseSensitive: false,
              ).hasMatch(symbol.trim())));

  @override
  Future<MarketResponse<Quote>> getQuote(
    String symbol, {
    AssetMarket? market,
  }) async {
    if (!_isChina(symbol, market)) {
      return dartMarkets.getQuote(symbol, market: market);
    }
    final canonical = canonicalAShare(symbol);
    final snapshot = await _fetch({
      'operation': 'quote',
      'symbol': canonical,
    }, history: false);
    final data = _map(snapshot.value['data']);
    return _response(
      snapshot,
      Quote(
        symbol: symbol.trim().toUpperCase(),
        currency: data['currency'] as String,
        price: Decimal.parse(data['price'] as String),
        previousClose: data['previous_close'] == null
            ? null
            : Decimal.parse(data['previous_close'] as String),
        asOf: DateTime.parse(data['observed_at'] as String).toUtc(),
        exchange: canonical.split('.').last,
      ),
    );
  }

  @override
  Future<MarketResponse<List<HistoricalBar>>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
    AssetMarket? market,
  }) async {
    if (!_isChina(symbol, market)) {
      return dartMarkets.getHistorical(
        symbol,
        from: from,
        to: to,
        interval: interval,
        market: market,
      );
    }
    if (interval != BarInterval.day) {
      throw UnsupportedError('Native A-share history supports daily bars only');
    }
    final canonical = canonicalAShare(symbol);
    final snapshot = await _fetch({
      'operation': 'history',
      'symbol': canonical,
      'from': _date(from),
      'to': _date(to),
    }, history: true);
    final data = _map(snapshot.value['data']);
    final bars = (data['bars'] as List<Object?>)
        .map((value) {
          final bar = _map(value);
          return HistoricalBar(
            symbol: symbol.trim().toUpperCase(),
            // A trading-date label is not China midnight converted to UTC.
            asOf: DateTime.parse('${bar['date']}T00:00:00Z'),
            open: Decimal.parse(bar['open'] as String),
            high: Decimal.parse(bar['high'] as String),
            low: Decimal.parse(bar['low'] as String),
            close: Decimal.parse(bar['close'] as String),
            // Domain volume is integer shares. Do not round fractional data.
            volume: int.tryParse(bar['volume_shares'] as String),
          );
        })
        .toList(growable: false);
    return _response(snapshot, bars);
  }

  @override
  Future<MarketResponse<List<SymbolInfo>>> searchSymbol(
    String query, {
    AssetMarket? market,
  }) => dartMarkets.searchSymbol(query, market: market);

  Future<_Snapshot> _fetch(
    Map<String, Object?> query, {
    required bool history,
  }) {
    // Version, raw basis and canonical identity are part of the cache key.
    final key = 'native-cn:v1:raw:${jsonEncode(query)}';
    return _pending.putIfAbsent(key, () async {
      try {
        return await _load(key, query, history);
      } finally {
        final _ = _pending.remove(key);
      }
    });
  }

  Future<_Snapshot> _load(
    String key,
    Map<String, Object?> query,
    bool history,
  ) async {
    _Snapshot? cached;
    try {
      final stored = await cache.read(key);
      if (stored != null) cached = _decode(stored, query, history);
    } on Object {
      // Rebuildable cache corruption/read failure must not block a fetch.
      AppLogger.instance.w('Native market cache read failed');
    }
    final fresh = history ? policy.historyFresh : policy.quoteFresh;
    final stale = history ? policy.historyStaleWindow : policy.quoteStaleWindow;
    if (cached != null && _age(cached) <= fresh) {
      return cached.withFreshness(DataFreshness.cachedFresh);
    }
    try {
      final raw = await request(jsonEncode(query));
      final result = _decode(raw, query, history);
      try {
        await cache.write(key, raw, result.fetchedAt);
      } on Object {
        AppLogger.instance.w('Native market cache write failed');
      }
      return result;
    } on Object catch (error, stack) {
      AppLogger.instance.w(
        'Native market ${query['operation']} request failed',
        error: error is MarketDataException ? error.cause ?? error : error,
        stackTrace: stack,
      );
      if (cached != null && _age(cached) <= stale) {
        return cached.withFreshness(DataFreshness.stale);
      }
      throw NoMarketDataAvailableException(
        'Native A-share market request failed',
        cause: error,
      );
    }
  }

  Duration _age(_Snapshot value) =>
      clock.now().toUtc().difference(value.fetchedAt);

  _Snapshot _decode(String raw, Map<String, Object?> query, bool history) {
    final envelope = _map(jsonDecode(raw));
    if (envelope['version'] != 1) throw const FormatException('market version');
    if (envelope['error'] != null) {
      throw ProviderUnavailableException(
        'Native market providers failed',
        cause: envelope['error'],
      );
    }
    final value = _map(envelope['ok']);
    final data = _map(value['data']);
    final fetched = DateTime.parse(value['fetched_at'] as String).toUtc();
    if (data['symbol'] != query['symbol'] ||
        value['freshness'] != 'network' ||
        (value['source'] as String).isEmpty ||
        fetched.isAfter(clock.now().toUtc().add(const Duration(minutes: 5)))) {
      throw const FormatException('invalid market identity or freshness');
    }
    if (history) {
      final coverage = _map(data['coverage']);
      if (data['adjustment'] != 'raw' ||
          coverage['boundary_check_passed'] != true ||
          coverage['requested_from'] != query['from'] ||
          coverage['requested_to'] != query['to']) {
        throw const FormatException('incompatible history basis or coverage');
      }
      String? previous;
      final bars = data['bars'] as List<Object?>;
      if (bars.isEmpty) throw const FormatException('empty history');
      for (final entry in bars) {
        final bar = _map(entry);
        final date = bar['date'] as String;
        DateTime.parse('${date}T00:00:00Z');
        if (date.compareTo(query['from'] as String) < 0 ||
            date.compareTo(query['to'] as String) > 0 ||
            (previous != null && date.compareTo(previous) <= 0)) {
          throw const FormatException('invalid history dates');
        }
        previous = date;
        final open = Decimal.parse(bar['open'] as String);
        final high = Decimal.parse(bar['high'] as String);
        final low = Decimal.parse(bar['low'] as String);
        final close = Decimal.parse(bar['close'] as String);
        final volume = Decimal.parse(bar['volume_shares'] as String);
        if (low <= Decimal.zero ||
            high < low ||
            open < low ||
            open > high ||
            close < low ||
            close > high ||
            volume < Decimal.zero) {
          throw const FormatException('invalid history prices');
        }
      }
    } else {
      if (data['currency'] != 'CNY' ||
          Decimal.parse(data['price'] as String) <= Decimal.zero) {
        throw const FormatException('invalid quote');
      }
      DateTime.parse(data['observed_at'] as String);
      if (data['previous_close'] != null) {
        Decimal.parse(data['previous_close'] as String);
      }
    }
    return _Snapshot(value, fetched, DataFreshness.live);
  }

  MarketResponse<T> _response<T>(_Snapshot snapshot, T data) {
    final payload = _map(snapshot.value['data']);
    return MarketResponse(
      data: data,
      source: snapshot.value['source'] as String,
      fetchedAt: snapshot.fetchedAt,
      freshness: snapshot.freshness,
      diagnostics: {
        'canonical_symbol': payload['symbol'],
        'warnings': snapshot.value['warnings'],
        'attempts': snapshot.value['attempts'],
        if (payload.containsKey('coverage')) 'coverage': payload['coverage'],
        if (payload.containsKey('adjustment'))
          'adjustment': payload['adjustment'],
        if (payload.containsKey('previous_close_only'))
          'previous_close_only': payload['previous_close_only'],
      },
    );
  }
}

class _Snapshot {
  const _Snapshot(this.value, this.fetchedAt, this.freshness);
  final Map<String, Object?> value;
  final DateTime fetchedAt;
  final DataFreshness freshness;
  _Snapshot withFreshness(DataFreshness freshness) =>
      _Snapshot(value, fetchedAt, freshness);
}

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map<Object?, Object?>);

String _date(DateTime value) =>
    value.toUtc().toIso8601String().substring(0, 10);

/// Mirrors SDK identity grammar; never rewrites user asset/ledger identifiers.
String canonicalAShare(String symbol) {
  final s = symbol.trim().toUpperCase();
  final suffix = RegExp(r'^(\d{6})\.(SH|SS|SZ|BJ)$').firstMatch(s);
  if (suffix != null) {
    return '${suffix[1]}.${suffix[2] == 'SS' ? 'SH' : suffix[2]}';
  }
  final prefix = RegExp(r'^(SH|SZ|BJ)(\d{6})$').firstMatch(s);
  if (prefix != null) return '${prefix[2]}.${prefix[1]}';
  if (RegExp(r'^\d{6}$').hasMatch(s)) {
    if (s.startsWith('5') || s.startsWith('6')) return '$s.SH';
    if (s.startsWith('0') || s.startsWith('1') || s.startsWith('3')) {
      return '$s.SZ';
    }
    if (s.startsWith('4') || s.startsWith('8') || s.startsWith('920')) {
      return '$s.BJ';
    }
  }
  throw SymbolNotFoundException('Invalid A-share identifier: $symbol');
}
