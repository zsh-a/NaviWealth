import 'dart:convert';

import 'package:naviwealth/data/securities_catalog/securities_catalog_loader.dart';

/// Hand-picked catalog used by the loader and search-service tests.
/// Smaller than the bundled file but covers every code path we want
/// to assert on (CN A-share, HK, US, ETF, crypto, alias-only match).
const List<Map<String, Object?>> _kFixtureRows = [
  {
    's': '600519',
    'm': 'cn_a',
    't': 'stock',
    'c': 'CNY',
    'ne': 'Kweichow Moutai',
    'nc': '贵州茅台',
    'p': 'guizhoumaotai',
    'pi': 'gzmt',
    'a': 'mt mtjt 茅台 maotai',
  },
  {
    's': '000858',
    'm': 'cn_a',
    't': 'stock',
    'c': 'CNY',
    'ne': 'Wuliangye',
    'nc': '五粮液',
    'p': 'wuliangye',
    'pi': 'wly',
  },
  {
    's': 'AAPL',
    'm': 'us_stock',
    't': 'stock',
    'c': 'USD',
    'ne': 'Apple Inc.',
    'nc': '苹果公司',
    'p': 'pingguogongsi',
    'pi': 'pgs',
    'a': 'apple',
  },
  {
    's': 'MSFT',
    'm': 'us_stock',
    't': 'stock',
    'c': 'USD',
    'ne': 'Microsoft',
    'nc': '微软',
    'p': 'weiruan',
    'pi': 'wr',
  },
  {
    's': 'SPY',
    'm': 'us_stock',
    't': 'etf',
    'c': 'USD',
    'ne': 'SPDR S&P 500 ETF',
    'a': 'sp500 spdr',
  },
  {
    's': '0700.HK',
    'm': 'hk_stock',
    't': 'stock',
    'c': 'HKD',
    'ne': 'Tencent',
    'nc': '腾讯控股',
    'p': 'tengxunkonggu',
    'pi': 'txkg',
    'a': 'tencent',
  },
  {
    's': 'BTC-USD',
    'm': 'crypto',
    't': 'crypto',
    'c': 'USD',
    'ne': 'Bitcoin',
    'nc': '比特币',
    'p': 'bitebi',
    'pi': 'btb',
    'a': 'bitcoin btc',
  },
];

/// Returns a deterministic NDJSON catalog string for use in tests.
/// [version] / [checksum] are passed verbatim into the header so a test
/// can simulate a bundle bump simply by tweaking either.
String makeFixtureBundle({
  String version = 'v-test-1',
  String checksum = 'fixture-1',
  List<Map<String, Object?>>? rows,
}) {
  final buffer = StringBuffer()
    ..writeln(jsonEncode({
      'version': version,
      'checksum': checksum,
      'count': (rows ?? _kFixtureRows).length,
    }));
  for (final row in rows ?? _kFixtureRows) {
    buffer.writeln(jsonEncode(row));
  }
  return buffer.toString();
}

/// Builds a sync reader callback for [SecuritiesCatalogLoader] off a
/// canned string. The loader itself never touches `rootBundle`, so this
/// is the only test seam needed.
Future<String> Function() makeReader(String bundle) {
  return () async => bundle;
}
