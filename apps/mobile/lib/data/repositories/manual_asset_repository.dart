import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../core/sync/op.dart';
import '../../core/sync/op_outbox.dart';
import '../audit/event_log_writer.dart';
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
    EventLogWriter? eventLog,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _eventLog = eventLog ?? EventLogWriter(db: db, uuid: uuid),
       _uuid = uuid;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final EventLogWriter _eventLog;
  final Uuid _uuid;

  static const String _tableName = 'assets';
  static const String _transactionsTableName = 'transactions';

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
      accountId: accountId,
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
      accountId: accountId,
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
      accountId: accountId,
    );
    return (await findById(id))!;
  }

  // ---------- Generic update / valuation / delete ----------

  /// Append a [TransactionType.valuationAdjust] event recording a manual
  /// valuation change for [assetId].
  ///
  /// FIR-123: cash / deposit / wealth-product valuations used to flow
  /// straight into `assets.last_price` via in-place UPDATE, which made the
  /// "100 → 300" jump unanswerable ("where did the 200 come from?"). The
  /// new contract is event-sourced:
  ///
  ///   - A `valuationAdjust` row is appended with `quantity = 0` (no
  ///     position change), `price = newValuation`, `currency =
  ///     asset.currency`, `tradeDate = asOf ?? stamp.now`, and `accountId`
  ///     resolved from the asset's metadata blob.
  ///   - `assets.last_price` / `last_price_at` are still updated in the
  ///     same Drift transaction as a denormalized read cache, so existing
  ///     readers (dashboard, asset list) keep rendering without a query
  ///     rewrite. The transaction stream remains the source of truth — see
  ///     `NetWorthService._applyTransaction` which folds these rows into
  ///     the cash-class valuation line.
  ///   - Two outbox `Op`s are enqueued (one for the inserted transaction,
  ///     one for the cached `last_price` update). Both ride the same
  ///     Drift transaction so peers never observe a half-written change.
  ///   - An audit `field_changed` event is recorded so the local-only
  ///     domain event log keeps showing before/after on the asset row.
  Future<Asset> recordValuationAdjust({
    required String assetId,
    required Decimal newValuation,
    DateTime? asOf,
    String? reason,
  }) async {
    final stamp = await _stamper.stamp();
    final priorRow = await (_db.select(
      _db.assets,
    )..where((t) => t.id.equals(assetId))).getSingleOrNull();
    if (priorRow == null) {
      throw StateError('Asset $assetId does not exist');
    }
    final tradeDate = asOf ?? stamp.now;
    final txId = _uuid.v4();
    final txAccountId = _accountIdForAsset(priorRow);
    final assetCompanion = AssetsCompanion(
      lastPrice: Value(newValuation),
      lastPriceAt: Value(tradeDate),
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
    );
    final assetDiff = <String, Object?>{
      'last_price': newValuation.toString(),
      'last_price_at': tradeDate.toUtc().toIso8601String(),
      'updated_at': stamp.now.toUtc().toIso8601String(),
      'updated_by_device': stamp.deviceId,
      'hlc': stamp.hlc.toString(),
    };
    await _db.transaction(() async {
      await (_db.update(
        _db.assets,
      )..where((t) => t.id.equals(assetId))).write(assetCompanion);
      await _enqueue(
        opType: OpType.update,
        rowId: assetId,
        fields: assetDiff,
        stamp: stamp,
      );

      await _db
          .into(_db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: txId,
              accountId: txAccountId,
              assetId: Value(assetId),
              type: TransactionType.valuationAdjust,
              // Quantity = 0 distinguishes "manual cash-class valuation"
              // (no underlying unit) from the physical-asset flow which
              // uses quantity = 1 for unitary real-estate / vehicle rows.
              quantity: Decimal.zero,
              price: newValuation,
              currency: priorRow.currency,
              tradeDate: tradeDate,
              note: Value(reason),
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
          );
      await _enqueueTransaction(
        rowId: txId,
        fields: <String, Object?>{
          'id': txId,
          'account_id': txAccountId,
          'asset_id': assetId,
          'type': TransactionType.valuationAdjust.name,
          'quantity': '0',
          'price': newValuation.toString(),
          'currency': priorRow.currency,
          'trade_date': tradeDate.toUtc().toIso8601String(),
          'note': ?reason,
          'owner_user_id': stamp.ownerUserId,
          'updated_at': stamp.now.toUtc().toIso8601String(),
          'updated_by_device': stamp.deviceId,
          'hlc': stamp.hlc.toString(),
        },
        stamp: stamp,
      );
      await _eventLog.recordFieldChanged(
        entityTable: _tableName,
        entityId: assetId,
        stamp: stamp,
        before: <String, Object?>{
          'last_price': priorRow.lastPrice?.toString(),
          'last_price_at': priorRow.lastPriceAt?.toUtc().toIso8601String(),
        },
        after: <String, Object?>{
          'last_price': newValuation.toString(),
          'last_price_at': tradeDate.toUtc().toIso8601String(),
        },
        reason: reason,
      );
    });
    return (await findById(assetId))!;
  }

  /// Replaces the typed metadata blob (e.g. updating a deposit's interest
  /// rate or maturity date). Callers normally compute the new wrapper from
  /// the old via `copyWith` before passing it here.
  Future<Asset> updateMetadata({
    required String id,
    required ManualAssetMetadata metadata,
    String? reason,
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
      final priorRow = await (_db.select(
        _db.assets,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      await (_db.update(
        _db.assets,
      )..where((t) => t.id.equals(id))).write(companion);
      await _enqueue(
        opType: OpType.update,
        rowId: id,
        fields: diff,
        stamp: stamp,
      );
      if (priorRow != null) {
        await _eventLog.recordFieldChanged(
          entityTable: _tableName,
          entityId: id,
          stamp: stamp,
          before: <String, Object?>{'metadata_json': priorRow.metadataJson},
          after: <String, Object?>{'metadata_json': encoded},
          reason: reason,
        );
      }
    });
    return (await findById(id))!;
  }

  Future<Asset> updateBasics({
    required String id,
    String? name,
    String? note,
    String? reason,
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
      final priorRow = await (_db.select(
        _db.assets,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      await (_db.update(
        _db.assets,
      )..where((t) => t.id.equals(id))).write(companion);
      await _enqueue(
        opType: OpType.update,
        rowId: id,
        fields: diff,
        stamp: stamp,
      );
      if (priorRow != null) {
        final before = <String, Object?>{};
        final after = <String, Object?>{};
        if (name != null) {
          before['name'] = priorRow.name;
          after['name'] = name;
        }
        if (after.isNotEmpty) {
          await _eventLog.recordFieldChanged(
            entityTable: _tableName,
            entityId: id,
            stamp: stamp,
            before: before,
            after: after,
            reason: reason,
          );
        }
      }
    });
    return (await findById(id))!;
  }

  Future<void> softDelete(String id, {String? reason}) async {
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
      await _eventLog.recordSoftDeleted(
        entityTable: _tableName,
        entityId: id,
        stamp: stamp,
        reason: reason,
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
    required String accountId,
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
      // Audit ledger gets the user-visible field set; sync columns are
      // already captured by the stamp on the event row itself.
      await _eventLog.recordCreated(
        entityTable: _tableName,
        entityId: id,
        stamp: stamp,
        after: <String, Object?>{
          'type': type.name,
          'symbol': symbol,
          'currency': currency,
          'name': name,
          'last_price': lastPrice?.toString(),
          'last_price_at': lastPriceAt?.toUtc().toIso8601String(),
          'metadata_json': metadataJson,
        },
      );
      // FIR-123: seed the genesis valuationAdjust transaction so the
      // event-sourced view of this asset has at least one row to fold
      // from. Future updates flow through `recordValuationAdjust`, which
      // appends additional rows; the transaction stream — never the
      // assets table — is the authoritative valuation timeline.
      if (lastPrice != null) {
        final txId = _uuid.v4();
        final tradeDate = lastPriceAt ?? stamp.now;
        await _db
            .into(_db.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: txId,
                accountId: accountId,
                assetId: Value(id),
                type: TransactionType.valuationAdjust,
                quantity: Decimal.zero,
                price: lastPrice,
                currency: currency,
                tradeDate: tradeDate,
                ownerUserId: stamp.ownerUserId,
                updatedAt: stamp.now,
                updatedByDevice: stamp.deviceId,
                hlc: stamp.hlc,
              ),
            );
        await _enqueueTransaction(
          rowId: txId,
          fields: <String, Object?>{
            'id': txId,
            'account_id': accountId,
            'asset_id': id,
            'type': TransactionType.valuationAdjust.name,
            'quantity': '0',
            'price': lastPrice.toString(),
            'currency': currency,
            'trade_date': tradeDate.toUtc().toIso8601String(),
            'owner_user_id': stamp.ownerUserId,
            'updated_at': stamp.now.toUtc().toIso8601String(),
            'updated_by_device': stamp.deviceId,
            'hlc': stamp.hlc.toString(),
          },
          stamp: stamp,
        );
      }
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

  Future<void> _enqueueTransaction({
    required String rowId,
    required Map<String, Object?> fields,
    required MutationStamp stamp,
  }) async {
    final op = Op(
      opId: _uuid.v4(),
      tableName: _transactionsTableName,
      rowId: rowId,
      opType: OpType.insert,
      fieldsDiff: fields,
      hlc: stamp.hlc,
      deviceId: stamp.deviceId,
    );
    await _outbox.enqueue(op);
  }

  /// Resolve the cash-flow account that a `valuationAdjust` event should
  /// be booked against. For manually-tracked assets the account id lives
  /// inside the typed metadata blob — falling back to the asset id keeps
  /// the transaction insertable on rows whose metadata could not be
  /// decoded (e.g. legacy seed rows in tests).
  String _accountIdForAsset(AssetRow row) {
    final meta = ManualAssetMetadata.decode(row.metadataJson);
    return meta?.accountId ?? row.id;
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
