import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/op.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/asset.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/repositories/securities_asset_repository.dart';
import 'package:naviwealth/domain/values/asset_market.dart';

import '../../core/sync/_outbox_test_ext.dart';
import '../db/test_database.dart';
import '_stub_stamper.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late SecuritiesAssetRepository repo;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = SecuritiesAssetRepository(
      db: db,
      outbox: outbox,
      stamper: makeStubStamper(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('upsertSecurity inserts and queues an insert op the first time',
      () async {
    final asset = await repo.upsertSecurity(
      symbol: '600519',
      market: AssetMarket.cnA,
      type: AssetType.stock,
      currency: 'CNY',
      name: '贵州茅台',
    );

    expect(asset.id, 'cn_a:600519');
    expect(asset.market, 'cn_a');
    expect(asset.symbol, '600519');
    expect(asset.type, AssetType.stock);

    final batch = await outbox.peekBatch();
    expect(batch.single.opType, OpType.insert);
    expect(batch.single.tableName, 'assets');
    expect(batch.single.rowId, 'cn_a:600519');
  });

  test('upsertSecurity is idempotent on a repeat call with no changes',
      () async {
    await repo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      name: 'Apple Inc.',
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final hlcBefore = (await repo.findById('us_stock:AAPL'))!.sync.hlc;

    final again = await repo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      name: 'Apple Inc.',
    );

    expect(again.id, 'us_stock:AAPL');
    expect(again.sync.hlc, hlcBefore,
        reason: 'no-op upsert must not bump the row HLC');
    expect(await outbox.peekBatch(), isEmpty,
        reason: 'no-op upsert must not enqueue an op');
  });

  test('upsertSecurity emits an update op when fields actually change',
      () async {
    await repo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      name: 'Apple Inc.',
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final updated = await repo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      name: 'Apple Inc. (rebrand)',
      isin: 'US0378331005',
    );

    expect(updated.name, 'Apple Inc. (rebrand)');
    expect(updated.isin, 'US0378331005');

    final batch = await outbox.peekBatch();
    expect(batch.single.opType, OpType.update);
    final diff = batch.single.fieldsDiff!;
    expect(diff['name'], 'Apple Inc. (rebrand)');
    expect(diff['isin'], 'US0378331005');
    expect(diff.containsKey('symbol'), isFalse,
        reason: 'unchanged columns must not appear in the diff');
  });

  test('same symbol in different markets resolve to distinct rows', () async {
    final cn = await repo.upsertSecurity(
      symbol: '000001',
      market: AssetMarket.cnA,
      type: AssetType.stock,
      currency: 'CNY',
      name: '平安银行',
    );
    final us = await repo.upsertSecurity(
      symbol: '000001',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      name: 'US Symbol Coincidence',
    );

    expect(cn.id, 'cn_a:000001');
    expect(us.id, 'us_stock:000001');
    expect(cn.id, isNot(equals(us.id)));

    expect(await repo.findBySymbolAndMarket('000001', AssetMarket.cnA),
        isNotNull);
    expect(await repo.findBySymbolAndMarket('000001', AssetMarket.usStock),
        isNotNull);
  });

  test('watchSecurities emits the new row when a security is upserted',
      () async {
    final stream = repo.watchSecurities();
    expect(await stream.first, isEmpty);

    await repo.upsertSecurity(
      symbol: 'BTC-USD',
      market: AssetMarket.crypto,
      type: AssetType.crypto,
      currency: 'USD',
      name: 'Bitcoin',
    );

    final next = await stream.first;
    expect(next, hasLength(1));
    expect(next.single.id, 'crypto:BTC-USD');
  });

  test('watchSecurities filters by asset type when caller restricts the set',
      () async {
    await repo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
    );
    await repo.upsertSecurity(
      symbol: 'SPY',
      market: AssetMarket.usStock,
      type: AssetType.etf,
      currency: 'USD',
    );

    final stocksOnly =
        await repo.watchSecurities(types: {AssetType.stock}).first;
    expect(stocksOnly.map((a) => a.id), {'us_stock:AAPL'});

    final etfsOnly = await repo.watchSecurities(types: {AssetType.etf}).first;
    expect(etfsOnly.map((a) => a.id), {'us_stock:SPY'});
  });

  test('watchSecurities skips manual-valuation assets even when they share '
      'the table', () async {
    // Insert a "cash" row directly to mimic the ManualAssetRepository
    // contribution. Securities watch must not pick it up because its
    // `market` column is NULL.
    final stamp = await makeStubStamper().stamp();
    await db.into(db.assets).insert(
          AssetsCompanion.insert(
            id: stamp.deviceId, // any unique stub id
            type: AssetType.cash,
            symbol: 'USD',
            currency: 'USD',
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        );

    await repo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
    );

    final securities = await repo.watchSecurities().first;
    expect(securities.map((a) => a.id), {'us_stock:AAPL'});
  });

  test('softDelete tombstones the row and queues a delete op', () async {
    final first = await repo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    await repo.softDelete(first.id);
    final reloaded = await repo.findById(first.id);
    expect(reloaded!.sync.deletedAt, isNotNull);

    final deleteBatch = await outbox.peekBatch();
    expect(deleteBatch.single.opType, OpType.delete);

    // findBySymbolAndMarket excludes tombstoned rows so it should not
    // surface the deleted instrument.
    expect(
      await repo.findBySymbolAndMarket('AAPL', AssetMarket.usStock),
      isNull,
    );
  });

  test('Asset.idFor rejects empty / colon-bearing symbols', () {
    expect(() => Asset.idFor(AssetMarket.cnA, ''), throwsArgumentError);
    expect(() => Asset.idFor(AssetMarket.cnA, '   '), throwsArgumentError);
    expect(
      () => Asset.idFor(AssetMarket.cnA, 'oops:colon'),
      throwsArgumentError,
    );
  });

  test('enrichMetadata fills only fields that are still null', () async {
    await repo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      name: 'User-edited name',
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final enriched = await repo.enrichMetadata(
      id: 'us_stock:AAPL',
      // Should be ignored — the user already named the row.
      name: 'Apple Inc.',
      // Should be filled — column is null on the existing row.
      isin: 'US0378331005',
      industry: 'Information Technology',
    );

    expect(enriched.name, 'User-edited name',
        reason: 'enrichment must not overwrite a user-supplied name');
    expect(enriched.isin, 'US0378331005');
    expect(enriched.industry, 'Information Technology');

    final batch = await outbox.peekBatch();
    expect(batch.single.opType, OpType.update);
    final diff = batch.single.fieldsDiff!;
    expect(diff.containsKey('name'), isFalse,
        reason: 'name was already populated; must not appear in the diff');
    expect(diff['isin'], 'US0378331005');
    expect(diff['industry'], 'Information Technology');
  });

  test('enrichMetadata is a no-op when every requested field is already set',
      () async {
    await repo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
      name: 'Apple Inc.',
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final hlcBefore = (await repo.findById('us_stock:AAPL'))!.sync.hlc;
    final enriched = await repo.enrichMetadata(
      id: 'us_stock:AAPL',
      name: 'something else',
    );

    expect(enriched.sync.hlc, hlcBefore,
        reason: 'no-op enrichment must not bump the HLC');
    expect(await outbox.peekBatch(), isEmpty,
        reason: 'no-op enrichment must not enqueue an op');
  });

  test('enrichMetadata fills empty name when the existing row has none',
      () async {
    await repo.upsertSecurity(
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      type: AssetType.stock,
      currency: 'USD',
    );
    await outbox.ack((await outbox.peekBatch()).map((o) => o.opId).toList());

    final enriched = await repo.enrichMetadata(
      id: 'us_stock:AAPL',
      name: 'Apple Inc.',
    );
    expect(enriched.name, 'Apple Inc.');

    final batch = await outbox.peekBatch();
    expect(batch.single.opType, OpType.update);
    expect(batch.single.fieldsDiff!['name'], 'Apple Inc.');
  });

  test('enrichMetadata throws when the asset does not exist', () async {
    expect(
      () => repo.enrichMetadata(id: 'us_stock:NOPE', name: 'whatever'),
      throwsStateError,
    );
  });

  test('upsertSecurity refuses non-securities asset types', () async {
    expect(
      () => repo.upsertSecurity(
        symbol: 'CNY',
        market: AssetMarket.cnA,
        type: AssetType.cash,
        currency: 'CNY',
      ),
      throwsArgumentError,
    );
  });
}
