import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../domain/income_strategy.dart';
import '../domain/income_strategy_plan.dart';

class IncomeStrategyPlanRepository {
  IncomeStrategyPlanRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper;

  static const tableName = 'income_strategy_plans';
  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;

  Stream<List<IncomeStrategyPlan>> watchActive(String ownerUserId) {
    final query = _db.select(_db.incomeStrategyPlans)
      ..where((table) => table.ownerUserId.equals(ownerUserId))
      ..where((table) => table.deletedAt.isNull())
      ..orderBy([(table) => OrderingTerm.asc(table.symbol)]);
    return query.watch().map(
      (rows) => rows.map(_rowToDomain).toList(growable: false),
    );
  }

  Future<IncomeStrategyPlan?> get(String assetId) async {
    final row =
        await (_db.select(_db.incomeStrategyPlans)
              ..where((table) => table.id.equals(assetId))
              ..where((table) => table.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _rowToDomain(row);
  }

  Future<IncomeStrategyPlan> upsert({
    required String assetId,
    required String symbol,
    required String market,
    required String currency,
    required Set<IncomeStrategySleeveKind> enabledSleeves,
    required bool preserveDividend,
    required bool allowSharesCalledAway,
    Decimal? capitalBudget,
    Decimal? annualIncomeTarget,
    Decimal? maxPositionWeight,
    Decimal? maxLeapsCost,
    Decimal? maxAssignmentValue,
    String? notes,
  }) async {
    final stamp = await _stamper.stamp();
    final plan = IncomeStrategyPlan(
      assetId: assetId,
      symbol: symbol.trim().toUpperCase(),
      market: market,
      currency: currency.trim().toUpperCase(),
      enabledSleeves: Set.unmodifiable(enabledSleeves),
      capitalBudget: capitalBudget,
      annualIncomeTarget: annualIncomeTarget,
      maxPositionWeight: maxPositionWeight,
      maxLeapsCost: maxLeapsCost,
      maxAssignmentValue: maxAssignmentValue,
      preserveDividend: preserveDividend,
      allowSharesCalledAway: allowSharesCalledAway,
      notes: notes,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.incomeStrategyPlans)
          .insertOnConflictUpdate(_toCompanion(plan));
      await _outbox.enqueue(table: tableName, rowId: assetId);
    });
    return plan;
  }

  Future<void> remove(IncomeStrategyPlan plan) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.incomeStrategyPlans,
      )..where((table) => table.id.equals(plan.assetId))).write(
        IncomeStrategyPlansCompanion(
          deletedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: tableName, rowId: plan.assetId);
    });
  }

  IncomeStrategyPlansCompanion _toCompanion(IncomeStrategyPlan plan) =>
      IncomeStrategyPlansCompanion.insert(
        id: plan.assetId,
        symbol: plan.symbol,
        market: plan.market,
        currency: plan.currency,
        enabledSleevesJson: Value(
          jsonEncode(
            [for (final sleeve in plan.enabledSleeves) sleeve.wire]..sort(),
          ),
        ),
        capitalBudget: Value(plan.capitalBudget),
        annualIncomeTarget: Value(plan.annualIncomeTarget),
        maxPositionWeight: Value(plan.maxPositionWeight),
        maxLeapsCost: Value(plan.maxLeapsCost),
        maxAssignmentValue: Value(plan.maxAssignmentValue),
        preserveDividend: Value(plan.preserveDividend),
        allowSharesCalledAway: Value(plan.allowSharesCalledAway),
        notes: Value(plan.notes),
        ownerUserId: plan.sync.ownerUserId,
        updatedAt: plan.sync.updatedAt,
        updatedByDevice: plan.sync.updatedByDevice,
        hlc: plan.sync.hlc,
        deletedAt: const Value(null),
      );
}

IncomeStrategyPlan _rowToDomain(IncomeStrategyPlanRow row) {
  final decoded = jsonDecode(row.enabledSleevesJson);
  final sleeves = <IncomeStrategySleeveKind>{};
  if (decoded is List) {
    for (final value in decoded.whereType<String>()) {
      final sleeve = incomeStrategySleeveKindFromWire(value);
      if (sleeve != null) sleeves.add(sleeve);
    }
  }
  return IncomeStrategyPlan(
    assetId: row.id,
    symbol: row.symbol,
    market: row.market,
    currency: row.currency,
    enabledSleeves: Set.unmodifiable(sleeves),
    capitalBudget: row.capitalBudget,
    annualIncomeTarget: row.annualIncomeTarget,
    maxPositionWeight: row.maxPositionWeight,
    maxLeapsCost: row.maxLeapsCost,
    maxAssignmentValue: row.maxAssignmentValue,
    preserveDividend: row.preserveDividend,
    allowSharesCalledAway: row.allowSharesCalledAway,
    notes: row.notes,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );
}
