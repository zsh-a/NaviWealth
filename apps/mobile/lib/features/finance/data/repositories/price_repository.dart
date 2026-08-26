import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/models/price_observation.dart';
import 'package:uuid/uuid.dart';

import 'price_mutation_receipt.dart';

/// DAO for the append-only `prices` time-series. Every price update
/// is a new row; current price = MAX(observed_on) over the matching
/// `(unit, quoteCurrency)`.
///
/// `unit` shares the [Posting.unit] namespace: usually an `assets.id`
/// (`'us_stock:AAPL'`), occasionally a fiat code when the user is
/// recording an FX spot independent of the global rate feed.
class PriceRepository {
  PriceRepository({
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

  static const String _tableName = 'prices';

  bool isBoundTo(AppDatabase database) =>
      identical(_db, database) && isOutboxBoundToDatabase(_outbox, database);

  // ---------- Reads ----------

  /// Live stream of every observation for a single `(unit, currency)`
  /// pair, ordered ascending by `observed_on` so a chart can index
  /// directly without re-sorting.
  Stream<List<PriceObservation>> watchSeries({
    required String unit,
    required String quoteCurrency,
  }) {
    final query = _db.select(_db.prices)
      ..where((t) => t.unit.equals(unit))
      ..where((t) => t.quoteCurrency.equals(quoteCurrency))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.observedOn)]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  /// Latest known price for `(unit, currency)` at or before [asOf].
  ///
  /// The newest observation day wins first; within that day explicit manual
  /// values win over trade/import values, which win over automatic snapshots.
  /// This matters because the append-only ledger can legitimately contain
  /// more than one observation for a day and a plain timestamp sort made the
  /// result depend on write timing.
  Future<PriceObservation?> latestAt({
    required String unit,
    required String quoteCurrency,
    required DateTime asOf,
  }) async {
    final query = _db.select(_db.prices)
      ..where((t) => t.unit.equals(unit))
      ..where((t) => t.quoteCurrency.equals(quoteCurrency))
      ..where((t) => t.observedOn.isSmallerOrEqualValue(asOf.toUtc()))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.observedOn, mode: OrderingMode.desc),
      ])
      ..limit(1);
    final anchor = await query.getSingleOrNull();
    if (anchor == null) return null;

    final latestDay = _floorToUtcDay(anchor.observedOn);
    final dayEnd = latestDay.add(const Duration(days: 1));
    final sameDay = _db.select(_db.prices)
      ..where((t) => t.unit.equals(unit))
      ..where((t) => t.quoteCurrency.equals(quoteCurrency))
      ..where((t) => t.observedOn.isBiggerOrEqualValue(latestDay))
      ..where((t) => t.observedOn.isSmallerThanValue(dayEnd))
      ..where((t) => t.observedOn.isSmallerOrEqualValue(asOf.toUtc()))
      ..where((t) => t.deletedAt.isNull());
    final candidates = (await sameDay.get()).map(_toDomain).toList();
    candidates.sort(_compareLatest);
    return candidates.first;
  }

  /// Reads one observation by its stable row id, including tombstones.
  Future<PriceObservation?> findById(String id) async {
    final row = await (_db.select(
      _db.prices,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  // ---------- Writes ----------

  /// Inserts a new observation. Idempotency / dedup is the caller's
  /// responsibility — the table is genuinely append-only so the same
  /// price observed twice on the same day produces two rows. (Most
  /// pickers throttle the writer; the manual entry form de-dupes by
  /// `(unit, currency, day)` before invoking the repo.)
  Future<PriceObservation> record({
    required String unit,
    required String quoteCurrency,
    required DateTime observedOn,
    required Decimal perUnit,
    required String source,
    bool allowZero = false,
  }) async {
    if (allowZero ? perUnit < Decimal.zero : perUnit <= Decimal.zero) {
      throw ArgumentError.value(perUnit, 'perUnit', 'must be positive');
    }
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    final domain = PriceObservation(
      id: id,
      unit: unit,
      quoteCurrency: quoteCurrency,
      observedOn: observedOn,
      perUnit: perUnit,
      source: source,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    final companion = PricesCompanion.insert(
      id: id,
      unit: unit,
      quoteCurrency: quoteCurrency,
      observedOn: observedOn,
      perUnit: perUnit,
      source: source,
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
    await _db.transaction(() async {
      await _db.into(_db.prices).insert(companion);
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
    return domain;
  }

  /// Upserts the deterministic automatic daily snapshot for an asset.
  ///
  /// The stable id closes the read-then-insert race between devices: two
  /// coordinators writing the same asset/day converge on one sync row instead
  /// of creating duplicate automatic observations. Manual and trade rows
  /// continue to use their own ids and remain independently auditable.
  Future<PriceObservation> upsertDailySnapshot({
    required String unit,
    required String quoteCurrency,
    required DateTime observedOn,
    required Decimal perUnit,
    required String source,
  }) async {
    if (perUnit <= Decimal.zero) {
      throw ArgumentError.value(perUnit, 'perUnit', 'must be positive');
    }
    final observedOnUtc = observedOn.toUtc();
    final normalizedObservedOn = _floorToUtcDay(observedOnUtc);
    final stamp = await _stamper.stamp();
    final id = dailySnapshotId(
      unit: unit,
      quoteCurrency: quoteCurrency,
      observedOn: normalizedObservedOn,
    );
    final domain = PriceObservation(
      id: id,
      unit: unit,
      quoteCurrency: quoteCurrency,
      observedOn: observedOnUtc,
      perUnit: perUnit,
      source: source,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.prices)
          .insertOnConflictUpdate(
            PricesCompanion.insert(
              id: id,
              unit: unit,
              quoteCurrency: quoteCurrency,
              observedOn: observedOnUtc,
              perUnit: perUnit,
              source: source,
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
              deletedAt: const Value(null),
            ),
          );
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
    return domain;
  }

  /// Stable identity for one automatic price observation per UTC day.
  static String dailySnapshotId({
    required String unit,
    required String quoteCurrency,
    required DateTime observedOn,
  }) {
    final day = _floorToUtcDay(observedOn).toIso8601String().substring(0, 10);
    return 'auto-snapshot:${unit.trim()}:${quoteCurrency.trim().toUpperCase()}:$day';
  }

  /// Inserts or replaces a stable observation and returns its Undo receipt.
  ///
  /// Trade submission uses the planned transaction id as [id], making the
  /// journal entry and its price observation one versioned logical mutation.
  Future<PriceMutationReceipt> upsertWithReceipt({
    required String id,
    required String unit,
    required String quoteCurrency,
    required DateTime observedOn,
    required Decimal perUnit,
    required String source,
    bool allowZero = false,
  }) async {
    if (allowZero ? perUnit < Decimal.zero : perUnit <= Decimal.zero) {
      throw ArgumentError.value(perUnit, 'perUnit', 'must be positive');
    }
    final stamp = await _stamper.stamp();
    PriceObservation? before;
    late final PriceObservation after;
    await _db.transaction(() async {
      before = await findById(id);
      final companion = PricesCompanion.insert(
        id: id,
        unit: unit,
        quoteCurrency: quoteCurrency,
        observedOn: observedOn,
        perUnit: perUnit,
        source: source,
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
        deletedAt: const Value(null),
      );
      await _db.into(_db.prices).insertOnConflictUpdate(companion);
      await _outbox.enqueue(table: _tableName, rowId: id);
      after = (await findById(id))!;
    });
    return PriceMutationReceipt(before: before, after: after);
  }

  /// Verifies that [receipt.after] is still the complete persisted version.
  Future<void> validateUndo(PriceMutationReceipt receipt) async {
    final current = await findById(receipt.after.id);
    if (current != receipt.after) {
      throw PriceMutationConflict(
        'Price observation ${receipt.after.id} changed after commit.',
      );
    }
  }

  /// Reverses [receipt] only while its exact committed version is current.
  Future<void> undoMutation(PriceMutationReceipt receipt) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await validateUndo(receipt);
      final before = receipt.before;
      if (before == null) {
        await (_db.update(
          _db.prices,
        )..where((t) => t.id.equals(receipt.after.id))).write(
          PricesCompanion(
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
            deletedAt: Value(stamp.now),
          ),
        );
      } else {
        await (_db.update(
          _db.prices,
        )..where((t) => t.id.equals(receipt.after.id))).write(
          PricesCompanion(
            unit: Value(before.unit),
            quoteCurrency: Value(before.quoteCurrency),
            observedOn: Value(before.observedOn),
            perUnit: Value(before.perUnit),
            source: Value(before.source),
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
            deletedAt: Value(before.sync.deletedAt == null ? null : stamp.now),
          ),
        );
      }
      await _outbox.enqueue(table: _tableName, rowId: receipt.after.id);
    });
  }

  /// Soft-delete an observation. Useful when a manually entered price
  /// turned out to be a typo; reports honour the tombstone and the
  /// previous observation becomes the latest again.
  Future<void> softDelete(String id) async {
    final stamp = await _stamper.stamp();
    final companion = PricesCompanion(
      updatedAt: Value(stamp.now),
      updatedByDevice: Value(stamp.deviceId),
      hlc: Value(stamp.hlc),
      deletedAt: Value(stamp.now),
    );
    await _db.transaction(() async {
      await (_db.update(
        _db.prices,
      )..where((t) => t.id.equals(id))).write(companion);
      await _outbox.enqueue(table: _tableName, rowId: id);
    });
  }

  // ---------- Helpers ----------

  PriceObservation _toDomain(PriceRow row) => PriceObservation(
    id: row.id,
    unit: row.unit,
    quoteCurrency: row.quoteCurrency,
    observedOn: row.observedOn.toUtc(),
    perUnit: row.perUnit,
    source: row.source,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt.toUtc(),
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
      deletedAt: row.deletedAt?.toUtc(),
    ),
  );

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

  static int _compareLatest(PriceObservation a, PriceObservation b) {
    final byObserved = _floorToUtcDay(b.observedOn)
        .compareTo(_floorToUtcDay(a.observedOn));
    if (byObserved != 0) return byObserved;
    final bySource = _sourcePriority(b.source)
        .compareTo(_sourcePriority(a.source));
    if (bySource != 0) return bySource;
    final byUpdated = b.sync.updatedAt.compareTo(a.sync.updatedAt);
    if (byUpdated != 0) return byUpdated;
    return b.sync.hlc.compareTo(a.sync.hlc);
  }

  static DateTime _floorToUtcDay(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }
}
