part of 'securities_catalog_loader.dart';

/// One row of the seed catalog. Mirrors the on-disk schema of
/// [SecuritiesCatalog] one-for-one but lives in pure Dart so the loader
/// can validate / dedup before opening a transaction.
class SecuritiesCatalogEntry {
  const SecuritiesCatalogEntry({
    required this.symbol,
    required this.market,
    required this.type,
    required this.currency,
    this.nameEn,
    this.nameCn,
    this.pinyin,
    this.pinyinInitials,
    this.aliases,
  });

  final String symbol;
  final AssetMarket market;
  final AssetType type;
  final String currency;
  final String? nameEn;
  final String? nameCn;
  final String? pinyin;
  final String? pinyinInitials;
  final String? aliases;

  String get id => Asset.idFor(market, symbol);
}

/// Top-level shape of the bundled catalog file. The on-disk format is a
/// short JSON header line followed by one [SecuritiesCatalogEntry] per
/// line (NDJSON). NDJSON keeps the parser streaming-friendly and lets
/// `tool/build-asset-catalog.sh` append rows without rewriting the whole
/// file.
class SecuritiesCatalogBundle {
  const SecuritiesCatalogBundle({
    required this.version,
    required this.checksum,
    required this.entries,
  });

  final String version;
  final String checksum;
  final List<SecuritiesCatalogEntry> entries;
}

/// Result of a [SecuritiesCatalogLoader.load] call. Callers (typically
/// the bootstrap code that fires the first lazy load) use this to log
/// whether the catalog was reloaded or skipped, and to surface
/// diagnostics if a parse failed soft.
class SecuritiesCatalogLoadResult {
  const SecuritiesCatalogLoadResult({
    required this.version,
    required this.rowCount,
    required this.reloaded,
    this.error,
  });

  final String version;
  final int rowCount;

  /// True when the loader actually rewrote the catalog table; false
  /// when the bundled checksum matched the persisted meta and the call
  /// was a free no-op.
  final bool reloaded;

  /// Non-null only on a soft failure (parse error / IO error). The
  /// loader keeps the previous catalog intact and surfaces the error
  /// here so the caller can decide whether to escalate.
  final Object? error;

  bool get isOk => error == null;
}
