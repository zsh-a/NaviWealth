import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';

import 'package:naviwealth/domain/entities/historical_bar.dart';
import 'package:naviwealth/domain/entities/quote.dart';
import 'package:naviwealth/domain/entities/symbol_info.dart';
import 'package:naviwealth/domain/values/asset_market.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';
import 'market_provider.dart';

/// Sina (新浪财经) A-share quote adapter via the public hq endpoint.
///
/// Endpoint shape: `https://hq.sinajs.cn/list=sh000001,sz000001`
/// Response: GBK-encoded `var hq_str_sh000001="..."` lines, comma-separated.
///
/// We accept both forms of input:
///   * Already prefixed: `sh600519`, `sz000001`, `bj430047`
///   * Unprefixed code: `600519` → routed to `sh`; `000001` / `300xxx` → `sz`
///
/// Historical bars and search are NOT supported by this endpoint — see
/// the fallback story (Tushare day-line / AKShare). This
/// adapter throws [UnsupportedError] on those paths and the composite
/// service falls through to the next provider in the chain.
class SinaProvider implements MarketProvider {
  SinaProvider({required MarketHttpClient http}) : _http = http;

  final MarketHttpClient _http;

  static const _base = 'https://hq.sinajs.cn/list';

  @override
  String get name => 'sina';

  @override
  Set<AssetMarket> get supportedMarkets => const {AssetMarket.cnA};

  @override
  Future<Quote> getQuote(String symbol) async {
    final code = _normalizeCode(symbol);
    final response = await _http.send<List<int>>(
      RequestOptions(
        path: '$_base=$code',
        method: 'GET',
        // Sina returns GBK-encoded text; we ask Dio for raw bytes and parse
        // only the ASCII-safe numeric fields. The Chinese stock name is left
        // as-is in `_raw` and ignored — symbol search is out of scope here.
        responseType: ResponseType.bytes,
        // Sina rejects requests without this Referer.
        headers: const {
          'Referer': 'https://finance.sina.com.cn/',
          'User-Agent': _userAgent,
        },
      ),
      endpoint: 'getQuote',
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw ProviderResponseException('empty body', provider: name);
    }
    final text = String.fromCharCodes(bytes);
    return _parseLine(text, code);
  }

  @override
  Future<List<HistoricalBar>> getHistorical(
    String symbol, {
    required DateTime from,
    required DateTime to,
    BarInterval interval = BarInterval.day,
  }) {
    throw UnsupportedError(
      'sina hq endpoint does not expose historical bars; '
      'route this provider chain through Tushare/AKShare for history',
    );
  }

  @override
  Future<List<SymbolInfo>> searchSymbol(String query) {
    throw UnsupportedError('sina hq endpoint does not expose symbol search');
  }

  Quote _parseLine(String text, String code) {
    // Format: var hq_str_sh600519="贵州茅台,1500.00,1499.00,1510.00,...";
    final eq = text.indexOf('"');
    final endQuote = text.lastIndexOf('"');
    if (eq < 0 || endQuote <= eq) {
      throw ProviderResponseException(
        'malformed line: ${_truncate(text)}',
        provider: name,
      );
    }
    final payload = text.substring(eq + 1, endQuote);
    if (payload.isEmpty) {
      throw SymbolNotFoundException(code, provider: name);
    }
    final fields = payload.split(',');
    if (fields.length < 32) {
      throw ProviderResponseException(
        'unexpected field count ${fields.length} for $code',
        provider: name,
      );
    }
    // Sina A-share schema (selected indices used here):
    //  0: name (GBK)
    //  1: open    2: previous close   3: current price
    //  4: day high   5: day low
    //  8: volume (shares)
    // 30: date (YYYY-MM-DD)
    // 31: time (HH:MM:SS)
    final price = _decimal(fields[3]);
    if (price == Decimal.zero) {
      // Sina returns all zeros before the market opens for the day. Surface
      // the previous close as the price so UI does not flicker to "0".
      final prev = _decimal(fields[2]);
      if (prev != Decimal.zero) {
        return Quote(
          symbol: code.toUpperCase(),
          currency: 'CNY',
          price: prev,
          previousClose: prev,
          asOf: _parseAsOf(fields[30], fields[31]),
          exchange: _exchangeFromCode(code),
        );
      }
    }
    return Quote(
      symbol: code.toUpperCase(),
      currency: 'CNY',
      price: price,
      previousClose: _decimal(fields[2]),
      open: _decimal(fields[1]),
      dayHigh: _decimal(fields[4]),
      dayLow: _decimal(fields[5]),
      volume: int.tryParse(fields[8]),
      asOf: _parseAsOf(fields[30], fields[31]),
      exchange: _exchangeFromCode(code),
    );
  }

  String _exchangeFromCode(String code) {
    final prefix = code.length >= 2 ? code.substring(0, 2).toLowerCase() : '';
    switch (prefix) {
      case 'sh':
        return 'SSE';
      case 'sz':
        return 'SZSE';
      case 'bj':
        return 'BSE';
      default:
        return 'CN';
    }
  }

  DateTime _parseAsOf(String date, String time) {
    final d = DateTime.tryParse('${date}T$time');
    if (d == null) return DateTime.now().toUtc();
    // Sina returns Asia/Shanghai (UTC+8). Without zoneinfo on Flutter we apply
    // a fixed offset — A-share market hours never cross DST boundaries, so the
    // shift is exact.
    return d.subtract(const Duration(hours: 8)).toUtc();
  }

  Decimal _decimal(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return Decimal.zero;
    return Decimal.tryParse(t) ?? Decimal.zero;
  }

  /// Accepts `sh600519`, `SZ000001`, `600519`, `000001` and normalises to a
  /// lower-case `sh600519` form. Throws if the digits look invalid.
  String _normalizeCode(String input) {
    final s = input.trim().toLowerCase();
    if (s.isEmpty) {
      throw const SymbolNotFoundException('empty symbol', provider: 'sina');
    }
    if (RegExp(r'^(sh|sz|bj)\d{6}$').hasMatch(s)) return s;
    if (RegExp(r'^\d{6}$').hasMatch(s)) {
      final first = s[0];
      if (first == '6') return 'sh$s';
      if (first == '0' || first == '3') return 'sz$s';
      if (first == '4' || first == '8') return 'bj$s';
    }
    throw ProviderResponseException(
      'unrecognised A-share code: $input',
      provider: name,
    );
  }

  String _truncate(String s) => s.length > 60 ? '${s.substring(0, 60)}…' : s;

  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) NaviWealth/0.1';
}
