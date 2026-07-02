import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/services.dart' show rootBundle;
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

/// Default location of the bundled seed catalog inside the Flutter asset
/// tree. Lives under `assets/catalog/` so it can be lazy-loaded via
/// `rootBundle.loadString` rather than baked into first-paint JS on web.
const String kBundledSecuritiesCatalogAsset =
    'assets/catalog/securities.v1.ndjson';

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

/// Materialises the bundled seed catalog into the local DB.
///
/// Conceptually a "side-channel" loader: not part of the OpLog sync
/// pipeline, not stamped with HLC, not mirrored to peers — every device
/// derives the same catalog independently from the bundled asset.
///
/// Lifecycle:
///   1. App boot calls [load] (typically right after the first DB open).
///   2. The loader reads the bundled file once via [bundleReader],
///      parses the header to extract `(version, checksum)`, and compares
///      against the singleton `securities_catalog_meta` row.
///   3. On match, returns a `reloaded=false` result without touching the
///      catalog table — the common steady-state path is essentially free.
///   4. On miss (fresh install or bundle bump), wipes the catalog +
///      FTS5 index inside one transaction, bulk-inserts the new entries,
///      and updates the meta row last so a partial write is observable
///      as an out-of-date version rather than a half-populated table.
///
/// The loader is intentionally idempotent and resumable: if the
/// transaction aborts (closed DB, OOM) the meta row stays at the
/// previous version and the next call re-runs the rewrite.
class SecuritiesCatalogLoader {
  SecuritiesCatalogLoader({
    required AppDatabase db,
    Future<String> Function() bundleReader = _defaultBundleReader,
    AppLogger? logger,
  }) : _db = db,
       _bundleReader = bundleReader,
       _logger = logger;

  final AppDatabase _db;
  final Future<String> Function() _bundleReader;
  final AppLogger? _logger;

  /// Read the bundle, decide whether a reload is needed, and apply it.
  ///
  /// Errors from [bundleReader] / parsing are caught and surfaced via
  /// [SecuritiesCatalogLoadResult.error] so a corrupt bundle never
  /// blocks app boot. The previous catalog (if any) stays intact.
  Future<SecuritiesCatalogLoadResult> load() async {
    String raw;
    try {
      raw = await _bundleReader();
    } catch (e) {
      _logger?.w('securities_catalog: failed to read bundle: $e');
      return SecuritiesCatalogLoadResult(
        version: 'unknown',
        rowCount: 0,
        reloaded: false,
        error: e,
      );
    }

    SecuritiesCatalogBundle bundle;
    try {
      bundle = parseBundle(raw);
    } catch (e) {
      _logger?.w('securities_catalog: failed to parse bundle: $e');
      return SecuritiesCatalogLoadResult(
        version: 'unknown',
        rowCount: 0,
        reloaded: false,
        error: e,
      );
    }

    final existing = await _readMeta();
    if (existing != null &&
        existing.version == bundle.version &&
        existing.checksum == bundle.checksum) {
      return SecuritiesCatalogLoadResult(
        version: bundle.version,
        rowCount: existing.rowCount,
        reloaded: false,
      );
    }

    await _replaceCatalog(bundle);
    _logger?.i(
      'securities_catalog: loaded version=${bundle.version} '
      'rows=${bundle.entries.length}',
    );
    return SecuritiesCatalogLoadResult(
      version: bundle.version,
      rowCount: bundle.entries.length,
      reloaded: true,
    );
  }

  Future<SecuritiesCatalogMetaRow?> _readMeta() async {
    final row = await (_db.select(
      _db.securitiesCatalogMeta,
    )..where((t) => t.id.equals(1))).getSingleOrNull();
    return row;
  }

  Future<void> _replaceCatalog(SecuritiesCatalogBundle bundle) async {
    await _db.transaction(() async {
      // Contentless FTS5 doesn't accept `DELETE FROM <fts>`; the
      // documented way to wipe one is the `delete-all` command.
      await _db.customStatement(
        'INSERT INTO securities_catalog_fts(securities_catalog_fts) '
        "VALUES('delete-all')",
      );
      await _db.delete(_db.securitiesCatalog).go();

      // Insert in ~500-row batches so we get the speedup of `Batch`
      // without holding an enormous companion list in memory if the
      // catalog grows past 100k rows. Inside a single Drift `transaction`
      // a `Batch` becomes a single SQL prepared-statement loop, which is
      // an order of magnitude faster than per-row `into.insert`.
      const batchSize = 500;
      for (var start = 0; start < bundle.entries.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, bundle.entries.length);
        final slice = bundle.entries.sublist(start, end);
        await _db.batch((b) {
          b.insertAll(
            _db.securitiesCatalog,
            slice
                .map(
                  (e) => SecuritiesCatalogCompanion.insert(
                    id: e.id,
                    symbol: e.symbol,
                    market: e.market.wire,
                    type: e.type,
                    currency: e.currency,
                    nameEn: Value(e.nameEn),
                    nameCn: Value(e.nameCn),
                    pinyin: Value(e.pinyin),
                    pinyinInitials: Value(e.pinyinInitials),
                    aliases: Value(e.aliases),
                  ),
                )
                .toList(),
          );
        });

        // Mirror the same slice into the contentless FTS5 index. We
        // keep the rowids in step with `securities_catalog.rowid` so
        // search queries can join the two tables by rowid without
        // building a separate id map.
        for (final entry in slice) {
          await _db.customStatement(
            '''
            INSERT INTO securities_catalog_fts(
              rowid, symbol, name_en, name_cn, pinyin, pinyin_initials, aliases
            )
            SELECT rowid, symbol, name_en, name_cn, pinyin, pinyin_initials, aliases
            FROM securities_catalog
            WHERE id = ?
            ''',
            [entry.id],
          );
        }
      }

      // Meta row is written last: a crash before this point leaves the
      // catalog in an old state but the meta unchanged, so the next
      // [load] call simply reruns the rewrite.
      await _db
          .into(_db.securitiesCatalogMeta)
          .insertOnConflictUpdate(
            SecuritiesCatalogMetaCompanion.insert(
              id: const Value(1),
              version: bundle.version,
              checksum: bundle.checksum,
              rowCount: bundle.entries.length,
              loadedAt: DateTime.now().toUtc(),
            ),
          );
    });
  }
}

/// Default reader: pulls the catalog from the Flutter asset bundle.
///
/// Defined as a top-level function so the loader's default constructor
/// can stay `const`-friendly for production use, while tests pass an
/// in-memory string source.
Future<String> _defaultBundleReader() {
  return rootBundle.loadString(kBundledSecuritiesCatalogAsset);
}

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
