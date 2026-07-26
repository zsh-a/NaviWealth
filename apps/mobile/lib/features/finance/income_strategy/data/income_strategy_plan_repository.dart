import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:uuid/uuid.dart';

import '../domain/income_strategy.dart';
import '../domain/income_strategy_plan.dart';

class IncomeStrategyPlanRepository {
  IncomeStrategyPlanRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _uuid = uuid;

  static const tableName = 'income_strategy_plans';
  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final Uuid _uuid;

  Stream<List<IncomeStrategyPlan>> watchActive(String ownerUserId) {
    final query = _db.select(_db.incomeStrategyPlans)
      ..where((table) => table.ownerUserId.equals(ownerUserId))
      ..where((table) => table.deletedAt.isNull())
      ..orderBy([(table) => OrderingTerm.asc(table.symbol)]);
    return query.watch().map(
      (rows) => rows.map(_rowToDomain).toList(growable: false),
    );
  }

  Future<IncomeStrategyPlan?> get({
    required String ownerUserId,
    required String assetId,
  }) async {
    final row =
        await (_db.select(_db.incomeStrategyPlans)
              ..where((table) => table.ownerUserId.equals(ownerUserId))
              ..where((table) => table.assetId.equals(assetId))
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
    required Map<IncomeStrategySleeveKind, IncomeStrategySleeveIntent>
    sleeveIntents,
    Decimal? capitalBudget,
    Decimal? annualIncomeTarget,
    Decimal? maxPositionWeight,
    String? notes,
  }) async {
    final stamp = await _stamper.stamp();
    final current =
        await (_db.select(_db.incomeStrategyPlans)
              ..where((table) => table.ownerUserId.equals(stamp.ownerUserId))
              ..where((table) => table.assetId.equals(assetId))
              ..limit(1))
            .getSingleOrNull();
    final plan = IncomeStrategyPlan(
      id: current?.id ?? _uuid.v4(),
      assetId: assetId,
      symbol: symbol.trim().toUpperCase(),
      market: market,
      currency: currency.trim().toUpperCase(),
      sleeveIntents: Map.unmodifiable(sleeveIntents),
      capitalBudget: capitalBudget,
      annualIncomeTarget: annualIncomeTarget,
      maxPositionWeight: maxPositionWeight,
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
      await _outbox.enqueue(table: tableName, rowId: plan.id);
    });
    return plan;
  }

  Future<void> remove(IncomeStrategyPlan plan) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(_db.incomeStrategyPlans)..where(
            (table) =>
                table.id.equals(plan.id) &
                table.ownerUserId.equals(stamp.ownerUserId),
          ))
          .write(
            IncomeStrategyPlansCompanion(
              deletedAt: Value(stamp.now),
              updatedAt: Value(stamp.now),
              updatedByDevice: Value(stamp.deviceId),
              hlc: Value(stamp.hlc),
            ),
          );
      await _outbox.enqueue(table: tableName, rowId: plan.id);
    });
  }

  IncomeStrategyPlansCompanion _toCompanion(IncomeStrategyPlan plan) =>
      IncomeStrategyPlansCompanion.insert(
        id: plan.id,
        assetId: plan.assetId,
        symbol: plan.symbol,
        market: plan.market,
        currency: plan.currency,
        sleeveIntentsJson: Value(_encodeIntents(plan.sleeveIntents)),
        capitalBudget: Value(plan.capitalBudget),
        annualIncomeTarget: Value(plan.annualIncomeTarget),
        maxPositionWeight: Value(plan.maxPositionWeight),
        notes: Value(plan.notes),
        ownerUserId: plan.sync.ownerUserId,
        updatedAt: plan.sync.updatedAt,
        updatedByDevice: plan.sync.updatedByDevice,
        hlc: plan.sync.hlc,
        deletedAt: const Value(null),
      );
}

String _encodeIntents(
  Map<IncomeStrategySleeveKind, IncomeStrategySleeveIntent> intents,
) => jsonEncode(<String, Object?>{
  for (final entry in intents.entries)
    entry.key.wire: <String, Object?>{
      'enabled': entry.value.enabled,
      'settings': <String, Object?>{
        for (final setting in entry.value.settings.entries)
          setting.key.wire: setting.value.toJson(),
      },
    },
});

Map<IncomeStrategySleeveKind, IncomeStrategySleeveIntent> _decodeIntents(
  String raw,
) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) return const {};
  final result = <IncomeStrategySleeveKind, IncomeStrategySleeveIntent>{};
  for (final entry in decoded.entries) {
    if (entry.key is! String || entry.value is! Map) continue;
    final body = entry.value as Map;
    final kind = incomeStrategySleeveKindFromWire(entry.key as String);
    final settings = <IncomeStrategySettingKey, IncomeStrategySettingValue>{};
    final rawSettings = body['settings'];
    if (rawSettings is Map) {
      for (final setting in rawSettings.entries) {
        if (setting.key is! String) continue;
        final value = IncomeStrategySettingValue.fromJson(setting.value);
        if (value != null) {
          settings[IncomeStrategySettingKey(setting.key as String)] = value;
        }
      }
    }
    result[kind] = IncomeStrategySleeveIntent(
      kind: kind,
      enabled: body['enabled'] == true,
      settings: Map.unmodifiable(settings),
    );
  }
  return Map.unmodifiable(result);
}

IncomeStrategyPlan _rowToDomain(IncomeStrategyPlanRow row) {
  return IncomeStrategyPlan(
    id: row.id,
    assetId: row.assetId,
    symbol: row.symbol,
    market: row.market,
    currency: row.currency,
    sleeveIntents: _decodeIntents(row.sleeveIntentsJson),
    capitalBudget: row.capitalBudget,
    annualIncomeTarget: row.annualIncomeTarget,
    maxPositionWeight: row.maxPositionWeight,
    notes: row.notes,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );
}
