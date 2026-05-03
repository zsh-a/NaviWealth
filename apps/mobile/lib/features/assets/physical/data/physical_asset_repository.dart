import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../../../core/sync/op.dart';
import '../../../../core/sync/op_outbox.dart';
import '../../../../data/db/app_database.dart';
import '../../../../data/domain/enums.dart';
import '../../../../data/repositories/account_repository.dart';
import '../../../../data/repositories/journal_entry_builders.dart';
import '../../../../data/repositories/journal_entry_repository.dart';
import '../../../../data/repositories/mutation_context.dart';
import '../../../../data/repositories/price_repository.dart';
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
    required PriceRepository priceRepo,
    JournalEntryRepository? journalEntryRepo,
    Uuid uuid = const Uuid(),
  })  : _db = db,
        _outbox = outbox,
        _stamper = stamper,
        _priceRepo = priceRepo,
        _journalEntryRepo = journalEntryRepo,
        _uuid = uuid;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final PriceRepository _priceRepo;
  final JournalEntryRepository? _journalEntryRepo;
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
  /// chart never starts mid-air. Subsequent points are rows in `prices`.
  Future<List<ValuationPoint>> getValuationHistory(String assetId) async {
    final asset = await getById(assetId);
    if (asset == null) return const [];

    final prices = await (_db.select(_db.prices)
          ..where((t) => t.unit.equals(assetId))
          ..where((t) => t.quoteCurrency.equals(asset.currency))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.observedOn)]))
        .get();

    final points = <ValuationPoint>[
      ValuationPoint(
        asOf: asset.purchaseDate,
        value: asset.purchasePrice,
        kind: ValuationPointKind.purchase,
      ),
      for (final price in prices)
        ValuationPoint(
          asOf: price.observedOn,
          value: price.perUnit,
          kind: ValuationPointKind.manual,
          note: price.source,
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
  /// Appends a price observation and a balanced valuation journal entry.
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

    await _priceRepo.record(
      unit: assetId,
      quoteCurrency: existing.currency,
      observedOn: asOf,
      perUnit: newValuation,
      source: note ?? 'manual',
    );
    await _recordValuationJournal(
      assetId: assetId,
      currency: existing.currency,
      valuation: newValuation,
      asOf: asOf,
      ownerUserId: existing.row.ownerUserId,
      narration: note,
    );
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
    await _priceRepo.record(
      unit: id,
      quoteCurrency: currency,
      observedOn: created.purchaseDate,
      perUnit: currentValuation,
      source: 'manual',
    );
    await _recordValuationJournal(
      assetId: id,
      currency: currency,
      valuation: currentValuation,
      asOf: created.purchaseDate,
      ownerUserId: created.row.ownerUserId,
    );
    return created;
  }

  Future<void> _recordValuationJournal({
    required String assetId,
    required String currency,
    required Decimal valuation,
    required DateTime asOf,
    required String ownerUserId,
    String? narration,
  }) async {
    final jeRepo = _journalEntryRepo;
    if (jeRepo == null) return;
    final equityAccountId = AccountRepository.systemAccountIdForPath(
      'equity:adjustments',
      ownerUserId: ownerUserId,
    );
    final build = JournalEntryBuilders.valuationAdjust(
      date: asOf,
      accountId: assetId,
      equityAccountId: equityAccountId,
      assetUnit: assetId,
      quantity: Decimal.one,
      newValuation: valuation,
      currency: currency,
      narration: narration,
    );
    await jeRepo.create(entry: build.entry, postings: build.postings);
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
