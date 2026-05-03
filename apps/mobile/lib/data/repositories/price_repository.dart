import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../core/sync/op.dart';
import '../../core/sync/op_outbox.dart';
import '../db/app_database.dart';
import '../domain/price_observation.dart';
import '../domain/sync_meta.dart';
import 'mutation_context.dart';

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
  /// Returns `null` when nothing is on file yet — callers either
  /// degrade to the asset's manually-entered value or surface a
  /// "price unknown" hint. The lookup uses the
  /// `(unit, quote_currency, observed_on)` index so it's a tight
  /// rangescan even on hot reload.
  Future<PriceObservation?> latestAt({
    required String unit,
    required String quoteCurrency,
    required DateTime asOf,
  }) async {
    final query = _db.select(_db.prices)
      ..where((t) => t.unit.equals(unit))
      ..where((t) => t.quoteCurrency.equals(quoteCurrency))
      ..where((t) => t.observedOn.isSmallerOrEqualValue(asOf))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.observedOn, mode: OrderingMode.desc),
      ])
      ..limit(1);
    final row = await query.getSingleOrNull();
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
    final fields = _insertFields(domain);
    await _db.transaction(() async {
      await _db.into(_db.prices).insert(companion);
      final op = Op(
        opId: _uuid.v4(),
        tableName: _tableName,
        rowId: id,
        opType: OpType.insert,
        fieldsDiff: fields,
        hlc: stamp.hlc,
        deviceId: stamp.deviceId,
      );
      await _outbox.enqueue(op);
    });
    return domain;
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
      final op = Op(
        opId: _uuid.v4(),
        tableName: _tableName,
        rowId: id,
        opType: OpType.delete,
        fieldsDiff: null,
        hlc: stamp.hlc,
        deviceId: stamp.deviceId,
      );
      await _outbox.enqueue(op);
    });
  }

  // ---------- Helpers ----------

  Map<String, Object?> _insertFields(PriceObservation p) => {
    'id': p.id,
    'unit': p.unit,
    'quote_currency': p.quoteCurrency,
    'observed_on': p.observedOn.toUtc().toIso8601String(),
    'per_unit': p.perUnit.toString(),
    'source': p.source,
    'owner_user_id': p.sync.ownerUserId,
    'updated_at': p.sync.updatedAt.toUtc().toIso8601String(),
    'updated_by_device': p.sync.updatedByDevice,
    'hlc': p.sync.hlc.toString(),
  };

  PriceObservation _toDomain(PriceRow row) => PriceObservation(
    id: row.id,
    unit: row.unit,
    quoteCurrency: row.quoteCurrency,
    observedOn: row.observedOn,
    perUnit: row.perUnit,
    source: row.source,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
      deletedAt: row.deletedAt,
    ),
  );
}
