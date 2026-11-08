import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/data/securities_catalog/securities_catalog_cache_store_base.dart';
import 'package:naviwealth/features/finance/data/securities_catalog/securities_catalog_loader.dart';
import 'package:naviwealth/features/finance/data/securities_catalog/securities_catalog_remote.dart';

import '../../../../core/persistence/test_database.dart';
import '_catalog_fixtures.dart';

final _manifestUrl = Uri.parse(
  'https://github.com/o/r/releases/download/securities-catalog/'
  'catalog-manifest.json',
);

class _ReleaseAdapter implements HttpClientAdapter {
  _ReleaseAdapter(this.files);

  final Map<String, List<int>> files;
  final requested = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final name = options.uri.pathSegments.last;
    requested.add(name);
    final body = files[name];
    if (body == null) return ResponseBody.fromString('missing', 404);
    return ResponseBody.fromBytes(
      body,
      200,
      headers: <String, List<String>>{
        'content-type': <String>['application/octet-stream'],
      },
    );
  }
}

/// Builds a release (manifest + gzip asset) for [raw]. [mutate] tweaks the
/// manifest to simulate tampering or mismatches.
Map<String, List<int>> _release(
  String raw, {
  required String version,
  required String checksum,
  void Function(Map<String, Object?> manifest)? mutate,
}) {
  final bytes = utf8.encode(raw);
  final compressed = gzip.encode(bytes);
  final asset = 'securities-$version.ndjson.gz';
  final manifest = <String, Object?>{
    'schema': 1,
    'version': version,
    'checksum': checksum,
    'count': parseBundle(raw).entries.length,
    'sha256': sha256.convert(bytes).toString(),
    'asset': asset,
    'gzip_sha256': sha256.convert(compressed).toString(),
    'gzip_size': compressed.length,
  };
  mutate?.call(manifest);
  return {
    'catalog-manifest.json': utf8.encode(jsonEncode(manifest)),
    asset: compressed,
  };
}

void main() {
  late AppDatabase db;
  late MemorySecuritiesCatalogCacheStore store;
  late SecuritiesCatalogLoader loader;
  final bundled = makeFixtureBundle(version: 'v1.20261001', checksum: 'old');

  setUp(() async {
    db = makeTestDatabase();
    store = MemorySecuritiesCatalogCacheStore();
    loader = SecuritiesCatalogLoader(
      db: db,
      bundleReader: makeReader(bundled),
      cacheStore: store,
    );
    await loader.load();
  });

  tearDown(() async {
    await db.close();
  });

  SecuritiesCatalogRemoteUpdater updater(
    _ReleaseAdapter adapter, {
    DateTime? now,
  }) {
    final dio = Dio()..httpClientAdapter = adapter;
    return SecuritiesCatalogRemoteUpdater(
      manifestUrl: _manifestUrl,
      dio: dio,
      store: store,
      loader: loader,
      clock: () => now ?? DateTime.utc(2026, 11, 8, 12),
    );
  }

  test('downloads, verifies, and materialises a newer catalog', () async {
    final newer = makeFixtureBundle(
      version: 'v1.20261108',
      checksum: 'new',
      rows: [
        {'s': 'NVDA', 'm': 'us_stock', 't': 'stock', 'c': 'USD'},
      ],
    );
    final adapter = _ReleaseAdapter(
      _release(newer, version: 'v1.20261108', checksum: 'new'),
    );

    final result = await updater(adapter).refresh();

    expect(result.status, SecuritiesCatalogRemoteStatus.updated);
    expect(result.version, 'v1.20261108');
    expect(store.raw, newer);
    expect(store.checkedAt, DateTime.utc(2026, 11, 8, 12));
    final rows = await db.select(db.securitiesCatalog).get();
    expect(rows.map((r) => r.id), ['us_stock:NVDA']);
    expect((await loader.currentHeader())?.version, 'v1.20261108');
  });

  test('skips download when the device catalog is current', () async {
    final adapter = _ReleaseAdapter(
      _release(bundled, version: 'v1.20261001', checksum: 'old'),
    );

    final result = await updater(adapter).refresh();

    expect(result.status, SecuritiesCatalogRemoteStatus.upToDate);
    expect(adapter.requested, ['catalog-manifest.json']);
    expect(store.raw, isNull);
  });

  test('checks the manifest at most once per interval', () async {
    store.checkedAt = DateTime.utc(2026, 11, 8, 1);
    final adapter = _ReleaseAdapter(const {});

    final result = await updater(adapter).refresh();

    expect(result.status, SecuritiesCatalogRemoteStatus.throttled);
    expect(adapter.requested, isEmpty);
  });

  test('rejects content whose sha256 does not match the manifest', () async {
    final newer = makeFixtureBundle(version: 'v1.20261108', checksum: 'new');
    final adapter = _ReleaseAdapter(
      _release(
        newer,
        version: 'v1.20261108',
        checksum: 'new',
        mutate: (m) => m['sha256'] = '0' * 64,
      ),
    );

    final result = await updater(adapter).refresh();

    expect(result.status, SecuritiesCatalogRemoteStatus.failed);
    expect(store.raw, isNull);
    expect((await loader.currentHeader())?.version, 'v1.20261001');
  });

  test('rejects a header that disagrees with the manifest', () async {
    final newer = makeFixtureBundle(version: 'v1.20261108', checksum: 'new');
    final adapter = _ReleaseAdapter(
      _release(newer, version: 'v1.20261109', checksum: 'new'),
    );

    final result = await updater(adapter).refresh();

    expect(result.status, SecuritiesCatalogRemoteStatus.failed);
    expect(store.raw, isNull);
  });

  test('ignores manifests with an unknown schema', () async {
    final adapter = _ReleaseAdapter(
      _release(
        bundled,
        version: 'v1.20261108',
        checksum: 'new',
        mutate: (m) => m['schema'] = 2,
      ),
    );

    final result = await updater(adapter).refresh();

    expect(result.status, SecuritiesCatalogRemoteStatus.failed);
    expect(adapter.requested, ['catalog-manifest.json']);
  });

  test('rejects asset names that could escape the release', () {
    final manifest = jsonEncode({
      'schema': 1,
      'version': 'v1.20261108',
      'checksum': 'x',
      'count': 1,
      'sha256': '0' * 64,
      'asset': '../../evil.gz',
      'gzip_sha256': '0' * 64,
      'gzip_size': 10,
    });
    expect(
      () => SecuritiesCatalogManifest.parse(manifest),
      throwsFormatException,
    );
  });

  group('loader source selection', () {
    test('a newer download wins over the bundled catalog', () async {
      store.raw = makeFixtureBundle(
        version: 'v1.20261108',
        checksum: 'new',
        rows: [
          {'s': 'NVDA', 'm': 'us_stock', 't': 'stock', 'c': 'USD'},
        ],
      );

      final result = await loader.load();

      expect(result.version, 'v1.20261108');
      expect(result.reloaded, isTrue);
    });

    test(
      'an app update with a newer bundle drops the stale download',
      () async {
        store.raw = makeFixtureBundle(
          version: 'v1.20260901',
          checksum: 'older',
        );

        final result = await loader.load();

        expect(result.version, 'v1.20261001');
        expect(result.reloaded, isFalse);
        expect(store.raw, isNull);
      },
    );

    test('a corrupt download falls back to the bundle', () async {
      store.raw = '{"version":"v1.20261108","checksum":"x"}\nnot-json\n';

      final result = await loader.load();

      expect(result.isOk, isTrue);
      expect(result.version, 'v1.20261001');
      expect(store.raw, isNull);
    });
  });

  test('compareCatalogVersions orders by schema then date', () {
    expect(compareCatalogVersions('v1.20261108', 'v1.20261025'), 1);
    expect(compareCatalogVersions('v1.20261108', 'v1.20261108'), 0);
    expect(compareCatalogVersions('v2.20200101', 'v1.20261108'), 1);
    expect(compareCatalogVersions('v1.20200101', 'v-test-1'), 1);
  });
}
