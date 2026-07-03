part of 'securities_catalog_loader.dart';

Future<SecuritiesCatalogMetaRow?> _readCatalogMeta(
  SecuritiesCatalogLoader loader,
) async {
  final row = await (loader._db.select(
    loader._db.securitiesCatalogMeta,
  )..where((t) => t.id.equals(1))).getSingleOrNull();
  return row;
}

Future<void> _replaceCatalog(
  SecuritiesCatalogLoader loader,
  SecuritiesCatalogBundle bundle,
) async {
  final db = loader._db;
  await db.transaction(() async {
    // Contentless FTS5 doesn't accept `DELETE FROM <fts>`; the
    // documented way to wipe one is the `delete-all` command.
    await db.customStatement(
      'INSERT INTO securities_catalog_fts(securities_catalog_fts) '
      "VALUES('delete-all')",
    );
    await db.delete(db.securitiesCatalog).go();

    // Insert in ~500-row batches so we get the speedup of `Batch`
    // without holding an enormous companion list in memory if the
    // catalog grows past 100k rows. Inside a single Drift `transaction`
    // a `Batch` becomes a single SQL prepared-statement loop, which is
    // an order of magnitude faster than per-row `into.insert`.
    const batchSize = 500;
    for (var start = 0; start < bundle.entries.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, bundle.entries.length);
      final slice = bundle.entries.sublist(start, end);
      await db.batch((b) {
        b.insertAll(
          db.securitiesCatalog,
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
        await db.customStatement(
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
    await db
        .into(db.securitiesCatalogMeta)
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
