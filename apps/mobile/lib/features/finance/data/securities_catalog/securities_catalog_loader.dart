import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/services.dart' show rootBundle;
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

import 'securities_catalog_cache_store_base.dart';

part 'securities_catalog_loader_models.dart';
part 'securities_catalog_loader_parser.dart';
part 'securities_catalog_loader_store.dart';

/// Default location of the bundled seed catalog inside the Flutter asset
/// tree. Lives under `assets/catalog/` so it can be lazy-loaded via
/// `rootBundle.loadString` rather than baked into first-paint JS on web.
const String kBundledSecuritiesCatalogAsset =
    'assets/catalog/securities.v1.ndjson';

/// Materialises the bundled seed catalog into the local DB.
///
/// Conceptually a "side-channel" loader: not part of the row-state sync
/// pipeline, not stamped with HLC, not mirrored to peers — every device
/// derives the same catalog independently from the bundled asset.
///
/// Lifecycle:
///   1. App boot calls [load] (typically right after the first DB open).
///   2. The loader reads the bundled file once via [bundleReader], plus
///      the out-of-band download in [cacheStore] when present, and keeps
///      whichever has the newer version (ties favour the download). The
///      winner's `(version, checksum)` is compared against the singleton
///      `securities_catalog_meta` row.
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
    SecuritiesCatalogCacheStore? cacheStore,
    AppLogger? logger,
  }) : _db = db,
       _bundleReader = bundleReader,
       _cacheStore = cacheStore,
       _logger = logger;

  final AppDatabase _db;
  final Future<String> Function() _bundleReader;
  final SecuritiesCatalogCacheStore? _cacheStore;
  final AppLogger? _logger;

  /// Version + checksum of the catalog currently materialised in the DB,
  /// or null before the first successful load.
  Future<SecuritiesCatalogHeader?> currentHeader() async {
    final meta = await _readCatalogMeta(this);
    if (meta == null) return null;
    return (version: meta.version, checksum: meta.checksum);
  }

  /// Read the bundle, decide whether a reload is needed, and apply it.
  ///
  /// Errors from [bundleReader] / parsing are caught and surfaced via
  /// [SecuritiesCatalogLoadResult.error] so a corrupt bundle never
  /// blocks app boot. The previous catalog (if any) stays intact.
  Future<SecuritiesCatalogLoadResult> load() async {
    final cached = await _readCached();
    String? bundled;
    Object? bundleError;
    try {
      bundled = await _bundleReader();
    } catch (e) {
      bundleError = e;
      _logger?.w('securities_catalog: failed to read bundle: $e');
    }

    if (cached != null && _preferCached(cached, bundled)) {
      SecuritiesCatalogBundle? downloaded;
      try {
        downloaded = parseBundle(cached);
      } catch (e) {
        // Validated before it was written, so this means on-disk damage.
        _logger?.w('securities_catalog: dropping corrupt download: $e');
        await _deleteCached();
      }
      if (downloaded != null) return _apply(downloaded);
    } else if (cached != null) {
      // The app update shipped a catalog at least as new as the download.
      await _deleteCached();
    }

    if (bundled == null) {
      return SecuritiesCatalogLoadResult(
        version: 'unknown',
        rowCount: 0,
        reloaded: false,
        error: bundleError ?? StateError('catalog bundle unavailable'),
      );
    }
    SecuritiesCatalogBundle bundle;
    try {
      bundle = parseBundle(bundled);
    } catch (e) {
      _logger?.w('securities_catalog: failed to parse bundle: $e');
      return SecuritiesCatalogLoadResult(
        version: 'unknown',
        rowCount: 0,
        reloaded: false,
        error: e,
      );
    }
    return _apply(bundle);
  }

  bool _preferCached(String cached, String? bundled) {
    final SecuritiesCatalogHeader cachedHeader;
    try {
      cachedHeader = parseBundleHeader(cached);
    } catch (_) {
      return true; // Let the full parse fail and drop the file.
    }
    if (bundled == null) return true;
    try {
      final bundledHeader = parseBundleHeader(bundled);
      return compareCatalogVersions(
            cachedHeader.version,
            bundledHeader.version,
          ) >=
          0;
    } catch (_) {
      return true;
    }
  }

  Future<String?> _readCached() async {
    final store = _cacheStore;
    if (store == null) return null;
    try {
      return await store.read();
    } catch (e) {
      _logger?.w('securities_catalog: failed to read download: $e');
      return null;
    }
  }

  Future<void> _deleteCached() async {
    try {
      await _cacheStore?.delete();
    } catch (e) {
      _logger?.w('securities_catalog: failed to delete download: $e');
    }
  }

  Future<SecuritiesCatalogLoadResult> _apply(
    SecuritiesCatalogBundle bundle,
  ) async {
    final existing = await _readCatalogMeta(this);
    if (existing != null &&
        existing.version == bundle.version &&
        existing.checksum == bundle.checksum) {
      return SecuritiesCatalogLoadResult(
        version: bundle.version,
        rowCount: existing.rowCount,
        reloaded: false,
      );
    }

    await _replaceCatalog(this, bundle);
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
}

/// Default reader: pulls the catalog from the Flutter asset bundle.
///
/// Defined as a top-level function so the loader's default constructor
/// can stay `const`-friendly for production use, while tests pass an
/// in-memory string source.
Future<String> _defaultBundleReader() {
  return rootBundle.loadString(kBundledSecuritiesCatalogAsset);
}
