import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../../../core/sync/op.dart';
import '../../../../core/sync/op_outbox.dart';
import '../../../../data/db/app_database.dart';
import '../../../../data/domain/enums.dart';
import '../../../../data/repositories/mutation_context.dart';
import 'physical_asset.dart';
import 'physical_asset_meta.dart';

/// CRUD + valuation history for non-financial assets (real estate, vehicles).
///
/// Acts as the single mutation entry point so callers can't accidentally
/// forget the sync `Op` enqueue or the synthetic `valuationAdjust`
/// transaction that the analytics layer relies on. Mirrors the contract
/// of [ManualAssetRepository] / [LiabilityRepository] from FIR-44 / FIR-47:
/// each write happens inside a Drift transaction that *both* mutates the
/// row and enqueues a corresponding [Op].
class PhysicalAssetRepository {
  PhysicalAssetRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    Uuid uuid = const Uuid(),
  })  : _db = db,
        _outbox = outbox,
        _stamper = stamper,
        _uuid = uuid;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
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
            (t) =>
                OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          ]))
        .get();
    return rows.map(_wrap).whereType<PhysicalAsset>().toList(growable: false);
  }

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
          (rows) => rows
              .map(_wrap)
              .whereType<PhysicalAsset>()
              .toList(growable: false),
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
  /// Includes a synthesised "purchase" point as the first entry so the UI
  /// chart never starts mid-air. Subsequent points are rows in
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

  Future<PhysicalAsset> createRealEstate({
    required String name,
    String? address,
    required String currency,
    required DateTime purchaseDate,
    required Decimal purchasePrice,
    Decimal? currentValuation,
    String? linkedLiabilityId,
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
    );
  }

  Future<PhysicalAsset> createVehicle({
    required String name,
    required String currency,
    required DateTime purchaseDate,
    required Decimal purchasePrice,
    Decimal? currentValuation,
    Decimal? annualResidualRate,
    bool autoDepreciation = true,
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
    );
  }

  /// Manual valuation update.
  ///
  /// Atomically: bumps `Assets.lastPrice` / `lastPriceAt`, inserts a
  /// `valuationAdjust` transaction so the change is visible in the
  /// history, and enqueues sync ops for both rows.
  Future<void> updateValuation({
    required String assetId,
    required Decimal newValuation,
    required DateTime asOf,
    String? note,
  }) async {
    final existing = await getById(assetId);
    if (existing == null) {
      throw StateError('Asset $assetId does not exist or was deleted');
    }

    await _db.transaction(() async {
      final assetStamp = await _stamper.stamp();
      await (_db.update(_db.assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(
          lastPrice: Value(newValuation),
          lastPriceAt: Value(asOf),
          updatedAt: Value(assetStamp.now),
          updatedByDevice: Value(assetStamp.deviceId),
          hlc: Value(assetStamp.hlc),
        ),
      );
      await _enqueue(
        tableName: 'assets',
        rowId: assetId,
        opType: OpType.update,
        stamp: assetStamp,
        fields: <String, Object?>{
          'last_price': newValuation.toString(),
          'last_price_at': asOf.toUtc().toIso8601String(),
          'updated_at': assetStamp.now.toUtc().toIso8601String(),
          'updated_by_device': assetStamp.deviceId,
          'hlc': assetStamp.hlc.toString(),
        },
      );

      final txStamp = await _stamper.stamp();
      final txId = _uuid.v4();
      // Quantity is fixed at 1 — physical assets are unitary, and the
      // analytics layer treats `valuationAdjust` rows as authoritative
      // mark-to-market events on the underlying asset rather than
      // quantity changes.
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
              ownerUserId: txStamp.ownerUserId,
              updatedAt: txStamp.now,
              updatedByDevice: txStamp.deviceId,
              hlc: txStamp.hlc,
            ),
          );
      await _enqueue(
        tableName: 'transactions',
        rowId: txId,
        opType: OpType.insert,
        stamp: txStamp,
        fields: <String, Object?>{
          'id': txId,
          'account_id': assetId,
          'asset_id': assetId,
          'type': TransactionType.valuationAdjust.name,
          'quantity': txQuantity.toString(),
          'price': newValuation.toString(),
          'currency': existing.currency,
          'trade_date': asOf.toUtc().toIso8601String(),
          'note': ?note,
          'owner_user_id': txStamp.ownerUserId,
          'updated_at': txStamp.now.toUtc().toIso8601String(),
          'updated_by_device': txStamp.deviceId,
          'hlc': txStamp.hlc.toString(),
        },
      );
    });
  }

  /// Soft-delete the asset. The row stays in the table with `deleted_at`
  /// populated so peers receive the delete during the next pull.
  Future<void> delete(String assetId) async {
    await _db.transaction(() async {
      final stamp = await _stamper.stamp();
      await (_db.update(_db.assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(
          deletedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _enqueue(
        tableName: 'assets',
        rowId: assetId,
        opType: OpType.delete,
        stamp: stamp,
        fields: null,
      );
    });
  }

  /// Update metadata-only fields (address, residual rate, link, etc.).
  /// Does NOT change the current valuation — that goes through
  /// [updateValuation] so the history stays accurate.
  Future<void> updateMetadata({
    required String assetId,
    required PhysicalAssetMeta meta,
    String? name,
  }) async {
    final encoded = meta.encode();
    await _db.transaction(() async {
      final stamp = await _stamper.stamp();
      await (_db.update(_db.assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(
          name: name == null ? const Value.absent() : Value(name),
          metadataJson: Value(encoded),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _enqueue(
        tableName: 'assets',
        rowId: assetId,
        opType: OpType.update,
        stamp: stamp,
        fields: <String, Object?>{
          'name': ?name,
          'metadata_json': encoded,
          'updated_at': stamp.now.toUtc().toIso8601String(),
          'updated_by_device': stamp.deviceId,
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
  }) async {
    final id = _uuid.v4();
    final encoded = meta.encode();

    await _db.transaction(() async {
      final stamp = await _stamper.stamp();
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
              lastPriceAt: Value(stamp.now),
              metadataJson: Value(encoded),
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
          );
      await _enqueue(
        tableName: 'assets',
        rowId: id,
        opType: OpType.insert,
        stamp: stamp,
        fields: <String, Object?>{
          'id': id,
          'type': type.name,
          'symbol': id,
          'currency': currency,
          'name': name,
          'last_price': currentValuation.toString(),
          'last_price_at': stamp.now.toUtc().toIso8601String(),
          'metadata_json': encoded,
          'owner_user_id': stamp.ownerUserId,
          'updated_at': stamp.now.toUtc().toIso8601String(),
          'updated_by_device': stamp.deviceId,
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

  Future<void> _enqueue({
    required String tableName,
    required String rowId,
    required OpType opType,
    required MutationStamp stamp,
    required Map<String, Object?>? fields,
  }) async {
    final op = Op(
      opId: _uuid.v4(),
      tableName: tableName,
      rowId: rowId,
      opType: opType,
      fieldsDiff: fields,
      hlc: stamp.hlc,
      deviceId: stamp.deviceId,
    );
    if (validateOpForQueue(op) != null) return;
    await _outbox.enqueue(op);
  }
}
