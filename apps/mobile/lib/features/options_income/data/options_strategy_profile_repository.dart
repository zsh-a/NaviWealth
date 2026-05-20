import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/sync/op.dart';
import '../../../core/sync/op_outbox.dart';
import '../../../data/db/app_database.dart';
import '../../../data/domain/hlc.dart';
import '../../../data/domain/sync_meta.dart';
import '../../../data/repositories/mutation_context.dart';
import '../domain/options_strategy_profile.dart';

const _uuid = Uuid();

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
  })  : _db = db,
        _outbox = outbox,
        _stamper = stamper;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;

  Stream<OptionsStrategyProfile?> watch(String ownerUserId) {
    final query = _db.select(_db.optionsStrategyProfileTable)
      ..where((t) => t.userId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..limit(1);
    return query
        .watchSingleOrNull()
        .map((row) => row == null ? null : _rowToDomain(row));
  }

  Future<OptionsStrategyProfile?> get(String ownerUserId) async {
    final row = await (_db.select(_db.optionsStrategyProfileTable)
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
    final existing = await get(stamp.ownerUserId);

    final companion = OptionsStrategyProfileTableCompanion.insert(
      userId: stamp.ownerUserId,
      mode: profile.mode.wire,
      allowedStrategiesJson: Value(_encodeStrategies(profile.allowedStrategies)),
      minDte: profile.minDte,
      maxDte: profile.maxDte,
      deltaPutMin: profile.deltaPutMin,
      deltaPutMax: profile.deltaPutMax,
      deltaCallMin: profile.deltaCallMin,
      deltaCallMax: profile.deltaCallMax,
      maxCapitalPerTradePct: profile.maxCapitalPerTradePct,
      maxUnderlyingExposurePct: profile.maxUnderlyingExposurePct,
      minAnnualizedYield: profile.minAnnualizedYield,
      minOpenInterest: profile.minOpenInterest,
      minVolume: profile.minVolume,
      maxBidAskSpreadPct: profile.maxBidAskSpreadPct,
      avoidEarnings: Value(profile.avoidEarnings),
      avoidMacroEvents: Value(profile.avoidMacroEvents),
      onlyOnApprovedUnderlyings: Value(profile.onlyOnApprovedUnderlyings),
      riskDisclosureAckAt: Value(profile.riskDisclosureAckAt),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
      deletedAt: const Value(null),
    );

    final fields = _fields(
      userId: stamp.ownerUserId,
      profile: profile,
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
      deletedAt: null,
    );

    await _db.transaction(() async {
      await _db
          .into(_db.optionsStrategyProfileTable)
          .insertOnConflictUpdate(companion);
      await _enqueue(
        existing == null ? OpType.insert : OpType.update,
        stamp.ownerUserId,
        existing == null ? fields : _diffFields(fields, stamp),
        stamp,
      );
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

  Future<void> _enqueue(
    OpType type,
    String rowId,
    Map<String, Object?> fields,
    MutationStamp stamp,
  ) {
    return _outbox.enqueue(
      Op(
        opId: _uuid.v4(),
        tableName: 'options_strategy_profile',
        rowId: rowId,
        opType: type,
        fieldsDiff: fields,
        hlc: stamp.hlc,
        deviceId: stamp.deviceId,
      ),
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
    maxUnderlyingExposurePct: row.maxUnderlyingExposurePct,
    minAnnualizedYield: row.minAnnualizedYield,
    minOpenInterest: row.minOpenInterest,
    minVolume: row.minVolume,
    maxBidAskSpreadPct: row.maxBidAskSpreadPct,
    avoidEarnings: row.avoidEarnings,
    avoidMacroEvents: row.avoidMacroEvents,
    onlyOnApprovedUnderlyings: row.onlyOnApprovedUnderlyings,
    riskDisclosureAckAt: row.riskDisclosureAckAt,
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

Map<String, Object?> _fields({
  required String userId,
  required OptionsStrategyProfile profile,
  required String ownerUserId,
  required DateTime updatedAt,
  required String updatedByDevice,
  required Hlc hlc,
  required DateTime? deletedAt,
}) {
  return {
    'user_id': userId,
    'mode': profile.mode.wire,
    'allowed_strategies_json': _encodeStrategies(profile.allowedStrategies),
    'min_dte': profile.minDte,
    'max_dte': profile.maxDte,
    'delta_put_min': profile.deltaPutMin.toString(),
    'delta_put_max': profile.deltaPutMax.toString(),
    'delta_call_min': profile.deltaCallMin.toString(),
    'delta_call_max': profile.deltaCallMax.toString(),
    'max_capital_per_trade_pct': profile.maxCapitalPerTradePct.toString(),
    'max_underlying_exposure_pct': profile.maxUnderlyingExposurePct.toString(),
    'min_annualized_yield': profile.minAnnualizedYield.toString(),
    'min_open_interest': profile.minOpenInterest,
    'min_volume': profile.minVolume,
    'max_bid_ask_spread_pct': profile.maxBidAskSpreadPct.toString(),
    'avoid_earnings': profile.avoidEarnings,
    'avoid_macro_events': profile.avoidMacroEvents,
    'only_on_approved_underlyings': profile.onlyOnApprovedUnderlyings,
    'risk_disclosure_ack_at': _isoOrNull(profile.riskDisclosureAckAt),
    'owner_user_id': ownerUserId,
    'updated_at': _iso(updatedAt),
    'updated_by_device': updatedByDevice,
    'hlc': hlc.toString(),
    'deleted_at': _isoOrNull(deletedAt),
  };
}

Map<String, Object?> _diffFields(
  Map<String, Object?> fields,
  MutationStamp stamp,
) {
  // For updates we still ship the full set: profile changes are rare and
  // every field is small, so paying the bytes is cheaper than tracking
  // dirty fields client-side. The `user_id` PK is omitted because it is
  // never mutated.
  final out = Map<String, Object?>.from(fields);
  out.remove('user_id');
  return out;
}

String _iso(DateTime value) => value.toUtc().toIso8601String();
String? _isoOrNull(DateTime? value) => value == null ? null : _iso(value);
