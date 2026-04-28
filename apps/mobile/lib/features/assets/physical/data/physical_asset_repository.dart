import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/sync/op.dart';
import '../../../../data/db/app_database.dart';
import '../../../../data/domain/enums.dart';
import 'physical_asset.dart';
import 'physical_asset_meta.dart';
import 'sync_stamper.dart';

/// CRUD + valuation history for non-financial assets (real estate, vehicles).
///
/// Acts as the single mutation entry point so callers can't accidentally
/// forget the OpLog enqueue or the synthetic `valuationAdjust` transaction
/// that the analytics layer relies on.
class PhysicalAssetRepository {
  PhysicalAssetRepository({
    required AppDatabase db,
    required SyncStamper stamper,
    Uuid uuid = const Uuid(),
  })  : _db = db,
        _stamper = stamper,
        _uuid = uuid;

  final AppDatabase _db;
  final SyncStamper _stamper;
  final Uuid _uuid;

  static const Set<AssetType> _physicalTypes = {
    AssetType.realEstate,
    AssetType.vehicle,
  };

  // ---------- Reads ----------

  Future<List<PhysicalAsset>> listAll() async {
    final rows = await (_db.select(_db.assets)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.type.isInValues(_physicalTypes.toList()),
          )
          ..orderBy([
            (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          ]))
        .get();
    return rows.map(_wrap).whereType<PhysicalAsset>().toList(growable: false);
  }

  /// Reactive variant of [listAll]. Use from Riverpod stream providers so
  /// the UI rebuilds whenever any physical-asset row changes.
  Stream<List<PhysicalAsset>> watchAll() {
    final query = _db.select(_db.assets)
      ..where(
        (t) =>
            t.deletedAt.isNull() & t.type.isInValues(_physicalTypes.toList()),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
      ]);
    return query.watch().map(
          (rows) =>
              rows.map(_wrap).whereType<PhysicalAsset>().toList(growable: false),
        );
  }

  Future<PhysicalAsset?> getById(String id) async {
    final row = await (_db.select(_db.assets)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    return _wrap(row);
  }

  /// Returns the valuation history for [assetId] in chronological order.
  ///
  /// Includes a synthesised "purchase" point as the first entry so the
  /// UI chart never starts mid-air. Subsequent points are the rows in
  /// [Transactions] with `type = valuationAdjust`.
  Future<List<ValuationPoint>> getValuationHistory(String assetId) async {
    final asset = await getById(assetId);
    if (asset == null) return const [];

    final adjusts = await (_db.select(_db.transactions)
          ..where(
            (t) =>
                t.assetId.equals(assetId) &
                t.type.equalsValue(TransactionType.valuationAdjust) &
                t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.tradeDate)]))
        .get();

    final points = <ValuationPoint>[
      ValuationPoint(
        asOf: asset.purchaseDate,
        value: asset.purchasePrice,
        kind: ValuationPointKind.purchase,
      ),
      for (final tx in adjusts)
        ValuationPoint(
          asOf: tx.tradeDate,
          value: tx.price,
          kind: ValuationPointKind.manual,
          note: tx.note,
        ),
    ];
    return points;
  }

  // ---------- Writes ----------

  /// Insert a new real-estate asset. Returns the persisted [PhysicalAsset]
  /// so the caller can navigate straight to its detail page.
  Future<PhysicalAsset> createRealEstate({
    required String name,
    String? address,
    required String currency,
    required DateTime purchaseDate,
    required Decimal purchasePrice,
    Decimal? currentValuation,
    String? linkedLiabilityId,
    DateTime? now,
  }) {
    return _create(
      type: AssetType.realEstate,
      name: name,
      currency: currency,
      currentValuation: currentValuation ?? purchasePrice,
      meta: PhysicalAssetMeta(
        address: address,
        purchaseDate: purchaseDate,
        purchasePrice: purchasePrice,
        linkedLiabilityId: linkedLiabilityId,
      ),
      now: now,
    );
  }

  /// Insert a new vehicle asset.
  Future<PhysicalAsset> createVehicle({
    required String name,
    required String currency,
    required DateTime purchaseDate,
    required Decimal purchasePrice,
    Decimal? currentValuation,
    Decimal? annualResidualRate,
    bool autoDepreciation = true,
    DateTime? now,
  }) {
    return _create(
      type: AssetType.vehicle,
      name: name,
      currency: currency,
      currentValuation: currentValuation ?? purchasePrice,
      meta: PhysicalAssetMeta(
        purchaseDate: purchaseDate,
        purchasePrice: purchasePrice,
        annualResidualRate: annualResidualRate,
        autoDepreciation: autoDepreciation,
      ),
      now: now,
    );
  }

  /// Manual valuation update.
  ///
  /// Atomically: bumps `Assets.lastPrice` / `lastPriceAt`, inserts a
  /// `valuationAdjust` transaction so the change is visible in the history,
  /// and enqueues sync ops for both rows.
  Future<void> updateValuation({
    required String assetId,
    required Decimal newValuation,
    required DateTime asOf,
    String? note,
    DateTime? now,
  }) async {
    final existing = await getById(assetId);
    if (existing == null) {
      throw StateError('Asset $assetId does not exist or was deleted');
    }

    await _stamper.runTransaction(() async {
      final assetStamp = await _stamper.stamp(now: now);
      await (_db.update(_db.assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(
          lastPrice: Value(newValuation),
          lastPriceAt: Value(asOf),
          updatedAt: Value(assetStamp.updatedAt),
          updatedByDevice: Value(_stamper.deviceId),
          hlc: Value(assetStamp.hlc),
        ),
      );
      await _stamper.enqueue(
        opId: _uuid.v4(),
        tableName: 'assets',
        rowId: assetId,
        opType: OpType.update,
        hlc: assetStamp.hlc,
        fieldsDiff: <String, Object?>{
          'last_price': newValuation.toString(),
          'last_price_at': asOf.toUtc().toIso8601String(),
          'updated_at': assetStamp.updatedAt.toIso8601String(),
          'updated_by_device': _stamper.deviceId,
          'hlc': assetStamp.hlc.toString(),
        },
      );

      final txStamp = await _stamper.stamp(now: now);
      final txId = _uuid.v4();
      // Quantity is fixed at 1 — physical assets are unitary and the
      // analytics layer treats `valuationAdjust` rows as authoritative
      // mark-to-market events on the underlying asset, not as quantity
      // changes.
      final txQuantity = Decimal.one;
      await _db.into(_db.transactions).insert(
            TransactionsCompanion.insert(
              id: txId,
              accountId: assetId,
              assetId: Value(assetId),
              type: TransactionType.valuationAdjust,
              quantity: txQuantity,
              price: newValuation,
              currency: existing.currency,
              tradeDate: asOf,
              note: Value(note),
              ownerUserId: _stamper.userId,
              updatedAt: txStamp.updatedAt,
              updatedByDevice: _stamper.deviceId,
              hlc: txStamp.hlc,
            ),
          );
      await _stamper.enqueue(
        opId: _uuid.v4(),
        tableName: 'transactions',
        rowId: txId,
        opType: OpType.insert,
        hlc: txStamp.hlc,
        fieldsDiff: <String, Object?>{
          'id': txId,
          'account_id': assetId,
          'asset_id': assetId,
          'type': TransactionType.valuationAdjust.name,
          'quantity': txQuantity.toString(),
          'price': newValuation.toString(),
          'currency': existing.currency,
          'trade_date': asOf.toUtc().toIso8601String(),
          'note': ?note,
          'owner_user_id': _stamper.userId,
          'updated_at': txStamp.updatedAt.toIso8601String(),
          'updated_by_device': _stamper.deviceId,
          'hlc': txStamp.hlc.toString(),
        },
      );
    });
  }

  /// Soft-delete the asset. The row stays in the table with `deleted_at`
  /// populated so peers receive the delete during the next pull.
  Future<void> delete(String assetId, {DateTime? now}) async {
    await _stamper.runTransaction(() async {
      final stamp = await _stamper.stamp(now: now);
      await (_db.update(_db.assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(
          deletedAt: Value(stamp.updatedAt),
          updatedAt: Value(stamp.updatedAt),
          updatedByDevice: Value(_stamper.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _stamper.enqueue(
        opId: _uuid.v4(),
        tableName: 'assets',
        rowId: assetId,
        opType: OpType.delete,
        hlc: stamp.hlc,
        fieldsDiff: null,
      );
    });
  }

  /// Update the metadata-only fields (address, residual rate, link, etc.).
  /// Does NOT change the current valuation — that goes through
  /// [updateValuation] so the history stays accurate.
  Future<void> updateMetadata({
    required String assetId,
    required PhysicalAssetMeta meta,
    String? name,
    DateTime? now,
  }) async {
    await _stamper.runTransaction(() async {
      final stamp = await _stamper.stamp(now: now);
      final encoded = meta.encode();
      await (_db.update(_db.assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(
          name: name == null ? const Value.absent() : Value(name),
          metadataJson: Value(encoded),
          updatedAt: Value(stamp.updatedAt),
          updatedByDevice: Value(_stamper.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _stamper.enqueue(
        opId: _uuid.v4(),
        tableName: 'assets',
        rowId: assetId,
        opType: OpType.update,
        hlc: stamp.hlc,
        fieldsDiff: <String, Object?>{
          'name': ?name,
          'metadata_json': encoded,
          'updated_at': stamp.updatedAt.toIso8601String(),
          'updated_by_device': _stamper.deviceId,
          'hlc': stamp.hlc.toString(),
        },
      );
    });
  }

  // ---------- Internals ----------

  PhysicalAsset? _wrap(AssetRow row) {
    if (!_physicalTypes.contains(row.type)) return null;
    final meta = PhysicalAssetMeta.tryDecode(row.metadataJson);
    if (meta == null) return null;
    return PhysicalAsset(row: row, meta: meta);
  }

  Future<PhysicalAsset> _create({
    required AssetType type,
    required String name,
    required String currency,
    required Decimal currentValuation,
    required PhysicalAssetMeta meta,
    DateTime? now,
  }) async {
    final id = _uuid.v4();
    final encoded = meta.encode();

    await _stamper.runTransaction(() async {
      final stamp = await _stamper.stamp(now: now);
      // `symbol` is required on the Assets table but only meaningful for
      // securities. We reuse the row id as the symbol so it's stable and
      // unique without leaking PII into a fielded column.
      await _db.into(_db.assets).insert(
            AssetsCompanion.insert(
              id: id,
              type: type,
              symbol: id,
              currency: currency,
              name: Value(name),
              lastPrice: Value(currentValuation),
              lastPriceAt: Value(stamp.updatedAt),
              metadataJson: Value(encoded),
              ownerUserId: _stamper.userId,
              updatedAt: stamp.updatedAt,
              updatedByDevice: _stamper.deviceId,
              hlc: stamp.hlc,
            ),
          );
      await _stamper.enqueue(
        opId: _uuid.v4(),
        tableName: 'assets',
        rowId: id,
        opType: OpType.insert,
        hlc: stamp.hlc,
        fieldsDiff: <String, Object?>{
          'id': id,
          'type': type.name,
          'symbol': id,
          'currency': currency,
          'name': name,
          'last_price': currentValuation.toString(),
          'last_price_at': stamp.updatedAt.toIso8601String(),
          'metadata_json': encoded,
          'owner_user_id': _stamper.userId,
          'updated_at': stamp.updatedAt.toIso8601String(),
          'updated_by_device': _stamper.deviceId,
          'hlc': stamp.hlc.toString(),
        },
      );
    });

    final created = await getById(id);
    if (created == null) {
      throw StateError('Asset $id was inserted but could not be re-read');
    }
    return created;
  }
}
