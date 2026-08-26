import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/price_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:uuid/uuid.dart';

import 'physical_asset.dart';
import 'physical_asset_meta.dart';

/// CRUD + valuation history for non-financial assets (real estate, vehicles).
///
/// Acts as the single mutation entry point so callers can't accidentally
/// forget the sync dirty-mark or the synthetic `valuationAdjust`
/// transaction that the analytics layer relies on. Mirrors the contract
/// of [ManualAssetRepository] / [LiabilityRepository]: each write happens
/// inside a Drift transaction that *both* mutates the row and marks it
/// dirty in the sync outbox.
class PhysicalAssetRepository {
  PhysicalAssetRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    required PriceRepository priceRepo,
    JournalEntryRepository? journalEntryRepo,
    Uuid uuid = const Uuid(),
  }) : _db = db,
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

  static const String _tableName = 'assets';

  static const Set<AssetType> _physicalTypes = {
    AssetType.realEstate,
    AssetType.vehicle,
  };

  // ---------- Reads ----------

  Future<List<PhysicalAsset>> listAll() async {
    return _physicalQuery().get().then(_physicalAssetsFromRows);
  }

  Stream<List<PhysicalAsset>> watchAll() {
    // Join `prices` so a valuation update invalidates the same stream as an
    // asset edit. The in-memory reducer groups the one-to-many rows back into
    // a single asset and carries the complete historical series.
    return _physicalQuery().watch().map(_physicalAssetsFromRows);
  }

  Future<PhysicalAsset?> getById(String id) async {
    final rows = await (_physicalQuery()..where(_db.assets.id.equals(id)))
        .get();
    return _physicalAssetsFromRows(rows).firstOrNull;
  }

  /// Returns the valuation history for [assetId] in chronological order.
  ///
  /// Includes a synthesised "purchase" point as the first entry so the UI
  /// chart never starts mid-air. Subsequent points are rows in `prices`.
  Future<List<ValuationPoint>> getValuationHistory(String assetId) async {
    final asset = await getById(assetId);
    return asset?.valuationHistory ?? const [];
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

    final normalizedAsOf = _calendarDay(asOf);
    if (normalizedAsOf.isBefore(existing.purchaseDate)) {
      throw ArgumentError.value(
        asOf,
        'asOf',
        'must not be before the asset purchase date',
      );
    }

    await _priceRepo.record(
      unit: assetId,
      quoteCurrency: existing.currency,
      observedOn: normalizedAsOf,
      perUnit: newValuation,
      source: _manualSource(note),
    );
    await _recordValuationJournal(
      assetId: assetId,
      currency: existing.currency,
      valuation: newValuation,
      asOf: normalizedAsOf,
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
      await _outbox.enqueue(table: _tableName, rowId: assetId);
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
      await _outbox.enqueue(table: _tableName, rowId: assetId);
    });
  }

  // ---------- Internals ----------

  PhysicalAsset? _wrap(
    AssetRow row, {
    Iterable<PriceRow> valuationRows = const [],
  }) {
    if (!_physicalTypes.contains(row.type)) return null;
    final meta = PhysicalAssetMeta.tryDecode(row.metadataJson);
    if (meta == null) return null;
    final prices = valuationRows.toList(growable: false)
      ..sort(_comparePriceRows);
    return PhysicalAsset(
      row: row,
      meta: meta,
      valuationHistory: [
        ValuationPoint(
          asOf: meta.purchaseDate,
          value: meta.purchasePrice,
          kind: ValuationPointKind.purchase,
        ),
        for (final price in prices)
          ValuationPoint(
            asOf: _floorToUtcDay(price.observedOn),
            value: price.perUnit,
            kind: ValuationPointKind.manual,
            note: _noteFromSource(price.source),
          ),
      ],
    );
  }

  JoinedSelectStatement<HasResultSet, dynamic> _physicalQuery() {
    return (_db.select(_db.assets).join([
        leftOuterJoin(
          _db.prices,
          _db.prices.unit.equalsExp(_db.assets.id) &
              _db.prices.quoteCurrency.equalsExp(_db.assets.currency) &
              _db.prices.deletedAt.isNull(),
        ),
      ])
      ..where(
        _db.assets.deletedAt.isNull() &
            _db.assets.type.isInValues(_physicalTypes.toList()),
      )
      ..orderBy([
        OrderingTerm(expression: _db.assets.updatedAt, mode: OrderingMode.desc),
      ]));
  }

  List<PhysicalAsset> _physicalAssetsFromRows(List<TypedResult> rows) {
    final grouped = <String, ({AssetRow asset, List<PriceRow> prices})>{};
    for (final joined in rows) {
      final asset = joined.readTable(_db.assets);
      final entry = grouped.putIfAbsent(
        asset.id,
        () => (asset: asset, prices: <PriceRow>[]),
      );
      final price = joined.readTableOrNull(_db.prices);
      if (price != null) entry.prices.add(price);
    }
    return [
      for (final entry in grouped.values)
        ?_wrap(entry.asset, valuationRows: entry.prices),
    ];
  }

  static int _comparePriceRows(PriceRow a, PriceRow b) {
    final byObserved = _floorToUtcDay(a.observedOn)
        .compareTo(_floorToUtcDay(b.observedOn));
    if (byObserved != 0) return byObserved;
    final bySource = _sourcePriority(a.source)
        .compareTo(_sourcePriority(b.source));
    if (bySource != 0) return bySource;
    final byUpdated = a.updatedAt.compareTo(b.updatedAt);
    if (byUpdated != 0) return byUpdated;
    final byHlc = a.hlc.compareTo(b.hlc);
    if (byHlc != 0) return byHlc;
    return a.id.compareTo(b.id);
  }

  static int _sourcePriority(String source) {
    final normalized = source.trim().toLowerCase();
    if (normalized == 'manual' || normalized.startsWith('manual:')) return 3;
    if (normalized == 'trade' ||
        normalized.startsWith('trade:') ||
        normalized == 'import' ||
        normalized.startsWith('import:')) {
      return 2;
    }
    if (normalized == 'auto' || normalized.startsWith('auto:')) return 1;
    return 0;
  }

  static String _manualSource(String? note) {
    final trimmed = note?.trim();
    return trimmed == null || trimmed.isEmpty ? 'manual' : 'manual:$trimmed';
  }

  static String? _noteFromSource(String source) {
    if (source == 'manual') return null;
    const prefix = 'manual:';
    if (source.startsWith(prefix)) return source.substring(prefix.length);
    return source;
  }

  static DateTime _floorToUtcDay(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  static DateTime _calendarDay(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

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
      await _db
          .into(_db.assets)
          .insert(
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
      await _outbox.enqueue(table: _tableName, rowId: id);
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
    // Re-read after the initial price observation so callers immediately get
    // the same current valuation/history as subsequent stream consumers.
    return await getById(id) ?? created;
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
}
