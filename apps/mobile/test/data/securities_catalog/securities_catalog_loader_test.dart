import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/securities_catalog/securities_catalog_loader.dart';

import '../db/test_database.dart';
import '_catalog_fixtures.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = makeTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  test('first load materialises every catalog row + writes meta', () async {
    final loader = SecuritiesCatalogLoader(
      db: db,
      bundleReader: makeReader(makeFixtureBundle()),
    );

    final result = await loader.load();
    expect(result.isOk, isTrue);
    expect(result.reloaded, isTrue);
    expect(result.version, 'v-test-1');
    expect(result.rowCount, greaterThan(0));

    final rows = await db.select(db.securitiesCatalog).get();
    expect(rows.map((r) => r.id), containsAll([
      'cn_a:600519',
      'us_stock:AAPL',
      'hk_stock:0700.HK',
      'crypto:BTC-USD',
    ]));

    final meta = await (db.select(db.securitiesCatalogMeta)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    expect(meta.version, 'v-test-1');
    expect(meta.checksum, 'fixture-1');
    expect(meta.rowCount, rows.length);
  });

  test('second load with the same checksum is a no-op', () async {
    final loader = SecuritiesCatalogLoader(
      db: db,
      bundleReader: makeReader(makeFixtureBundle()),
    );
    await loader.load();
    final firstLoadedAt = (await db.select(db.securitiesCatalogMeta).getSingle())
        .loadedAt;

    // Sleep a tick so a real reload would change `loaded_at` — the test
    // asserts the loader does NOT touch the row.
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final result = await loader.load();
    expect(result.reloaded, isFalse);

    final unchanged =
        (await db.select(db.securitiesCatalogMeta).getSingle()).loadedAt;
    expect(
      unchanged,
      firstLoadedAt,
      reason: 'no-op load must not bump loaded_at',
    );
  });

  test('bumped checksum triggers a wipe-and-reload', () async {
    final v1 = SecuritiesCatalogLoader(
      db: db,
      bundleReader: makeReader(makeFixtureBundle()),
    );
    await v1.load();
    final v1Rows = await db.select(db.securitiesCatalog).get();

    final v2 = SecuritiesCatalogLoader(
      db: db,
      bundleReader: makeReader(
        makeFixtureBundle(
          version: 'v-test-2',
          checksum: 'fixture-2',
          rows: const [
            {
              's': 'GOOG',
              'm': 'us_stock',
              't': 'stock',
              'c': 'USD',
              'ne': 'Alphabet Inc.',
            },
          ],
        ),
      ),
    );
    final result = await v2.load();
    expect(result.reloaded, isTrue);
    expect(result.version, 'v-test-2');
    expect(result.rowCount, 1);

    final v2Rows = await db.select(db.securitiesCatalog).get();
    expect(v2Rows.map((r) => r.id), {'us_stock:GOOG'});
    expect(
      v2Rows.map((r) => r.id),
      isNot(containsAll(v1Rows.map((r) => r.id))),
      reason: 'reload must wipe stale rows, not merge',
    );
  });

  test('FTS index lines up with catalog rowids after reload', () async {
    final loader = SecuritiesCatalogLoader(
      db: db,
      bundleReader: makeReader(makeFixtureBundle()),
    );
    await loader.load();

    // Querying the FTS table by MATCH and joining back to the catalog
    // by rowid is the search service's hot path; we assert the join
    // returns a non-empty result for a well-known token.
    final rows = await db.customSelect(
      '''
      SELECT c.id
      FROM securities_catalog_fts AS f
      JOIN securities_catalog AS c ON c.rowid = f.rowid
      WHERE securities_catalog_fts MATCH ?
      ''',
      variables: [Variable.withString('"apple"*')],
    ).get();
    expect(rows.map((r) => r.read<String>('id')).toList(), ['us_stock:AAPL']);
  });

  test('parser ignores blank lines and comments in the bundle', () async {
    const bundle = '''
{"version":"v-test-comments","checksum":"abc","count":1}
# trailing comment ignored

{"s":"AAPL","m":"us_stock","t":"stock","c":"USD","ne":"Apple Inc."}
# stray comment in the middle
''';
    final loader = SecuritiesCatalogLoader(
      db: db,
      bundleReader: makeReader(bundle),
    );
    final result = await loader.load();
    expect(result.isOk, isTrue);
    expect(result.rowCount, 1);
  });

  test('corrupt bundle leaves the previous catalog intact', () async {
    final ok = SecuritiesCatalogLoader(
      db: db,
      bundleReader: makeReader(makeFixtureBundle()),
    );
    await ok.load();
    final goodRows = await db.select(db.securitiesCatalog).get();
    expect(goodRows, isNotEmpty);

    final broken = SecuritiesCatalogLoader(
      db: db,
      bundleReader: makeReader('not valid json'),
    );
    final result = await broken.load();
    expect(result.isOk, isFalse);
    expect(result.error, isNotNull);

    // Good rows survive the failed parse.
    final after = await db.select(db.securitiesCatalog).get();
    expect(after, hasLength(goodRows.length));
  });

  test('parseBundle dedupes duplicate entries before insert', () async {
    final bundle = makeFixtureBundle(rows: const [
      {
        's': 'AAPL',
        'm': 'us_stock',
        't': 'stock',
        'c': 'USD',
        'ne': 'Apple Inc.',
      },
      {
        's': 'AAPL',
        'm': 'us_stock',
        't': 'stock',
        'c': 'USD',
        'ne': 'Apple Inc. duplicate',
      },
    ]);
    final loader = SecuritiesCatalogLoader(
      db: db,
      bundleReader: makeReader(bundle),
    );
    await loader.load();
    final rows = await db.select(db.securitiesCatalog).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'us_stock:AAPL');
  });
}
