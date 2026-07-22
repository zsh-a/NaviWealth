import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:uuid/uuid.dart';

import '../domain/dca/dca_plan.dart';
import '../domain/dca/dca_simulator.dart';

class DcaPlanRepository {
  DcaPlanRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _uuid = uuid;

  static const tableName = 'dca_plans';

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final Uuid _uuid;

  Stream<List<DcaPlan>> watchAll() async* {
    final owner = await _stamper.currentUserId();
    final query = _db.select(_db.dcaPlans)
      ..where((t) => t.ownerUserId.equals(owner) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.nextDueAt)]);
    yield* query.watch().map(
      (rows) => rows.map(_fromRow).toList(growable: false),
    );
  }

  Future<DcaPlan> create({
    required List<DcaAllocation> allocations,
    required Decimal amountPerContribution,
    required String currency,
    required AssetMarket market,
    required DcaFrequency frequency,
    required DateTime nextDueAt,
    DateTime? endAt,
  }) async {
    _validate(allocations, amountPerContribution);
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();
    final row = DcaPlansCompanion.insert(
      id: id,
      allocationsJson: _encodeAllocations(allocations),
      amountPerContribution: amountPerContribution,
      currency: currency.toUpperCase(),
      market: market.wire,
      frequency: frequency.name,
      nextDueAt: nextDueAt.toUtc(),
      endAt: Value(endAt?.toUtc()),
      createdAt: stamp.now,
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
    await _db.transaction(() async {
      await _db.into(_db.dcaPlans).insert(row);
      await _outbox.enqueue(table: tableName, rowId: id);
    });
    return (await _find(id))!;
  }

  Future<void> setEnabled(DcaPlan plan, bool enabled) async {
    await _update(plan.id, DcaPlansCompanion(enabled: Value(enabled)));
  }

  Future<void> markExecuted(DcaPlan plan, DateTime executedAt) async {
    await _update(
      plan.id,
      DcaPlansCompanion(
        lastExecutedAt: Value(executedAt.toUtc()),
        nextDueAt: Value(nextDcaDueDate(executedAt, plan.frequency)),
      ),
    );
  }

  Future<void> remove(DcaPlan plan) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.dcaPlans,
      )..where((t) => t.id.equals(plan.id))).write(
        DcaPlansCompanion(
          deletedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: tableName, rowId: plan.id);
    });
  }

  Future<void> _update(String id, DcaPlansCompanion changes) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(_db.dcaPlans)..where((t) => t.id.equals(id))).write(
        changes.copyWith(
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: tableName, rowId: id);
    });
  }

  Future<DcaPlan?> _find(String id) async {
    final owner = await _stamper.currentUserId();
    final row =
        await (_db.select(_db.dcaPlans)..where(
              (t) =>
                  t.id.equals(id) &
                  t.ownerUserId.equals(owner) &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  DcaPlan _fromRow(DcaPlanRow row) => DcaPlan(
    id: row.id,
    allocations: _decodeAllocations(row.allocationsJson),
    amountPerContribution: row.amountPerContribution,
    currency: row.currency,
    market: assetMarketFromWire(row.market) ?? AssetMarket.usStock,
    frequency: DcaFrequency.values.byName(row.frequency),
    nextDueAt: row.nextDueAt,
    endAt: row.endAt,
    lastExecutedAt: row.lastExecutedAt,
    enabled: row.enabled,
    createdAt: row.createdAt,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );

  static String _encodeAllocations(List<DcaAllocation> allocations) =>
      jsonEncode([
        for (final allocation in allocations)
          <String, String>{
            'symbol': allocation.symbol,
            'weight': allocation.weight.toString(),
          },
      ]);

  static List<DcaAllocation> _decodeAllocations(String raw) {
    return (jsonDecode(raw) as List<Object?>)
        .map((item) {
          final map = Map<String, Object?>.from(item! as Map);
          return DcaAllocation(
            symbol: map['symbol']! as String,
            weight: Decimal.parse(map['weight']! as String),
          );
        })
        .toList(growable: false);
  }

  static void _validate(
    List<DcaAllocation> allocations,
    Decimal amountPerContribution,
  ) {
    if (allocations.isEmpty || amountPerContribution <= Decimal.zero) {
      throw ArgumentError(
        'DCA plan requires allocations and a positive amount',
      );
    }
    if (allocations.any((allocation) => allocation.weight <= Decimal.zero)) {
      throw ArgumentError('DCA allocation weights must be positive');
    }
    final total = allocations.fold(
      Decimal.zero,
      (sum, allocation) => sum + allocation.weight,
    );
    if ((total - Decimal.one).abs() > Decimal.parse('0.000001')) {
      throw ArgumentError('DCA allocation weights must total 1');
    }
  }
}
