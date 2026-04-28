import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../core/sync/op.dart';
import '../../core/sync/op_outbox.dart';
import '../db/app_database.dart';
import '../domain/asset.dart';
import '../domain/enums.dart';
import '../domain/manual_asset_metadata.dart';
import '../domain/sync_meta.dart';
import 'mutation_context.dart';

/// Read/write API for "manual valuation" [Asset] rows — those whose
/// current value is updated by the user instead of fetched from a market
/// feed. FIR-44 covers cash, bank deposits (term/demand) and 理财产品;
/// securities and crypto land in their own follow-up.
///
/// Every mutation lives in a Drift transaction that *both* writes the row
/// and enqueues a corresponding [Op] — same contract as
/// [AccountRepository], so peers see the change once the next sync cycle
/// drains the outbox.
class ManualAssetRepository {
  ManualAssetRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _uuid = uuid;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final Uuid _uuid;

  static const String _tableName = 'assets';

  // ---------- Reads ----------

  Stream<List<Asset>> watchManual() {
    final query = _db.select(_db.assets)
      ..where((t) => t.deletedAt.isNull())
      ..where(
        (t) =>
            t.type.isIn(kManualValuationAssetTypes.map((e) => e.name).toList()),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.type),
        (t) => OrderingTerm(expression: t.symbol),
      ]);
    return query.watch().map((rows) => rows.map(_toAsset).toList());
  }

  Future<Asset?> findById(String id) async {
    final row = await (_db.select(
      _db.assets,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toAsset(row);
  }

  // ---------- Cash ----------

  /// Adds a multi-currency cash balance held in [accountId].
  ///
  /// We use [currency] as the asset's `symbol` so the list view can show
  /// a stable badge (`USD`, `CNY`) without needing a separate column.
  Future<Asset> createCash({
    required String accountId,
    required String currency,
    required Decimal balance,
    String? nickname,
  }) async {
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    final metadata = CashMetadata(accountId: accountId);
    final companion = AssetsCompanion.insert(
      id: id,
      type: AssetType.cash,
      symbol: currency,
      currency: currency,
      name: Value(nickname ?? '$currency cash'),
      lastPrice: Value(balance),
      lastPriceAt: Value(stamp.now),
      metadataJson: Value(metadata.encode()),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
    await _insertWithOp(
      id: id,
      stamp: stamp,
      companion: companion,
      type: AssetType.cash,
      symbol: currency,
      currency: currency,
      name: nickname ?? '$currency cash',
      lastPrice: balance,
      lastPriceAt: stamp.now,
      metadataJson: metadata.encode(),
    );
    return (await findById(id))!;
  }

  // ---------- Deposits ----------

  Future<Asset> createDeposit({
    required String accountId,
    required AssetType type,
    required String name,
    required String currency,
    required Decimal principal,
    required Decimal interestRate,
    DateTime? startDate,
    DateTime? maturityDate,
    bool autoRenew = false,
    Decimal? currentValuation,
  }) async {
    assert(
      type == AssetType.bankDepositTerm || type == AssetType.bankDepositDemand,
      'createDeposit only accepts bankDepositTerm / bankDepositDemand',
    );
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    final metadata = DepositMetadata(
      accountId: accountId,
      principal: principal,
      interestRate: interestRate,
      startDate: startDate,
      maturityDate: maturityDate,
      autoRenew: autoRenew,
    );
    final price = currentValuation ?? principal;
    final companion = AssetsCompanion.insert(
      id: id,
      type: type,
      symbol: name,
      currency: currency,
      name: Value(name),
      lastPrice: Value(price),
      lastPriceAt: Value(stamp.now),
      metadataJson: Value(metadata.encode()),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
    await _insertWithOp(
      id: id,
      stamp: stamp,
      companion: companion,
      type: type,
      symbol: name,
      currency: currency,
      name: name,
      lastPrice: price,
      lastPriceAt: stamp.now,
      metadataJson: metadata.encode(),
    );
    return (await findById(id))!;
  }

  // ---------- Wealth products ----------

  Future<Asset> createWealthProduct({
    required String accountId,
    required String name,
    required String currency,
    required Decimal principal,
    required Decimal expectedAnnualReturn,
    DateTime? startDate,
    DateTime? maturityDate,
    String? issuer,
    String? productCode,
    Decimal? currentValuation,
  }) async {
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    final metadata = WealthProductMetadata(
      accountId: accountId,
      principal: principal,
      expectedAnnualReturn: expectedAnnualReturn,
      startDate: startDate,
      maturityDate: maturityDate,
      issuer: issuer,
      productCode: productCode,
    );
    final price = currentValuation ?? principal;
    final symbol = productCode ?? name;
    final companion = AssetsCompanion.insert(
      id: id,
      type: AssetType.wealthProduct,
      symbol: symbol,
      currency: currency,
      name: Value(name),
      lastPrice: Value(price),
      lastPriceAt: Value(stamp.now),
      metadataJson: Value(metadata.encode()),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
    await _insertWithOp(
      id: id,
      stamp: stamp,
      companion: companion,
      type: AssetType.wealthProduct,
      symbol: symbol,
      currency: currency,
      name: name,
      lastPrice: price,
      lastPriceAt: stamp.now,
      metadataJson: metadata.encode(),
    );
    return (await findById(id))!;
  }

  // ---------- Generic update / valuation / delete ----------

  /// Updates the manually-tracked valuation of an existing asset, leaving
  /// the rest of its fields alone. The deposit/wealth-product specifics
  /// stay in `metadataJson`; only `last_price` + `last_price_at` change.
  Future<Asset> updateValuation({
    required String id,
    required Decimal newValuation,
  }) async {
    final stamp = await _stamper.stamp();
    final companion = AssetsCompanion(
      lastPrice: Value(newValuation),
      lastPriceAt: Value(stamp.now),
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );
    final diff = <String, Object?>{
      'last_price': newValuation.toString(),
      'last_price_at': stamp.now.toUtc().toIso8601String(),
      'updated_at': stamp.now.toUtc().toIso8601String(),
      'updated_by_device': stamp.deviceId,
      'hlc': stamp.hlc.toString(),
    };
    await _db.transaction(() async {
      await (_db.update(
        _db.assets,
      )..where((t) => t.id.equals(id))).write(companion);
      await _enqueue(
        opType: OpType.update,
        rowId: id,
        fields: diff,
        stamp: stamp,
      );
    });
    return (await findById(id))!;
  }

  /// Replaces the typed metadata blob (e.g. updating a deposit's interest
  /// rate or maturity date). Callers normally compute the new wrapper from
  /// the old via `copyWith` before passing it here.
  Future<Asset> updateMetadata({
    required String id,
    required ManualAssetMetadata metadata,
  }) async {
    final stamp = await _stamper.stamp();
    final encoded = metadata.encode();
    final companion = AssetsCompanion(
      metadataJson: Value(encoded),
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );
    final diff = <String, Object?>{
      'metadata_json': encoded,
      'updated_at': stamp.now.toUtc().toIso8601String(),
      'updated_by_device': stamp.deviceId,
      'hlc': stamp.hlc.toString(),
    };
    await _db.transaction(() async {
      await (_db.update(
        _db.assets,
      )..where((t) => t.id.equals(id))).write(companion);
      await _enqueue(
        opType: OpType.update,
        rowId: id,
        fields: diff,
        stamp: stamp,
      );
    });
    return (await findById(id))!;
  }

  Future<Asset> updateBasics({
    required String id,
    String? name,
    String? note,
  }) async {
    final stamp = await _stamper.stamp();
    final diff = <String, Object?>{};
    var companion = AssetsCompanion(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );
    if (name != null) {
      companion = companion.copyWith(name: Value(name));
      diff['name'] = name;
    }
    if (diff.isEmpty) return (await findById(id))!;
    diff['updated_at'] = stamp.now.toUtc().toIso8601String();
    diff['updated_by_device'] = stamp.deviceId;
    diff['hlc'] = stamp.hlc.toString();
    await _db.transaction(() async {
      await (_db.update(
        _db.assets,
      )..where((t) => t.id.equals(id))).write(companion);
      await _enqueue(
        opType: OpType.update,
        rowId: id,
        fields: diff,
        stamp: stamp,
      );
    });
    return (await findById(id))!;
  }

  Future<void> softDelete(String id) async {
    final stamp = await _stamper.stamp();
    final companion = AssetsCompanion(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
      deletedAt: Value(stamp.now),
    );
    await _db.transaction(() async {
      await (_db.update(
        _db.assets,
      )..where((t) => t.id.equals(id))).write(companion);
      await _enqueue(
        opType: OpType.delete,
        rowId: id,
        fields: null,
        stamp: stamp,
      );
    });
  }

  // ---------- Helpers ----------

  Future<void> _insertWithOp({
    required String id,
    required MutationStamp stamp,
    required AssetsCompanion companion,
    required AssetType type,
    required String symbol,
    required String currency,
    required String? name,
    required Decimal? lastPrice,
    required DateTime? lastPriceAt,
    required String? metadataJson,
  }) async {
    final fields = <String, Object?>{
      'id': id,
      'type': type.name,
      'symbol': symbol,
      'currency': currency,
      'name': name,
      'last_price': lastPrice?.toString(),
      'last_price_at': lastPriceAt?.toUtc().toIso8601String(),
      'metadata_json': metadataJson,
      'owner_user_id': stamp.ownerUserId,
      'updated_at': stamp.now.toUtc().toIso8601String(),
      'updated_by_device': stamp.deviceId,
      'hlc': stamp.hlc.toString(),
    };
    await _db.transaction(() async {
      await _db.into(_db.assets).insert(companion);
      await _enqueue(
        opType: OpType.insert,
        rowId: id,
        fields: fields,
        stamp: stamp,
      );
    });
  }

  Future<void> _enqueue({
    required OpType opType,
    required String rowId,
    required Map<String, Object?>? fields,
    required MutationStamp stamp,
  }) async {
    final op = Op(
      opId: _uuid.v4(),
      tableName: _tableName,
      rowId: rowId,
      opType: opType,
      fieldsDiff: fields,
      hlc: stamp.hlc,
      deviceId: stamp.deviceId,
    );
    await _outbox.enqueue(op);
  }

  Asset _toAsset(AssetRow row) {
    return Asset(
      id: row.id,
      type: row.type,
      symbol: row.symbol,
      currency: row.currency,
      name: row.name,
      market: row.market,
      industry: row.industry,
      region: row.region,
      isin: row.isin,
      lastPrice: row.lastPrice,
      lastPriceAt: row.lastPriceAt,
      logoUrl: row.logoUrl,
      metadataJson: row.metadataJson,
      sync: SyncMeta(
        ownerUserId: row.ownerUserId,
        updatedAt: row.updatedAt,
        updatedByDevice: row.updatedByDevice,
        hlc: row.hlc,
        deletedAt: row.deletedAt,
      ),
    );
  }
}

/// Convenience accessor for the typed metadata wrapper.
extension AssetManualMetadata on Asset {
  ManualAssetMetadata? get manualMetadata =>
      ManualAssetMetadata.decode(metadataJson);
}
