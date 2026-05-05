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
import 'account_repository.dart';
import 'journal_entry_builders.dart';
import 'journal_entry_repository.dart';
import 'mutation_context.dart';
import 'price_repository.dart';

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

  Future<Decimal?> latestValuation(String assetId, {DateTime? asOf}) async {
    final row = await (_db.select(
      _db.assets,
    )..where((t) => t.id.equals(assetId))).getSingleOrNull();
    if (row == null) return null;
    final observed = await _priceRepo.latestAt(
      unit: assetId,
      quoteCurrency: row.currency,
      asOf: asOf ?? DateTime.now().toUtc(),
    );
    return observed?.perUnit;
  }

  /// Current balance for a cash asset, derived from the postings ledger.
  ///
  /// Returns the algebraic sum of all non-deleted posting units on the
  /// account linked to [assetId].  Returns `null` when the asset has no
  /// postings or the metadata cannot be decoded.
  Future<Decimal?> cashBalanceFromPostings(String assetId) async {
    final assetRow = await (_db.select(
      _db.assets,
    )..where((t) => t.id.equals(assetId))).getSingleOrNull();
    if (assetRow == null) return null;
    final meta = ManualAssetMetadata.decode(assetRow.metadataJson);
    if (meta == null) return null;
    final rows = await (_db.select(_db.postings).join([
      innerJoin(
        _db.journalEntries,
        _db.journalEntries.id.equalsExp(_db.postings.journalEntryId),
      ),
    ])
          ..where(_db.postings.accountId.equals(meta.accountId))
          ..where(_db.postings.deletedAt.isNull())
          ..where(_db.journalEntries.deletedAt.isNull()))
        .get();
    if (rows.isEmpty) return null;
    var sum = Decimal.zero;
    for (final row in rows) {
      sum += row.readTable(_db.postings).units;
    }
    return sum;
  }

  /// Find an existing non-deleted cash asset linked to [accountId].
  ///
  /// Returns `null` when no cash asset points to this account. Used by
  /// the create flow to enforce the double-entry invariant that each
  /// ledger account has at most one cash asset.
  Future<Asset?> findCashByAccountId(String accountId) async {
    final rows = await (_db.select(_db.assets)
          ..where((t) => t.type.equalsValue(AssetType.cash))
          ..where((t) => t.deletedAt.isNull()))
        .get();
    for (final row in rows) {
      final meta = ManualAssetMetadata.decode(row.metadataJson);
      if (meta is CashMetadata && meta.accountId == accountId) {
        return _toAsset(row);
      }
    }
    return null;
  }

  Future<Asset> createCash({
    required String accountId,
    required String currency,
    required Decimal balance,
    String? nickname,
  }) async {
    if (balance < Decimal.zero) {
      throw ArgumentError.value(balance, 'balance', 'must be >= 0');
    }
    final metadata = CashMetadata(accountId: accountId);
    return _create(
      type: AssetType.cash,
      symbol: currency,
      currency: currency,
      name: nickname ?? '$currency cash',
      metadata: metadata,
      accountId: accountId,
      initialValuation: balance,
    );
  }

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
    final metadata = DepositMetadata(
      accountId: accountId,
      principal: principal,
      interestRate: interestRate,
      startDate: startDate,
      maturityDate: maturityDate,
      autoRenew: autoRenew,
    );
    return _create(
      type: type,
      symbol: name,
      currency: currency,
      name: name,
      metadata: metadata,
      accountId: accountId,
      initialValuation: currentValuation ?? principal,
    );
  }

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
    final metadata = WealthProductMetadata(
      accountId: accountId,
      principal: principal,
      expectedAnnualReturn: expectedAnnualReturn,
      startDate: startDate,
      maturityDate: maturityDate,
      issuer: issuer,
      productCode: productCode,
    );
    return _create(
      type: AssetType.wealthProduct,
      symbol: productCode ?? name,
      currency: currency,
      name: name,
      metadata: metadata,
      accountId: accountId,
      initialValuation: currentValuation ?? principal,
    );
  }

  Future<Asset> recordValuationAdjust({
    required String assetId,
    required Decimal newValuation,
    DateTime? asOf,
    String? reason,
  }) async {
    final row = await (_db.select(
      _db.assets,
    )..where((t) => t.id.equals(assetId))).getSingleOrNull();
    if (row == null) {
      throw StateError('Asset $assetId does not exist');
    }
    final observedOn = asOf ?? DateTime.now().toUtc();
    final previous = await _priceRepo.latestAt(
      unit: assetId,
      quoteCurrency: row.currency,
      asOf: observedOn,
    );
    await _recordValuation(
      assetId: assetId,
      accountId: _accountIdForAsset(row),
      currency: row.currency,
      value: newValuation,
      observedOn: observedOn,
      narration: reason,
      ownerUserId: row.ownerUserId,
      type: row.type,
      previousValue: previous?.perUnit,
    );
    await _eventLog.recordFieldChanged(
      entityTable: _tableName,
      entityId: assetId,
      stamp: await _stamper.stamp(),
      before: <String, Object?>{
        'valuation': previous?.perUnit.toString(),
        'observed_on': previous?.observedOn.toUtc().toIso8601String(),
      },
      after: <String, Object?>{
        'valuation': newValuation.toString(),
        'observed_on': observedOn.toUtc().toIso8601String(),
      },
      reason: reason,
    );
    return (await findById(assetId))!;
  }

  Future<Asset> updateMetadata({
    required String id,
    required ManualAssetMetadata metadata,
    String? reason,
  }) async {
    final stamp = await _stamper.stamp();
    final encoded = metadata.encode();
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
      await (_db.update(_db.assets)..where((t) => t.id.equals(id))).write(
        AssetsCompanion(
          metadataJson: Value(encoded),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _enqueue(OpType.update, id, diff, stamp);
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
      await _enqueue(OpType.update, id, diff, stamp);
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
      await _enqueue(OpType.delete, id, null, stamp);
      await _eventLog.recordSoftDeleted(
        entityTable: _tableName,
        entityId: id,
        stamp: stamp,
        reason: reason,
      );
    });
  }

  Future<Asset> _create({
    required AssetType type,
    required String symbol,
    required String currency,
    required String name,
    required ManualAssetMetadata metadata,
    required String accountId,
    required Decimal initialValuation,
  }) async {
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    final encoded = metadata.encode();
    final companion = AssetsCompanion.insert(
      id: id,
      type: type,
      symbol: symbol,
      currency: currency,
      name: Value(name),
      metadataJson: Value(encoded),
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
      'metadata_json': encoded,
      'owner_user_id': stamp.ownerUserId,
      'updated_at': stamp.now.toUtc().toIso8601String(),
      'updated_by_device': stamp.deviceId,
      'hlc': stamp.hlc.toString(),
    };
    await _db.transaction(() async {
      await _db.into(_db.assets).insert(companion);
      await _enqueue(OpType.insert, id, fields, stamp);
      await _eventLog.recordCreated(
        entityTable: _tableName,
        entityId: id,
        stamp: stamp,
        after: fields,
      );
    });
    if (initialValuation > Decimal.zero ||
        (type == AssetType.cash && initialValuation == Decimal.zero)) {
      await _recordValuation(
        assetId: id,
        accountId: accountId,
        currency: currency,
        value: initialValuation,
        observedOn: stamp.now,
        ownerUserId: stamp.ownerUserId,
        type: type,
        previousValue: Decimal.zero,
      );
    }
    return (await findById(id))!;
  }

  Future<void> _recordValuation({
    required String assetId,
    required String accountId,
    required String currency,
    required Decimal value,
    required DateTime observedOn,
    required String ownerUserId,
    required AssetType type,
    Decimal? previousValue,
    String? narration,
  }) async {
    await _priceRepo.record(
      unit: assetId,
      quoteCurrency: currency,
      observedOn: observedOn,
      perUnit: value,
      source: 'manual',
      allowZero: type == AssetType.cash,
    );
    final jeRepo = _journalEntryRepo;
    if (jeRepo == null) return;
    final JournalEntryBuild build;
    if (type == AssetType.cash) {
      final delta = value - (previousValue ?? Decimal.zero);
      if (delta == Decimal.zero) return;
      build = JournalEntryBuilders.openingBalance(
        date: observedOn,
        accountId: accountId,
        openingBalanceAccountId: AccountRepository.systemAccountIdForPath(
          'equity:openingBalance',
          ownerUserId: ownerUserId,
        ),
        amount: delta,
        currency: currency,
        narration: narration ?? 'Cash balance',
        tagIds: ['asset:$assetId'],
      );
    } else {
      final equityAccountId = AccountRepository.systemAccountIdForPath(
        'equity:adjustments',
        ownerUserId: ownerUserId,
      );
      build = JournalEntryBuilders.valuationAdjust(
        date: observedOn,
        accountId: accountId,
        equityAccountId: equityAccountId,
        assetUnit: assetId,
        quantity: Decimal.zero,
        newValuation: value,
        currency: currency,
        narration: narration,
      );
    }
    await jeRepo.create(entry: build.entry, postings: build.postings);
  }

  Future<void> _enqueue(
    OpType opType,
    String rowId,
    Map<String, Object?>? fields,
    MutationStamp stamp,
  ) {
    return _outbox.enqueue(
      Op(
        opId: _uuid.v4(),
        tableName: _tableName,
        rowId: rowId,
        opType: opType,
        fieldsDiff: fields,
        hlc: stamp.hlc,
        deviceId: stamp.deviceId,
      ),
    );
  }

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
