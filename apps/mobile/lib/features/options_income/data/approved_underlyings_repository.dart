import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../core/sync/op_outbox.dart';
import '../../../data/db/app_database.dart';
import '../../../data/domain/sync_meta.dart';
import '../../../data/repositories/mutation_context.dart';
import '../../../domain/values/asset_market.dart';
import '../domain/approved_underlying.dart';

/// CRUD surface for `approved_underlyings`. Hard architectural rule (see
/// `docs/options-income.md` §1.2): the scanner reads from this list only.
class ApprovedUnderlyingsRepository {
  ApprovedUnderlyingsRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
  })  : _db = db,
        _outbox = outbox,
        _stamper = stamper;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;

  static const String _tableName = 'approved_underlyings';

  Stream<List<ApprovedUnderlying>> watchActive(String ownerUserId) {
    final query = _db.select(_db.approvedUnderlyings)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.symbol)]);
    return query
        .watch()
        .map((rows) => rows.map(_rowToDomain).toList(growable: false));
  }

  Future<List<ApprovedUnderlying>> listActive(String ownerUserId) async {
    final query = _db.select(_db.approvedUnderlyings)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.symbol)]);
    final rows = await query.get();
    return rows.map(_rowToDomain).toList(growable: false);
  }

  Future<ApprovedUnderlying> add({
    required String symbol,
    required AssetMarket market,
    bool allowPut = true,
    bool allowCall = true,
    Decimal? maxBuyPrice,
    Decimal? minSellPrice,
    String? notes,
  }) async {
    final stamp = await _stamper.stamp();
    final normalizedSymbol = symbol.trim().toUpperCase();
    final id = ApprovedUnderlying.idFor(
      market: market,
      symbol: normalizedSymbol,
    );

    final companion = ApprovedUnderlyingsCompanion.insert(
      id: id,
      symbol: normalizedSymbol,
      market: market.wire,
      allowPut: Value(allowPut),
      allowCall: Value(allowCall),
      maxBuyPrice: Value(maxBuyPrice),
      minSellPrice: Value(minSellPrice),
      notes: Value(notes),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
      deletedAt: const Value(null),
    );

    await _db.transaction(() async {
      await _db
          .into(_db.approvedUnderlyings)
          .insertOnConflictUpdate(companion);
      await _outbox.enqueue(table: _tableName, rowId: id);
    });

    return ApprovedUnderlying(
      id: id,
      symbol: normalizedSymbol,
      market: market,
      allowPut: allowPut,
      allowCall: allowCall,
      maxBuyPrice: maxBuyPrice,
      minSellPrice: minSellPrice,
      notes: notes,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
  }

  Future<ApprovedUnderlying> update(ApprovedUnderlying item) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.approvedUnderlyings,
      )..where((t) => t.id.equals(item.id))).write(
        ApprovedUnderlyingsCompanion(
          allowPut: Value(item.allowPut),
          allowCall: Value(item.allowCall),
          maxBuyPrice: Value(item.maxBuyPrice),
          minSellPrice: Value(item.minSellPrice),
          notes: Value(item.notes),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: _tableName, rowId: item.id);
    });
    return item.copyWith(
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
  }

  Future<void> remove(ApprovedUnderlying item) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.approvedUnderlyings,
      )..where((t) => t.id.equals(item.id))).write(
        ApprovedUnderlyingsCompanion(
          deletedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: _tableName, rowId: item.id);
    });
  }
}

ApprovedUnderlying _rowToDomain(ApprovedUnderlyingRow row) {
  final market = assetMarketFromWire(row.market) ?? AssetMarket.unknown;
  return ApprovedUnderlying(
    id: row.id,
    symbol: row.symbol,
    market: market,
    allowPut: row.allowPut,
    allowCall: row.allowCall,
    maxBuyPrice: row.maxBuyPrice,
    minSellPrice: row.minSellPrice,
    notes: row.notes,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );
}

