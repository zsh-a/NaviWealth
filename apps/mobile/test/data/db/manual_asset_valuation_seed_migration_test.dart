import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/db/app_database.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/manual_asset_metadata.dart';

import 'test_database.dart';

/// FIR-123 v11 migration: covers [seedManualAssetValuationAdjusts], the
/// helper that backfills a genesis `valuationAdjust` transaction for
/// every manual-valuation asset that currently has a `last_price` but no
/// existing `valuationAdjust` row.
///
/// Exercised directly against an in-memory v11 database hand-seeded with
/// the row shape a v10 → v11 upgrade would leave behind. That keeps the
/// test independent of drift's `Migrator.fromVersion` plumbing while
/// asserting the behaviour the migration cares about — that every alive
/// manual asset gets an event-sourced starting point.
void main() {
  late AppDatabase db;

  setUp(() {
    db = makeTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertManualAsset({
    required String id,
    required AssetType type,
    required Decimal lastPrice,
    String currency = 'CNY',
    String? metadataJson,
    bool deleted = false,
  }) async {
    final hlc = Hlc(
      wallMillis: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      counter: 0,
      nodeId: 'd1',
    );
    await db.into(db.assets).insert(
          AssetsCompanion.insert(
            id: id,
            type: type,
            symbol: id,
            currency: currency,
            lastPrice: Value(lastPrice),
            lastPriceAt: Value(DateTime.utc(2026, 4, 1)),
            metadataJson: Value(metadataJson),
            ownerUserId: 'u1',
            updatedAt: DateTime.utc(2026, 4, 1),
            updatedByDevice: 'd1',
            hlc: hlc,
            deletedAt: deleted ? Value(DateTime.utc(2026, 4, 2)) : const Value.absent(),
          ),
        );
  }

  test('seeds a valuationAdjust transaction for each alive manual asset',
      () async {
    await insertManualAsset(
      id: 'cash-cny',
      type: AssetType.cash,
      lastPrice: Decimal.parse('1000'),
      metadataJson: const CashMetadata(accountId: 'acc-bank').encode(),
    );
    await insertManualAsset(
      id: 'deposit-1',
      type: AssetType.bankDepositTerm,
      lastPrice: Decimal.parse('50000'),
      metadataJson: DepositMetadata(
        accountId: 'acc-bank',
        principal: Decimal.parse('50000'),
        interestRate: Decimal.parse('0.03'),
      ).encode(),
    );
    await insertManualAsset(
      id: 'wealth-1',
      type: AssetType.wealthProduct,
      lastPrice: Decimal.parse('100000'),
      metadataJson: WealthProductMetadata(
        accountId: 'acc-broker',
        principal: Decimal.parse('100000'),
        expectedAnnualReturn: Decimal.parse('0.04'),
      ).encode(),
    );

    await seedManualAssetValuationAdjusts(db);

    final txs = await db.select(db.transactions).get();
    expect(txs, hasLength(3));
    final byAsset = {for (final t in txs) t.assetId: t};
    expect(byAsset['cash-cny']!.price, Decimal.parse('1000'));
    expect(byAsset['cash-cny']!.quantity, Decimal.zero);
    expect(byAsset['cash-cny']!.accountId, 'acc-bank');
    expect(byAsset['cash-cny']!.type, TransactionType.valuationAdjust);
    expect(byAsset['deposit-1']!.accountId, 'acc-bank');
    expect(byAsset['wealth-1']!.accountId, 'acc-broker');
  });

  test('skips soft-deleted assets and assets without a last_price', () async {
    await insertManualAsset(
      id: 'cash-deleted',
      type: AssetType.cash,
      lastPrice: Decimal.parse('500'),
      metadataJson: const CashMetadata(accountId: 'acc-1').encode(),
      deleted: true,
    );
    // Asset with no metadata — we still seed it but fall back to the
    // asset id as the account id (mirrors the repository's runtime rule).
    await insertManualAsset(
      id: 'cash-no-meta',
      type: AssetType.cash,
      lastPrice: Decimal.parse('200'),
    );

    await seedManualAssetValuationAdjusts(db);

    final txs = await db.select(db.transactions).get();
    expect(txs, hasLength(1));
    expect(txs.single.assetId, 'cash-no-meta');
    expect(txs.single.accountId, 'cash-no-meta');
  });

  test('is idempotent — rerunning leaves the seeded row count unchanged',
      () async {
    await insertManualAsset(
      id: 'cash-cny',
      type: AssetType.cash,
      lastPrice: Decimal.parse('1000'),
      metadataJson: const CashMetadata(accountId: 'acc-bank').encode(),
    );

    await seedManualAssetValuationAdjusts(db);
    await seedManualAssetValuationAdjusts(db);

    final txs = await db.select(db.transactions).get();
    expect(txs, hasLength(1));
  });

  test(
    'leaves manual assets that already carry a valuationAdjust transaction '
    'alone',
    () async {
      await insertManualAsset(
        id: 'cash-cny',
        type: AssetType.cash,
        lastPrice: Decimal.parse('1000'),
        metadataJson: const CashMetadata(accountId: 'acc-bank').encode(),
      );
      // Pre-existing valuationAdjust row — the seed must not duplicate it.
      final hlc = Hlc(
        wallMillis: DateTime.utc(2026, 4, 1).millisecondsSinceEpoch,
        counter: 0,
        nodeId: 'd1',
      );
      await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-existing',
              accountId: 'acc-bank',
              assetId: const Value('cash-cny'),
              type: TransactionType.valuationAdjust,
              quantity: Decimal.zero,
              price: Decimal.parse('999'),
              currency: 'CNY',
              tradeDate: DateTime.utc(2026, 4, 1),
              ownerUserId: 'u1',
              updatedAt: DateTime.utc(2026, 4, 1),
              updatedByDevice: 'd1',
              hlc: hlc,
            ),
          );

      await seedManualAssetValuationAdjusts(db);

      final txs = await db.select(db.transactions).get();
      expect(txs, hasLength(1));
      expect(txs.single.id, 'tx-existing');
    },
  );

  test('skips non-manual asset types (securities, physical)', () async {
    await insertManualAsset(
      id: 'sec-aapl',
      type: AssetType.stock,
      lastPrice: Decimal.parse('200'),
    );
    await insertManualAsset(
      id: 'house-1',
      type: AssetType.realEstate,
      lastPrice: Decimal.parse('1000000'),
    );

    await seedManualAssetValuationAdjusts(db);

    final txs = await db.select(db.transactions).get();
    expect(txs, isEmpty);
  });
}
