import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/audit/event_log_writer.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/manual_asset_metadata.dart';
import 'package:uuid/uuid.dart';

import 'account_repository.dart';
import 'journal_entry_builders.dart';
import 'journal_entry_repository.dart';
import 'price_repository.dart';

part 'manual_asset_repository_cash.dart';
part 'manual_asset_repository_products.dart';
part 'manual_asset_repository_valuation.dart';

/// Repository for user-valued assets: cash, deposits and wealth products.
///
/// The current valuation is no longer mirrored on `assets`. Every valuation
/// update is an append-only `prices` observation plus a balanced journal entry.
class ManualAssetRepository {
  ManualAssetRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    required PriceRepository priceRepo,
    JournalEntryRepository? journalEntryRepo,
    EventLogWriter? eventLog,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _priceRepo = priceRepo,
       _journalEntryRepo = journalEntryRepo,
       _eventLog = eventLog ?? EventLogWriter(db: db, uuid: uuid),
       _uuid = uuid;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final PriceRepository _priceRepo;
  final JournalEntryRepository? _journalEntryRepo;
  final EventLogWriter _eventLog;
  final Uuid _uuid;

  static const String _tableName = 'assets';

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

  Future<Decimal?> latestValuation(String assetId, {DateTime? asOf}) =>
      _latestManualAssetValuation(this, assetId, asOf: asOf);

  /// Current balance for a cash asset, derived from the postings ledger.
  ///
  /// Returns the algebraic sum of all non-deleted posting units on the
  /// account linked to [assetId].  Returns `null` when the asset has no
  /// postings or the metadata cannot be decoded.
  Future<Decimal?> cashBalanceFromPostings(String assetId) =>
      _manualCashBalanceFromPostings(this, assetId);

  /// Find an existing non-deleted cash asset linked to [accountId].
  ///
  /// Returns `null` when no cash asset points to this account. Used by
  /// the create flow to enforce the double-entry invariant that each
  /// ledger account has at most one cash asset.
  Future<Asset?> findCashByAccountId(String accountId) =>
      _findManualCashByAccountId(this, accountId);

  Future<Asset> createCash({
    required String accountId,
    required String currency,
    required Decimal balance,
    String? nickname,
  }) => _createManualCash(
    this,
    accountId: accountId,
    currency: currency,
    balance: balance,
    nickname: nickname,
  );

  /// Repairs cash assets that have a latest valuation but whose linked
  /// account ledger does not reflect that balance.
  ///
  /// This is defensive for older builds that wrote the asset/price rows
  /// before the opening-balance journal. If the journal leg failed, the
  /// dashboard could include the cash asset while the account list still
  /// showed "-". The repair writes only the missing ledger delta.
  Future<int> repairCashBalancePostings() =>
      _repairManualCashBalancePostings(this);

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
  }) => _createManualDeposit(
    this,
    accountId: accountId,
    type: type,
    name: name,
    currency: currency,
    principal: principal,
    interestRate: interestRate,
    startDate: startDate,
    maturityDate: maturityDate,
    autoRenew: autoRenew,
    currentValuation: currentValuation,
  );

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
  }) => _createManualWealthProduct(
    this,
    accountId: accountId,
    name: name,
    currency: currency,
    principal: principal,
    expectedAnnualReturn: expectedAnnualReturn,
    startDate: startDate,
    maturityDate: maturityDate,
    issuer: issuer,
    productCode: productCode,
    currentValuation: currentValuation,
  );

  Future<Asset> recordValuationAdjust({
    required String assetId,
    required Decimal newValuation,
    DateTime? asOf,
    String? reason,
  }) => _recordManualValuationAdjust(
    this,
    assetId: assetId,
    newValuation: newValuation,
    asOf: asOf,
    reason: reason,
  );

  Future<Asset> updateMetadata({
    required String id,
    required ManualAssetMetadata metadata,
    String? reason,
  }) async {
    final stamp = await _stamper.stamp();
    final encoded = metadata.encode();
    await _db.transaction(() async {
      final priorRow = await (_db.select(
        _db.assets,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      await (_db.update(_db.assets)..where((t) => t.id.equals(id))).write(
        AssetsCompanion(
          metadataJson: Value(encoded),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: _tableName, rowId: id);
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
      await (_db.update(
        _db.assets,
      )..where((t) => t.id.equals(id))).write(companion);
      await _outbox.enqueue(table: _tableName, rowId: id);
      await _eventLog.recordFieldChanged(
        entityTable: _tableName,
        entityId: id,
        stamp: stamp,
        before: const <String, Object?>{},
        after: diff,
        reason: reason,
      );
    });
    return (await findById(id))!;
  }

  Future<void> softDelete(String id, {String? reason}) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(_db.assets)..where((t) => t.id.equals(id))).write(
        AssetsCompanion(
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
          deletedAt: Value(stamp.now),
        ),
      );
      await _outbox.enqueue(table: _tableName, rowId: id);
      await _eventLog.recordSoftDeleted(
        entityTable: _tableName,
        entityId: id,
        stamp: stamp,
        reason: reason,
      );
    });
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

extension AssetManualMetadata on Asset {
  ManualAssetMetadata? get manualMetadata =>
      ManualAssetMetadata.decode(metadataJson);
}
