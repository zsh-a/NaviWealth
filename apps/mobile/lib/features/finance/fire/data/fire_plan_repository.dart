import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';

import '../domain/fire_plan.dart';

/// Synced source of truth for the current user's FIRE planning assumptions.
class FirePlanRepository {
  FirePlanRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper;

  static const _tableName = 'fire_plans';

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;

  Stream<FirePlan?> watch(String ownerUserId) {
    final query = _db.select(_db.firePlans)
      ..where((t) => t.userId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..limit(1);
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : _rowToDomain(row),
    );
  }

  Future<FirePlan?> get(String ownerUserId) async {
    final row =
        await (_db.select(_db.firePlans)
              ..where((t) => t.userId.equals(ownerUserId))
              ..where((t) => t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _rowToDomain(row);
  }

  Future<FirePlan> upsert(FirePlan plan) async {
    final stamp = await _stamper.stamp();
    final companion = FirePlansCompanion.insert(
      userId: stamp.ownerUserId,
      baseCurrency: plan.baseCurrency,
      monthlyExpenses: plan.monthlyExpenses,
      monthlySurplus: plan.monthlySurplus,
      inflationRate: plan.inflationRate,
      targetNetWorth: plan.targetNetWorth,
      safeWithdrawalRate: plan.safeWithdrawalRate,
      targetCashBucketMonths: plan.targetCashBucketMonths,
      lifestyleMode: plan.lifestyleMode.name,
      reservesJson: Value(
        jsonEncode(plan.reserves.map((reserve) => reserve.toJson()).toList()),
      ),
      riskSettingsJson: Value(jsonEncode(plan.riskSettings.toJson())),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
      deletedAt: const Value(null),
    );

    await _db.transaction(() async {
      await _db.into(_db.firePlans).insertOnConflictUpdate(companion);
      await _outbox.enqueue(table: _tableName, rowId: stamp.ownerUserId);
    });
    return plan;
  }

  FirePlan _rowToDomain(FirePlanRow row) {
    return FirePlan(
      id: FirePlan.kDefaultFirePlanId,
      baseCurrency: row.baseCurrency,
      monthlyExpenses: row.monthlyExpenses,
      monthlySurplus: row.monthlySurplus,
      inflationRate: row.inflationRate,
      targetNetWorth: row.targetNetWorth,
      safeWithdrawalRate: row.safeWithdrawalRate,
      targetCashBucketMonths: row.targetCashBucketMonths,
      lifestyleMode: _parseLifestyle(row.lifestyleMode),
      reserves: _decodeReserves(row.reservesJson, row.baseCurrency),
      riskSettings: _decodeRiskSettings(row.riskSettingsJson),
    );
  }
}

FireLifestyleMode _parseLifestyle(String raw) {
  return FireLifestyleMode.values.firstWhere(
    (mode) => mode.name == raw,
    orElse: () => FireLifestyleMode.standard,
  );
}

List<FireReserve> _decodeReserves(String raw, String baseCurrency) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (value) => FireReserve.fromJson(
            Map<String, Object?>.from(value),
            baseCurrency,
          ),
        )
        .toList(growable: false);
  } on FormatException {
    return const [];
  }
}

FireRiskSettings _decodeRiskSettings(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const FireRiskSettings();
    return FireRiskSettings.fromJson(Map<String, Object?>.from(decoded));
  } on FormatException {
    return const FireRiskSettings();
  }
}
