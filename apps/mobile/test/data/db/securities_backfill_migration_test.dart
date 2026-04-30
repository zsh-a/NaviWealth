import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/domain/values/asset_market.dart';

import 'test_database.dart';

/// FIR-75 v6 migration: covers the backfill that materialises every
/// historical `transactions.asset_id` into the `assets` table and
/// rewrites the transaction's `asset_id` to the new canonical
/// `<market>:<symbol>` form.
///
/// We exercise the backfill helper directly against a v6 in-memory
/// database that we hand-seed with v5-shaped fixtures (bare symbol ids
/// on the transactions, no asset rows). That keeps the test independent
/// of drift's `Migrator.fromVersion` plumbing while still asserting the
/// only behaviour we care about — that the rewrite is correct, the
/// inferred markets match the spec, and the transaction joins still hold
/// up after the migration.
void main() {
  late AppDatabase db;

  setUp(() {
    db = makeTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertTransaction({
    required String id,
    required String assetId,
    required String currency,
    DateTime? tradeDate,
  }) async {
    final hlc = Hlc(
      wallMillis: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'd1',
    );
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            accountId: 'acc-1',
            assetId: Value(assetId),
            type: TransactionType.buy,
            quantity: Decimal.one,
            price: Decimal.parse('100'),
            currency: currency,
            tradeDate: tradeDate ?? DateTime.utc(2026, 1, 1),
            ownerUserId: 'u1',
            updatedAt: DateTime.utc(2026, 1, 1),
            updatedByDevice: 'd1',
            hlc: hlc,
          ),
        );
  }

  test('backfill creates one asset row per (market, symbol) and rewrites the '
      'transactions to the new id', () async {
    await insertTransaction(
      id: 'tx-cn',
      assetId: '600519',
      currency: 'CNY',
    );
    await insertTransaction(
      id: 'tx-us',
      assetId: 'AAPL',
      currency: 'USD',
    );
    await insertTransaction(
      id: 'tx-hk',
      assetId: '0700.HK',
      currency: 'HKD',
    );
    await insertTransaction(
      id: 'tx-crypto',
      assetId: 'BTC-USD',
      currency: 'USD',
    );
    await insertTransaction(
      id: 'tx-unknown',
      assetId: 'weird thing',
      currency: 'USD',
    );

    final report = await backfillSecuritiesAssetsFromTransactions(db);

    expect(report.rewritten, 5);
    expect(report.unknownSymbols, ['weird thing']);

    Future<String?> idFor(String txId) async {
      final row = await (db.select(db.transactions)
            ..where((t) => t.id.equals(txId)))
          .getSingle();
      return row.assetId;
    }

    expect(await idFor('tx-cn'), 'cn_a:600519');
    expect(await idFor('tx-us'), 'us_stock:AAPL');
    expect(await idFor('tx-hk'), 'hk_stock:0700.HK');
    expect(await idFor('tx-crypto'), 'crypto:BTC-USD');
    expect(await idFor('tx-unknown'), 'unknown:weird thing');

    final assetRows = await db.select(db.assets).get();
    expect(assetRows.map((r) => r.id).toSet(), {
      'cn_a:600519',
      'us_stock:AAPL',
      'hk_stock:0700.HK',
      'crypto:BTC-USD',
      'unknown:weird thing',
    });

    final btc =
        assetRows.firstWhere((r) => r.id == 'crypto:BTC-USD');
    expect(btc.type, AssetType.crypto);
    expect(btc.market, AssetMarket.crypto.wire);
    expect(btc.symbol, 'BTC-USD');
    expect(btc.currency, 'USD');
  });

  test('multiple transactions on the same symbol collapse into a single '
      'asset row', () async {
    for (var i = 0; i < 4; i++) {
      await insertTransaction(
        id: 'tx-$i',
        assetId: '600519',
        currency: 'CNY',
        tradeDate: DateTime.utc(2026, 2, 1 + i),
      );
    }

    final report = await backfillSecuritiesAssetsFromTransactions(db);
    expect(report.rewritten, 1);

    final assetRows = await db.select(db.assets).get();
    expect(assetRows, hasLength(1));
    expect(assetRows.single.id, 'cn_a:600519');

    final txs = await db.select(db.transactions).get();
    expect(txs.map((t) => t.assetId).toSet(), {'cn_a:600519'});
  });

  test('dry-run reports the same impact without mutating either table',
      () async {
    await insertTransaction(
      id: 'tx-aapl',
      assetId: 'AAPL',
      currency: 'USD',
    );

    final report =
        await backfillSecuritiesAssetsFromTransactions(db, dryRun: true);
    expect(report.rewritten, 1);
    expect(report.entries.single.newAssetId, 'us_stock:AAPL');

    expect(await db.select(db.assets).get(), isEmpty,
        reason: 'dry-run must not insert asset rows');
    final tx = await db.select(db.transactions).getSingle();
    expect(tx.assetId, 'AAPL',
        reason: 'dry-run must not rewrite transactions');

    // After committing for real, the impact matches the dry-run prediction.
    final committed = await backfillSecuritiesAssetsFromTransactions(db);
    expect(committed.rewritten, report.rewritten);
    final txAfter = await db.select(db.transactions).getSingle();
    expect(txAfter.assetId, 'us_stock:AAPL');
  });

  test('asset_ids that already follow the canonical scheme are left alone',
      () async {
    await insertTransaction(
      id: 'tx-canonical',
      assetId: 'us_stock:AAPL',
      currency: 'USD',
    );

    final report = await backfillSecuritiesAssetsFromTransactions(db);
    expect(report.rewritten, 0);
    expect(report.skipped, ['us_stock:AAPL']);

    final tx = await db.select(db.transactions).getSingle();
    expect(tx.assetId, 'us_stock:AAPL');
    expect(await db.select(db.assets).get(), isEmpty);
  });

  test('soft-deleted transactions are ignored', () async {
    const hlc = Hlc(wallMillis: 1000, counter: 0, nodeId: 'd1');
    await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: 'tx-tombstoned',
            accountId: 'acc-1',
            assetId: const Value('AAPL'),
            type: TransactionType.buy,
            quantity: Decimal.one,
            price: Decimal.parse('100'),
            currency: 'USD',
            tradeDate: DateTime.utc(2026, 1, 1),
            ownerUserId: 'u1',
            updatedAt: DateTime.utc(2026, 1, 1),
            updatedByDevice: 'd1',
            hlc: hlc,
            deletedAt: Value(DateTime.utc(2026, 2, 1)),
          ),
        );

    final report = await backfillSecuritiesAssetsFromTransactions(db);
    expect(report.rewritten, 0);
    expect(await db.select(db.assets).get(), isEmpty);
  });

  test('partial unique index forbids two live rows on the same '
      '(market, symbol)', () async {
    const hlc = Hlc(wallMillis: 1000, counter: 0, nodeId: 'd1');
    await db.into(db.assets).insert(
          AssetsCompanion.insert(
            id: 'us_stock:AAPL',
            type: AssetType.stock,
            symbol: 'AAPL',
            currency: 'USD',
            market: const Value('us_stock'),
            ownerUserId: 'u1',
            updatedAt: DateTime.utc(2026, 1, 1),
            updatedByDevice: 'd1',
            hlc: hlc,
          ),
        );

    expect(
      () async => db.into(db.assets).insert(
            AssetsCompanion.insert(
              id: 'duplicate-id',
              type: AssetType.stock,
              symbol: 'AAPL',
              currency: 'USD',
              market: const Value('us_stock'),
              ownerUserId: 'u1',
              updatedAt: DateTime.utc(2026, 1, 1),
              updatedByDevice: 'd1',
              hlc: hlc,
            ),
          ),
      throwsA(isA<Exception>()),
    );
  });

  test('partial unique index allows tombstoned + live row on same '
      '(market, symbol)', () async {
    const hlc = Hlc(wallMillis: 1000, counter: 0, nodeId: 'd1');
    await db.into(db.assets).insert(
          AssetsCompanion.insert(
            id: 'old-tombstone',
            type: AssetType.stock,
            symbol: 'AAPL',
            currency: 'USD',
            market: const Value('us_stock'),
            ownerUserId: 'u1',
            updatedAt: DateTime.utc(2026, 1, 1),
            updatedByDevice: 'd1',
            hlc: hlc,
            deletedAt: Value(DateTime.utc(2026, 2, 1)),
          ),
        );
    // Live row on the same (market, symbol) must still go through because
    // the unique index excludes `deleted_at IS NOT NULL` rows.
    await db.into(db.assets).insert(
          AssetsCompanion.insert(
            id: 'us_stock:AAPL',
            type: AssetType.stock,
            symbol: 'AAPL',
            currency: 'USD',
            market: const Value('us_stock'),
            ownerUserId: 'u1',
            updatedAt: DateTime.utc(2026, 1, 1),
            updatedByDevice: 'd1',
            hlc: hlc,
          ),
        );

    final rows = await db.select(db.assets).get();
    expect(rows.map((r) => r.id).toSet(), {'old-tombstone', 'us_stock:AAPL'});
  });
}
