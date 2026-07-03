import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/services.dart' show rootBundle;
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';

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
