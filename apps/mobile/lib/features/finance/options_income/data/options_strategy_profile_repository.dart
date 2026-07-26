import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';

import '../domain/options_strategy_profile.dart';

/// Read/write surface for the per-user [OptionsStrategyProfile] singleton.
///
/// Mirrors the `SettingsTable` pattern: the row's primary key is the
/// user's id rather than a separate uuid. The repository transparently
/// upserts, so callers don't need to know whether the row already exists.
class OptionsStrategyProfileRepository {
  OptionsStrategyProfileRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;

  static const String _tableName = 'options_strategy_profile';

  Stream<OptionsStrategyProfile?> watch(String ownerUserId) {
    final query = _db.select(_db.optionsStrategyProfileTable)
      ..where((t) => t.userId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..limit(1);
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : _rowToDomain(row),
    );
  }

  Future<OptionsStrategyProfile?> get(String ownerUserId) async {
    final row =
        await (_db.select(_db.optionsStrategyProfileTable)
              ..where((t) => t.userId.equals(ownerUserId))
              ..where((t) => t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _rowToDomain(row);
  }

  /// Upsert the singleton row. Returns the persisted profile (with its
  /// freshly-stamped [SyncMeta]).
  Future<OptionsStrategyProfile> upsert(OptionsStrategyProfile profile) async {
    final stamp = await _stamper.stamp();

    final companion = OptionsStrategyProfileTableCompanion.insert(
      userId: stamp.ownerUserId,
      mode: profile.mode.wire,
      allowedStrategiesJson: Value(
        _encodeStrategies(profile.allowedStrategies),
      ),
      minDte: profile.minDte,
      maxDte: profile.maxDte,
      deltaPutMin: profile.deltaPutMin,
      deltaPutMax: profile.deltaPutMax,
      deltaCallMin: profile.deltaCallMin,
      deltaCallMax: profile.deltaCallMax,
      maxCapitalPerTradePct: profile.maxCapitalPerTradePct,
      minAnnualizedYield: profile.minAnnualizedYield,
      minOpenInterest: profile.minOpenInterest,
      minVolume: profile.minVolume,
      maxBidAskSpreadPct: profile.maxBidAskSpreadPct,
      avoidEarnings: Value(profile.avoidEarnings),
      avoidMacroEvents: Value(profile.avoidMacroEvents),
      riskDisclosureAckAt: Value(profile.riskDisclosureAckAt),
      leapsMinDte: Value(profile.leapsMinDte),
      leapsMaxDte: Value(profile.leapsMaxDte),
      leapsDeltaMin: Value(profile.leapsDeltaMin),
      leapsDeltaMax: Value(profile.leapsDeltaMax),
      leapsMaxSpreadPct: Value(profile.leapsMaxSpreadPct),
      leapsMinOpenInterest: Value(profile.leapsMinOpenInterest),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
      deletedAt: const Value(null),
    );

    await _db.transaction(() async {
      await _db
          .into(_db.optionsStrategyProfileTable)
          .insertOnConflictUpdate(companion);
      await _outbox.enqueue(table: _tableName, rowId: stamp.ownerUserId);
    });

    return profile.copyWith(
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
  }

  /// Mark the OCC ODD as acknowledged. Optimised to a single targeted
  /// write rather than rewriting the full profile.
  Future<OptionsStrategyProfile> acknowledgeRiskDisclosure(
    OptionsStrategyProfile profile,
  ) async {
    return upsert(
      profile.copyWith(riskDisclosureAckAt: DateTime.now().toUtc()),
    );
  }
}

OptionsStrategyProfile _rowToDomain(OptionsStrategyProfileRow row) {
  return OptionsStrategyProfile(
    mode: parseOptionsStrategyMode(row.mode),
    allowedStrategies: _decodeStrategies(row.allowedStrategiesJson),
    minDte: row.minDte,
    maxDte: row.maxDte,
    deltaPutMin: row.deltaPutMin,
    deltaPutMax: row.deltaPutMax,
    deltaCallMin: row.deltaCallMin,
    deltaCallMax: row.deltaCallMax,
    maxCapitalPerTradePct: row.maxCapitalPerTradePct,
    minAnnualizedYield: row.minAnnualizedYield,
    minOpenInterest: row.minOpenInterest,
    minVolume: row.minVolume,
    maxBidAskSpreadPct: row.maxBidAskSpreadPct,
    avoidEarnings: row.avoidEarnings,
    avoidMacroEvents: row.avoidMacroEvents,
    riskDisclosureAckAt: row.riskDisclosureAckAt,
    leapsMinDte: row.leapsMinDte,
    leapsMaxDte: row.leapsMaxDte,
    leapsDeltaMin: row.leapsDeltaMin,
    leapsDeltaMax: row.leapsDeltaMax,
    leapsMaxSpreadPct: row.leapsMaxSpreadPct,
    leapsMinOpenInterest: row.leapsMinOpenInterest,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );
}

String _encodeStrategies(Set<OptionsStrategyKind> kinds) {
  final sorted = kinds.map((k) => k.wire).toList()..sort();
  return jsonEncode(sorted);
}

Set<OptionsStrategyKind> _decodeStrategies(String json) {
  if (json.trim().isEmpty) return const {};
  final decoded = jsonDecode(json);
  if (decoded is! List) return const {};
  final out = <OptionsStrategyKind>{};
  for (final value in decoded) {
    if (value is! String) continue;
    final kind = parseOptionsStrategyKind(value);
    if (kind != null) out.add(kind);
  }
  return out;
}
