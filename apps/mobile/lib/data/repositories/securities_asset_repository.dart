import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../core/sync/op.dart';
import '../../core/sync/op_outbox.dart';
import '../../domain/values/asset_market.dart';
import '../db/app_database.dart';
import '../domain/asset.dart';
import '../domain/enums.dart';
import '../domain/sync_meta.dart';
import 'mutation_context.dart';

/// Read/write API for securities-class [Asset] rows — stocks, ETFs, mutual
/// funds, bonds and crypto (everything in [kSecuritiesAssetTypes]).
///
/// Sibling to [ManualAssetRepository], which owns the cash / deposit /
/// wealth-product slice. The two repos are kept apart because they have
/// fundamentally different identity schemes: securities use a deterministic
/// `<market>:<symbol>` id (so the same instrument lines up across devices
/// and survives sync without a UUID mapping table), whereas manual
/// valuation rows are UUIDs the user can rename freely.
///
/// Every mutation here lives in a single Drift transaction that *both*
/// writes the `assets` row and enqueues a sync [Op] — same contract as
/// [AccountRepository] and [ManualAssetRepository] — so peers see the new
/// asset on the next outbox drain.
class SecuritiesAssetRepository {
  SecuritiesAssetRepository({
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

  static const String _tableName = 'assets';

  // ---------- Reads ----------

  Future<Asset?> findById(String id) async {
    final row = await (_db.select(_db.assets)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toAsset(row);
  }

  /// Resolves a security by its (market, symbol) natural key, ignoring
  /// soft-deleted rows. Lookup is by deterministic id rather than by
  /// scanning `(market, symbol)` so we hit the primary key index.
  Future<Asset?> findBySymbolAndMarket(String symbol, AssetMarket market) async {
    final id = Asset.idFor(market, symbol);
    final row = await (_db.select(_db.assets)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .getSingleOrNull();
    return row == null ? null : _toAsset(row);
  }

  /// Live stream of non-deleted securities, ordered by market then symbol
  /// for stable list rendering. [types] filters to a subset of asset
  /// classes; null/empty means "everything in [kSecuritiesAssetTypes]".
  Stream<List<Asset>> watchSecurities({Set<AssetType>? types}) {
    final filter = (types == null || types.isEmpty)
        ? kSecuritiesAssetTypes
        : types;
    final query = _db.select(_db.assets)
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.market.isNotNull())
      ..where((t) => t.type.isIn(filter.map((e) => e.name).toList()))
      ..orderBy([
        (t) => OrderingTerm(expression: t.market),
        (t) => OrderingTerm(expression: t.symbol),
      ]);
    return query.watch().map((rows) => rows.map(_toAsset).toList());
  }

  // ---------- Writes ----------

  /// Idempotent on `(market, symbol)`. If no row exists for the derived
  /// id, insert one and queue an `insert` op. If a row already exists,
  /// update only the fields the caller actually supplied (anything left
  /// null is treated as "no change") and queue an `update` op carrying
  /// just the diff. A no-op call (existing row + no fields to change)
  /// returns the row without queuing anything — the protocol rejects
  /// empty updates and we'd rather surface this as a noop than push a
  /// stale op.
  Future<Asset> upsertSecurity({
    required String symbol,
    required AssetMarket market,
    required AssetType type,
    required String currency,
    String? name,
    String? isin,
    String? industry,
    String? region,
    String? logoUrl,
  }) async {
    if (!kSecuritiesAssetTypes.contains(type)) {
      throw ArgumentError.value(
        type,
        'type',
        'must be one of $kSecuritiesAssetTypes',
      );
    }
    final id = Asset.idFor(market, symbol);
    final existing = await findById(id);
    if (existing == null) {
      return _insert(
        id: id,
        market: market,
        symbol: symbol,
        type: type,
        currency: currency,
        name: name,
        isin: isin,
        industry: industry,
        region: region,
        logoUrl: logoUrl,
      );
    }
    return _update(
      existing: existing,
      type: type,
      currency: currency,
      name: name,
      isin: isin,
      industry: industry,
      region: region,
      logoUrl: logoUrl,
    );
  }

  /// Fill **only** fields that are still null on the existing row. Used by
  /// FIR-78's "同步元数据" / "从网络导入" actions: the network is treated as a
  /// best-effort metadata enrichment, never as a source of truth, so any
  /// field the user has already touched is left alone. Currency is
  /// non-nullable in the schema and so is never overwritten through this
  /// path — callers that genuinely need to change a currency must go
  /// through [upsertSecurity] (or the type-specific edit form) and accept
  /// the explicit overwrite.
  ///
  /// A no-op call (everything already set) returns the row untouched and
  /// does **not** queue an update op, mirroring the contract of
  /// [upsertSecurity]'s update path.
  Future<Asset> enrichMetadata({
    required String id,
    String? name,
    String? isin,
    String? industry,
    String? region,
    String? logoUrl,
  }) async {
    final existing = await findById(id);
    if (existing == null) {
      throw StateError('asset not found: $id');
    }

    final diff = <String, Object?>{};
    var pending = const AssetsCompanion();

    if (name != null &&
        name.isNotEmpty &&
        (existing.name == null || existing.name!.isEmpty)) {
      pending = pending.copyWith(name: Value(name));
      diff['name'] = name;
    }
    if (isin != null && isin.isNotEmpty && existing.isin == null) {
      pending = pending.copyWith(isin: Value(isin));
      diff['isin'] = isin;
    }
    if (industry != null &&
        industry.isNotEmpty &&
        existing.industry == null) {
      pending = pending.copyWith(industry: Value(industry));
      diff['industry'] = industry;
    }
    if (region != null && region.isNotEmpty && existing.region == null) {
      pending = pending.copyWith(region: Value(region));
      diff['region'] = region;
    }
    if (logoUrl != null &&
        logoUrl.isNotEmpty &&
        existing.logoUrl == null) {
      pending = pending.copyWith(logoUrl: Value(logoUrl));
      diff['logo_url'] = logoUrl;
    }

    if (diff.isEmpty) return existing;

    final stamp = await _stamper.stamp();
    pending = pending.copyWith(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );
    diff['updated_at'] = stamp.now.toUtc().toIso8601String();
    diff['updated_by_device'] = stamp.deviceId;
    diff['hlc'] = stamp.hlc.toString();

    await _db.transaction(() async {
      await (_db.update(_db.assets)..where((t) => t.id.equals(existing.id)))
          .write(pending);
      await _enqueue(
        opType: OpType.update,
        rowId: existing.id,
        fields: diff,
        stamp: stamp,
      );
    });
    return (await findById(existing.id))!;
  }

  /// Soft-delete by deterministic id. Tombstones the row (`deletedAt =
  /// now`) and queues a `delete` op so peers honour LWW.
  Future<void> softDelete(String id) async {
    final stamp = await _stamper.stamp();
    final companion = AssetsCompanion(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
      deletedAt: Value(stamp.now),
    );
    await _db.transaction(() async {
      await (_db.update(_db.assets)..where((t) => t.id.equals(id)))
          .write(companion);
      await _enqueue(
        opType: OpType.delete,
        rowId: id,
        fields: null,
        stamp: stamp,
      );
    });
  }

  // ---------- Helpers ----------

  Future<Asset> _insert({
    required String id,
    required AssetMarket market,
    required String symbol,
    required AssetType type,
    required String currency,
    required String? name,
    required String? isin,
    required String? industry,
    required String? region,
    required String? logoUrl,
  }) async {
    final stamp = await _stamper.stamp();
    final companion = AssetsCompanion.insert(
      id: id,
      type: type,
      symbol: symbol,
      currency: currency,
      name: Value(name),
      market: Value(market.wire),
      industry: Value(industry),
      region: Value(region),
      isin: Value(isin),
      logoUrl: Value(logoUrl),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
    final fields = <String, Object?>{
      'id': id,
      'type': type.name,
      'symbol': symbol,
      'currency': currency,
      'name': name,
      'market': market.wire,
      'industry': industry,
      'region': region,
      'isin': isin,
      'logo_url': logoUrl,
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
    return (await findById(id))!;
  }

  Future<Asset> _update({
    required Asset existing,
    required AssetType type,
    required String currency,
    required String? name,
    required String? isin,
    required String? industry,
    required String? region,
    required String? logoUrl,
  }) async {
    final diff = <String, Object?>{};
    var pending = const AssetsCompanion();

    if (existing.type != type) {
      pending = pending.copyWith(type: Value(type));
      diff['type'] = type.name;
    }
    if (existing.currency != currency) {
      pending = pending.copyWith(currency: Value(currency));
      diff['currency'] = currency;
    }
    if (name != null && existing.name != name) {
      pending = pending.copyWith(name: Value(name));
      diff['name'] = name;
    }
    if (isin != null && existing.isin != isin) {
      pending = pending.copyWith(isin: Value(isin));
      diff['isin'] = isin;
    }
    if (industry != null && existing.industry != industry) {
      pending = pending.copyWith(industry: Value(industry));
      diff['industry'] = industry;
    }
    if (region != null && existing.region != region) {
      pending = pending.copyWith(region: Value(region));
      diff['region'] = region;
    }
    if (logoUrl != null && existing.logoUrl != logoUrl) {
      pending = pending.copyWith(logoUrl: Value(logoUrl));
      diff['logo_url'] = logoUrl;
    }

    if (diff.isEmpty) {
      // Nothing to record — return the existing row untouched. The protocol
      // rejects empty updates, so we *must* skip the outbox enqueue here.
      return existing;
    }

    final stamp = await _stamper.stamp();
    pending = pending.copyWith(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );
    diff['updated_at'] = stamp.now.toUtc().toIso8601String();
    diff['updated_by_device'] = stamp.deviceId;
    diff['hlc'] = stamp.hlc.toString();

    await _db.transaction(() async {
      await (_db.update(_db.assets)..where((t) => t.id.equals(existing.id)))
          .write(pending);
      await _enqueue(
        opType: OpType.update,
        rowId: existing.id,
        fields: diff,
        stamp: stamp,
      );
    });
    return (await findById(existing.id))!;
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
