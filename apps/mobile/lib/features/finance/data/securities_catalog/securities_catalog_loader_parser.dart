part of 'securities_catalog_loader.dart';

/// Parses the on-disk bundle format: a JSON header line followed by one
/// JSON object per line (NDJSON), separated by `\n`.
///
/// Header schema:
/// ```json
/// {"version":"<semver>","checksum":"<hex>","count":<int>}
/// ```
///
/// Each entry line:
/// ```json
/// {"s":"600519","m":"cn_a","t":"stock","c":"CNY",
///  "ne":"Kweichow Moutai","nc":"贵州茅台",
///  "p":"guizhoumaotai","pi":"gzmt","a":"mt 茅台"}
/// ```
///
/// Lines starting with `#` and blank lines are ignored, matching the
/// hand-edit-friendly convention `tool/build-asset-catalog.sh` uses.
SecuritiesCatalogBundle parseBundle(String raw) {
  final lines = const LineSplitter().convert(raw);
  if (lines.isEmpty) {
    throw const FormatException('catalog bundle is empty');
  }

  Map<String, Object?>? header;
  final entries = <SecuritiesCatalogEntry>[];
  final seenIds = <String>{};

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, Object?>) {
      throw FormatException(
        'expected JSON object per line, got ${decoded.runtimeType}',
      );
    }
    if (header == null) {
      header = decoded;
      continue;
    }

    final entry = _decodeEntry(decoded);
    if (!seenIds.add(entry.id)) {
      // Duplicate rows are a build-script bug, not a runtime concern —
      // we keep the first occurrence and log nothing because validating
      // the bundle is not the loader's job. Tests assert this.
      continue;
    }
    entries.add(entry);
  }

  if (header == null) {
    throw const FormatException('catalog bundle is missing header line');
  }
  final version = header['version'];
  final checksum = header['checksum'];
  if (version is! String || checksum is! String) {
    throw const FormatException(
      'catalog bundle header missing version or checksum',
    );
  }

  return SecuritiesCatalogBundle(
    version: version,
    checksum: checksum,
    entries: entries,
  );
}

SecuritiesCatalogEntry _decodeEntry(Map<String, Object?> json) {
  final symbol = (json['s'] as String?)?.trim();
  final marketWire = json['m'] as String?;
  final typeName = json['t'] as String?;
  final currency = json['c'] as String?;
  if (symbol == null ||
      symbol.isEmpty ||
      marketWire == null ||
      typeName == null ||
      currency == null) {
    throw FormatException('catalog row missing required field: $json');
  }
  final market = assetMarketFromWire(marketWire);
  if (market == null) {
    throw FormatException('catalog row has unknown market wire: $marketWire');
  }
  final type = AssetType.values.byName(typeName);
  return SecuritiesCatalogEntry(
    symbol: symbol,
    market: market,
    type: type,
    currency: currency,
    nameEn: _trimNullable(json['ne'] as String?),
    nameCn: _trimNullable(json['nc'] as String?),
    pinyin: _normalisePinyin(json['p'] as String?),
    pinyinInitials: _normalisePinyin(json['pi'] as String?),
    aliases: _trimNullable(json['a'] as String?),
  );
}

String? _trimNullable(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Pinyin and pinyin-initials are written into the catalog table in
/// lower case so prefix `LIKE '<q>%'` queries with the default BINARY
/// collation match user input regardless of how the bundle generator
/// emitted them.
String? _normalisePinyin(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed.toLowerCase();
}

/// Version + checksum of a catalog bundle.
typedef SecuritiesCatalogHeader = ({String version, String checksum});

/// Reads only the header line, so the loader can pick between the bundled
/// and downloaded catalogs without decoding every entry twice.
SecuritiesCatalogHeader parseBundleHeader(String raw) {
  for (final line in const LineSplitter().convert(raw)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, Object?>) break;
    final version = decoded['version'];
    final checksum = decoded['checksum'];
    if (version is String && checksum is String) {
      return (version: version, checksum: checksum);
    }
    break;
  }
  throw const FormatException('catalog bundle header missing');
}

final RegExp _catalogVersionPattern = RegExp(r'^v(\d+)\.(\d{8})$');

/// Orders catalog versions (`v<schema>.<YYYYMMDD>`, as emitted by
/// `tool/build-asset-catalog.sh`). Well-formed versions rank above malformed
/// ones; two malformed versions fall back to lexical order.
int compareCatalogVersions(String a, String b) {
  final ma = _catalogVersionPattern.firstMatch(a);
  final mb = _catalogVersionPattern.firstMatch(b);
  if (ma != null && mb != null) {
    final schema = int.parse(ma.group(1)!).compareTo(int.parse(mb.group(1)!));
    if (schema != 0) return schema;
    return int.parse(ma.group(2)!).compareTo(int.parse(mb.group(2)!));
  }
  if (ma != null) return 1;
  if (mb != null) return -1;
  return a.compareTo(b);
}
