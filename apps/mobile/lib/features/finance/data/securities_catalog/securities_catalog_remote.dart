import 'dart:convert';

import 'package:archive/archive.dart' show GZipDecoder;
import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:naviwealth/core/logging/app_logger.dart';

import 'securities_catalog_cache_store_base.dart';
import 'securities_catalog_loader.dart';

/// Schema of `catalog-manifest.json` this build understands. Bump together
/// with `tool/asset_catalog/publish.py` when the bundle format changes; older
/// apps then ignore newer manifests and keep their current catalog.
const int kSecuritiesCatalogManifestSchema = 1;

/// Hard ceiling for a downloaded (gzip) catalog. The bake step budgets 800KB.
const int kSecuritiesCatalogMaxDownloadBytes = 8 * 1024 * 1024;

final RegExp _assetNamePattern = RegExp(r'^[A-Za-z0-9._-]+$');
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// Metadata published next to each catalog asset on the rolling
/// `securities-catalog` GitHub Release.
class SecuritiesCatalogManifest {
  const SecuritiesCatalogManifest({
    required this.version,
    required this.checksum,
    required this.count,
    required this.sha256,
    required this.asset,
    required this.gzipSha256,
    required this.gzipSize,
  });

  factory SecuritiesCatalogManifest.parse(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map<String, Object?>) {
      throw const FormatException('catalog manifest must be a JSON object');
    }
    final schema = json['schema'];
    if (schema != kSecuritiesCatalogManifestSchema) {
      throw FormatException('unsupported catalog manifest schema: $schema');
    }
    String str(String key, [RegExp? pattern]) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('catalog manifest missing $key');
      }
      if (pattern != null && !pattern.hasMatch(value)) {
        throw FormatException('catalog manifest has invalid $key');
      }
      return value;
    }

    int positiveInt(String key) {
      final value = json[key];
      if (value is! int || value <= 0) {
        throw FormatException('catalog manifest has invalid $key');
      }
      return value;
    }

    final manifest = SecuritiesCatalogManifest(
      version: str('version'),
      checksum: str('checksum'),
      count: positiveInt('count'),
      sha256: str('sha256', _sha256Pattern),
      asset: str('asset', _assetNamePattern),
      gzipSha256: str('gzip_sha256', _sha256Pattern),
      gzipSize: positiveInt('gzip_size'),
    );
    if (manifest.gzipSize > kSecuritiesCatalogMaxDownloadBytes) {
      throw const FormatException('catalog asset exceeds download limit');
    }
    return manifest;
  }

  final String version;
  final String checksum;
  final int count;

  /// SHA-256 of the decompressed NDJSON.
  final String sha256;

  /// File name of the gzip asset, resolved against the manifest URL.
  final String asset;
  final String gzipSha256;
  final int gzipSize;
}

enum SecuritiesCatalogRemoteStatus {
  /// No manifest configured for this build/platform.
  disabled,

  /// Checked recently; the manifest was not fetched.
  throttled,

  /// The device already has this or a newer catalog.
  upToDate,

  /// A newer catalog was downloaded, verified, and materialised.
  updated,

  /// Network, verification, or load failure; the current catalog is intact.
  failed,
}

class SecuritiesCatalogRemoteResult {
  const SecuritiesCatalogRemoteResult(this.status, {this.version, this.error});

  final SecuritiesCatalogRemoteStatus status;
  final String? version;
  final Object? error;
}

/// Pulls catalog refreshes from GitHub Releases so listing changes reach
/// installed apps without shipping a new APK.
///
/// Integrity: the gzip asset and its decompressed NDJSON must both match the
/// manifest SHA-256s, and the NDJSON header must match the manifest version,
/// checksum, and count before anything is written. The verified file then
/// goes through the regular [SecuritiesCatalogLoader] path, which keeps the
/// newer of bundled vs downloaded and replaces the table atomically.
class SecuritiesCatalogRemoteUpdater {
  SecuritiesCatalogRemoteUpdater({
    required Uri manifestUrl,
    required Dio dio,
    required SecuritiesCatalogCacheStore store,
    required SecuritiesCatalogLoader loader,
    DateTime Function()? clock,
    this.minCheckInterval = const Duration(hours: 24),
    AppLogger? logger,
  }) : _manifestUrl = manifestUrl,
       _dio = dio,
       _store = store,
       _loader = loader,
       _clock = clock ?? DateTime.now,
       _logger = logger;

  final Uri _manifestUrl;
  final Dio _dio;
  final SecuritiesCatalogCacheStore _store;
  final SecuritiesCatalogLoader _loader;
  final DateTime Function() _clock;
  final AppLogger? _logger;
  final Duration minCheckInterval;

  Future<SecuritiesCatalogRemoteResult> refresh({bool force = false}) async {
    try {
      final now = _clock().toUtc();
      if (!force) {
        final last = await _store.lastCheckedAt();
        if (last != null && now.difference(last) < minCheckInterval) {
          return const SecuritiesCatalogRemoteResult(
            SecuritiesCatalogRemoteStatus.throttled,
          );
        }
      }

      final manifest = SecuritiesCatalogManifest.parse(await _fetchManifest());
      await _store.markChecked(now);

      final current = await _loader.currentHeader();
      if (current != null && !_isNewer(manifest, current)) {
        return SecuritiesCatalogRemoteResult(
          SecuritiesCatalogRemoteStatus.upToDate,
          version: current.version,
        );
      }

      final raw = await _downloadVerified(manifest);
      await _store.write(raw);
      final result = await _loader.load();
      if (!result.isOk) {
        return SecuritiesCatalogRemoteResult(
          SecuritiesCatalogRemoteStatus.failed,
          error: result.error,
        );
      }
      _logger?.i(
        'securities_catalog: remote refresh '
        'version=${result.version} reloaded=${result.reloaded}',
      );
      return SecuritiesCatalogRemoteResult(
        result.reloaded && result.version == manifest.version
            ? SecuritiesCatalogRemoteStatus.updated
            : SecuritiesCatalogRemoteStatus.upToDate,
        version: result.version,
      );
    } catch (e) {
      _logger?.w('securities_catalog: remote refresh failed: $e');
      return SecuritiesCatalogRemoteResult(
        SecuritiesCatalogRemoteStatus.failed,
        error: e,
      );
    }
  }

  bool _isNewer(
    SecuritiesCatalogManifest manifest,
    SecuritiesCatalogHeader current,
  ) {
    final order = compareCatalogVersions(manifest.version, current.version);
    if (order != 0) return order > 0;
    // Same-day republish with different content.
    return manifest.checksum != current.checksum;
  }

  Future<String> _fetchManifest() async {
    final response = await _dio.getUri<String>(
      _manifestUrl,
      options: Options(responseType: ResponseType.plain),
    );
    final body = response.data;
    if (body == null || body.isEmpty) {
      throw const FormatException('empty catalog manifest');
    }
    return body;
  }

  Future<String> _downloadVerified(SecuritiesCatalogManifest manifest) async {
    final response = await _dio.getUri<List<int>>(
      _manifestUrl.resolve(manifest.asset),
      options: Options(responseType: ResponseType.bytes),
    );
    final gzipBytes = response.data;
    if (gzipBytes == null || gzipBytes.length != manifest.gzipSize) {
      throw const FormatException('catalog asset size mismatch');
    }
    if (sha256.convert(gzipBytes).toString() != manifest.gzipSha256) {
      throw const FormatException('catalog asset sha256 mismatch');
    }
    final bytes = const GZipDecoder().decodeBytes(gzipBytes);
    if (sha256.convert(bytes).toString() != manifest.sha256) {
      throw const FormatException('catalog content sha256 mismatch');
    }
    final raw = utf8.decode(bytes);
    final bundle = parseBundle(raw);
    if (bundle.version != manifest.version ||
        bundle.checksum != manifest.checksum ||
        bundle.entries.length != manifest.count) {
      throw const FormatException('catalog header does not match manifest');
    }
    return raw;
  }
}
