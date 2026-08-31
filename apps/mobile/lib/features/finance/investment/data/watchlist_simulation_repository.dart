import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class WatchlistSimulation {
  const WatchlistSimulation({
    required this.id,
    required this.collectionId,
    required this.name,
    required this.baseCurrency,
    required this.startingCapital,
    required this.cashWeight,
    required this.baselineAt,
    required this.createdAt,
    required this.sync,
  });

  final String id;
  final String collectionId;
  final String name;
  final String baseCurrency;
  final Decimal startingCapital;
  final Decimal cashWeight;
  final DateTime baselineAt;
  final DateTime createdAt;
  final SyncMeta sync;
}

class WatchlistSimulationPosition {
  const WatchlistSimulationPosition({
    required this.id,
    required this.simulationId,
    required this.watchlistItemId,
    required this.targetWeight,
    required this.createdAt,
    required this.sync,
  });

  final String id;
  final String simulationId;
  final String watchlistItemId;
  final Decimal targetWeight;
  final DateTime createdAt;
  final SyncMeta sync;
}

class WatchlistSimulationObservation {
  const WatchlistSimulationObservation({
    required this.id,
    required this.simulationId,
    required this.observationDay,
    required this.observedAt,
    required this.projectedValue,
    required this.weightedDailyChange,
    required this.pricedWeight,
    required this.missingQuoteWeight,
  });

  final String id;
  final String simulationId;
  final String observationDay;
  final DateTime observedAt;
  final Decimal projectedValue;
  final Decimal weightedDailyChange;
  final Decimal pricedWeight;
  final Decimal missingQuoteWeight;
}

/// Paper-only repository for watchlist allocation scenarios.
///
/// This repository intentionally has no dependency on the real investment
/// portfolio, lots, accounts, journal entries, or postings. Every mutation is
/// confined to the `watchlist_simulation*` row families; observations remain
/// derived and local-only while simulation inputs use the sync outbox.
class WatchlistSimulationRepository {
  WatchlistSimulationRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper;

  static const simulationsTable = 'watchlist_simulations';
  static const positionsTable = 'watchlist_simulation_positions';

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;

  Stream<List<WatchlistSimulation>> watchActive(String ownerUserId) {
    final query = _db.select(_db.watchlistSimulations)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_simulationFromRow).toList(growable: false),
    );
  }

  Stream<List<WatchlistSimulationPosition>> watchPositions({
    required String ownerUserId,
    required String simulationId,
  }) {
    final query = _db.select(_db.watchlistSimulationPositions)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.simulationId.equals(simulationId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_positionFromRow).toList(growable: false),
    );
  }

  Stream<List<WatchlistSimulationObservation>> watchObservations({
    required String ownerUserId,
    required String simulationId,
  }) {
    final query = _db.select(_db.watchlistSimulationObservations)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.simulationId.equals(simulationId))
      ..orderBy([(t) => OrderingTerm.asc(t.observationDay)]);
    return query.watch().map(
      (rows) => rows.map(_observationFromRow).toList(growable: false),
    );
  }

  Future<WatchlistSimulation> create({
    required String collectionId,
    required String name,
    required String baseCurrency,
    required Decimal startingCapital,
    required Map<String, Decimal> targetWeights,
    required Decimal cashWeight,
  }) async {
    final normalizedName = _requireName(name);
    final normalizedCurrency = _requireCurrency(baseCurrency);
    if (collectionId.trim().isEmpty) {
      throw ArgumentError.value(collectionId, 'collectionId');
    }
    if (startingCapital <= Decimal.zero) {
      throw ArgumentError.value(startingCapital, 'startingCapital');
    }
    _validateAllocation(targetWeights, cashWeight);

    final stamp = await _stamper.stamp();
    final simulation = WatchlistSimulation(
      id: _uuid.v4(),
      collectionId: collectionId,
      name: normalizedName,
      baseCurrency: normalizedCurrency,
      startingCapital: startingCapital,
      cashWeight: cashWeight,
      baselineAt: stamp.now,
      createdAt: stamp.now,
      sync: _syncFromStamp(stamp),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.watchlistSimulations)
          .insert(
            WatchlistSimulationsCompanion.insert(
              id: simulation.id,
              collectionId: simulation.collectionId,
              name: simulation.name,
              baseCurrency: simulation.baseCurrency,
              startingCapital: simulation.startingCapital,
              cashWeight: Value(simulation.cashWeight),
              baselineAt: simulation.baselineAt,
              createdAt: simulation.createdAt,
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
          );
      await _db
          .into(_db.watchlistSimulationObservations)
          .insert(
            WatchlistSimulationObservationsCompanion.insert(
              id: _observationId(
                simulationId: simulation.id,
                observationDay: _observationDay(simulation.baselineAt),
              ),
              ownerUserId: stamp.ownerUserId,
              simulationId: simulation.id,
              observationDay: _observationDay(simulation.baselineAt),
              observedAt: simulation.baselineAt,
              projectedValue: simulation.startingCapital,
              weightedDailyChange: Decimal.zero,
              pricedWeight: Decimal.zero,
              missingQuoteWeight: Decimal.one - simulation.cashWeight,
              createdAt: stamp.now,
              updatedAt: stamp.now,
            ),
          );
      await _outbox.enqueue(table: simulationsTable, rowId: simulation.id);
      for (final entry in targetWeights.entries) {
        await _writePosition(
          simulationId: simulation.id,
          watchlistItemId: entry.key,
          targetWeight: entry.value,
          createdAt: stamp.now,
          stamp: stamp,
        );
      }
    });
    return simulation;
  }

  /// Records one derived observation per UTC calendar day.
  ///
  /// Repeated quotes for the same day replace that day's projection using
  /// the prior day's value, so refreshes never compound twice. The creation
  /// day remains the starting-capital baseline because the simulation does
  /// not know prices from the instant it was created.
  Future<WatchlistSimulationObservation?> recordObservation({
    required WatchlistSimulation simulation,
    required DateTime observedAt,
    required Decimal weightedDailyChange,
    required Decimal pricedWeight,
    required Decimal missingQuoteWeight,
  }) async {
    if (observedAt.isBefore(simulation.baselineAt) ||
        pricedWeight <= Decimal.zero) {
      return null;
    }
    if (weightedDailyChange < -Decimal.one ||
        pricedWeight < Decimal.zero ||
        pricedWeight > Decimal.one ||
        missingQuoteWeight < Decimal.zero ||
        missingQuoteWeight > Decimal.one) {
      throw ArgumentError('Invalid paper simulation observation.');
    }
    final ownerUserId = simulation.sync.ownerUserId;
    final day = _observationDay(observedAt);
    final now = DateTime.now().toUtc();
    WatchlistSimulationObservation? result;
    await _db.transaction(() async {
      final activeSimulation =
          await (_db.select(_db.watchlistSimulations)..where(
                (t) =>
                    t.id.equals(simulation.id) &
                    t.ownerUserId.equals(ownerUserId) &
                    t.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (activeSimulation == null) return;

      final latestQuery = _db.select(_db.watchlistSimulationObservations)
        ..where((t) => t.ownerUserId.equals(ownerUserId))
        ..where((t) => t.simulationId.equals(simulation.id))
        ..orderBy([(t) => OrderingTerm.desc(t.observationDay)])
        ..limit(1);
      final latest = await latestQuery.getSingleOrNull();
      if (latest != null && latest.observationDay.compareTo(day) > 0) return;

      final currentQuery = _db.select(_db.watchlistSimulationObservations)
        ..where((t) => t.ownerUserId.equals(ownerUserId))
        ..where((t) => t.simulationId.equals(simulation.id))
        ..where((t) => t.observationDay.equals(day));
      final current = await currentQuery.getSingleOrNull();
      if (current != null && observedAt.isBefore(current.observedAt)) {
        result = _observationFromRow(current);
        return;
      }

      final previousQuery = _db.select(_db.watchlistSimulationObservations)
        ..where((t) => t.ownerUserId.equals(ownerUserId))
        ..where((t) => t.simulationId.equals(simulation.id))
        ..where((t) => t.observationDay.isSmallerThanValue(day))
        ..orderBy([(t) => OrderingTerm.desc(t.observationDay)])
        ..limit(1);
      final previous = await previousQuery.getSingleOrNull();
      final projectedValue = previous == null
          ? simulation.startingCapital
          : (previous.projectedValue * (Decimal.one + weightedDailyChange))
                .round(scale: 8);
      final id = _observationId(
        simulationId: simulation.id,
        observationDay: day,
      );
      final row = WatchlistSimulationObservationsCompanion.insert(
        id: id,
        ownerUserId: ownerUserId,
        simulationId: simulation.id,
        observationDay: day,
        observedAt: observedAt,
        projectedValue: projectedValue,
        weightedDailyChange: weightedDailyChange,
        pricedWeight: pricedWeight,
        missingQuoteWeight: missingQuoteWeight,
        createdAt: current?.createdAt ?? now,
        updatedAt: now,
      );
      await _db
          .into(_db.watchlistSimulationObservations)
          .insertOnConflictUpdate(row);
      result = WatchlistSimulationObservation(
        id: id,
        simulationId: simulation.id,
        observationDay: day,
        observedAt: observedAt,
        projectedValue: projectedValue,
        weightedDailyChange: weightedDailyChange,
        pricedWeight: pricedWeight,
        missingQuoteWeight: missingQuoteWeight,
      );
    });
    return result;
  }

  Future<void> replaceAllocation({
    required WatchlistSimulation simulation,
    required Map<String, Decimal> targetWeights,
    required Decimal cashWeight,
  }) async {
    _validateAllocation(targetWeights, cashWeight);
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      final activeSimulation =
          await (_db.select(_db.watchlistSimulations)..where(
                (t) =>
                    t.id.equals(simulation.id) &
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (activeSimulation == null) {
        throw StateError('Watchlist simulation is not active.');
      }
      await (_db.update(_db.watchlistSimulations)..where(
            (t) =>
                t.id.equals(simulation.id) &
                t.ownerUserId.equals(stamp.ownerUserId),
          ))
          .write(
            WatchlistSimulationsCompanion(
              cashWeight: Value(cashWeight),
              updatedAt: Value(stamp.now),
              updatedByDevice: Value(stamp.deviceId),
              hlc: Value(stamp.hlc),
            ),
          );
      await _outbox.enqueue(table: simulationsTable, rowId: simulation.id);

      final existingRows =
          await (_db.select(_db.watchlistSimulationPositions)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.simulationId.equals(simulation.id),
              ))
              .get();
      final existingByItemId = <String, WatchlistSimulationPositionRow>{
        for (final row in existingRows) row.watchlistItemId: row,
      };
      for (final row in existingRows) {
        if (targetWeights.containsKey(row.watchlistItemId) ||
            row.deletedAt != null) {
          continue;
        }
        await (_db.update(
          _db.watchlistSimulationPositions,
        )..where((t) => t.id.equals(row.id))).write(
          WatchlistSimulationPositionsCompanion(
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
            deletedAt: Value(stamp.now),
          ),
        );
        await _outbox.enqueue(table: positionsTable, rowId: row.id);
      }
      for (final entry in targetWeights.entries) {
        await _writePosition(
          simulationId: simulation.id,
          watchlistItemId: entry.key,
          targetWeight: entry.value,
          createdAt: existingByItemId[entry.key]?.createdAt ?? stamp.now,
          stamp: stamp,
        );
      }
    });
  }

  Future<void> delete(WatchlistSimulation simulation) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(_db.watchlistSimulations)..where(
            (t) =>
                t.id.equals(simulation.id) &
                t.ownerUserId.equals(stamp.ownerUserId) &
                t.deletedAt.isNull(),
          ))
          .write(
            WatchlistSimulationsCompanion(
              updatedAt: Value(stamp.now),
              updatedByDevice: Value(stamp.deviceId),
              hlc: Value(stamp.hlc),
              deletedAt: Value(stamp.now),
            ),
          );
      await _outbox.enqueue(table: simulationsTable, rowId: simulation.id);

      final activePositions =
          await (_db.select(_db.watchlistSimulationPositions)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.simulationId.equals(simulation.id) &
                    t.deletedAt.isNull(),
              ))
              .get();
      for (final row in activePositions) {
        await (_db.update(
          _db.watchlistSimulationPositions,
        )..where((t) => t.id.equals(row.id))).write(
          WatchlistSimulationPositionsCompanion(
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
            deletedAt: Value(stamp.now),
          ),
        );
        await _outbox.enqueue(table: positionsTable, rowId: row.id);
      }
      await (_db.delete(_db.watchlistSimulationObservations)..where(
            (t) =>
                t.ownerUserId.equals(stamp.ownerUserId) &
                t.simulationId.equals(simulation.id),
          ))
          .go();
    });
  }

  Future<void> _writePosition({
    required String simulationId,
    required String watchlistItemId,
    required Decimal targetWeight,
    required DateTime createdAt,
    required MutationStamp stamp,
  }) async {
    final id = _positionId(
      simulationId: simulationId,
      watchlistItemId: watchlistItemId,
    );
    await _db
        .into(_db.watchlistSimulationPositions)
        .insertOnConflictUpdate(
          WatchlistSimulationPositionsCompanion.insert(
            id: id,
            simulationId: simulationId,
            watchlistItemId: watchlistItemId,
            targetWeight: targetWeight,
            createdAt: createdAt,
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
            deletedAt: const Value(null),
          ),
        );
    await _outbox.enqueue(table: positionsTable, rowId: id);
  }

  static void _validateAllocation(
    Map<String, Decimal> targetWeights,
    Decimal cashWeight,
  ) {
    if (cashWeight < Decimal.zero || cashWeight > Decimal.one) {
      throw ArgumentError.value(cashWeight, 'cashWeight');
    }
    var total = cashWeight;
    for (final entry in targetWeights.entries) {
      if (entry.key.trim().isEmpty ||
          entry.value <= Decimal.zero ||
          entry.value > Decimal.one) {
        throw ArgumentError('Invalid target allocation for ${entry.key}.');
      }
      total += entry.value;
    }
    if (total != Decimal.one) {
      throw ArgumentError.value(total, 'allocationTotal');
    }
  }

  static String _requireName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 80) {
      throw ArgumentError.value(value, 'name');
    }
    return normalized;
  }

  static String _requireCurrency(String value) {
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z][A-Z0-9]{2,7}$').hasMatch(normalized)) {
      throw ArgumentError.value(value, 'baseCurrency');
    }
    return normalized;
  }

  static String _positionId({
    required String simulationId,
    required String watchlistItemId,
  }) {
    final digest = sha256.convert(
      utf8.encode('$simulationId\u0000$watchlistItemId'),
    );
    return 'watchlist-simulation-position:$digest';
  }

  static String _observationId({
    required String simulationId,
    required String observationDay,
  }) => 'watchlist-simulation-observation:$simulationId:$observationDay';
}

String _observationDay(DateTime value) {
  final utc = value.toUtc();
  String twoDigits(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${twoDigits(utc.month)}-${twoDigits(utc.day)}';
}

WatchlistSimulation _simulationFromRow(WatchlistSimulationRow row) {
  return WatchlistSimulation(
    id: row.id,
    collectionId: row.collectionId,
    name: row.name,
    baseCurrency: row.baseCurrency,
    startingCapital: row.startingCapital,
    cashWeight: row.cashWeight,
    baselineAt: row.baselineAt,
    createdAt: row.createdAt,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
      deletedAt: row.deletedAt,
    ),
  );
}

WatchlistSimulationPosition _positionFromRow(
  WatchlistSimulationPositionRow row,
) {
  return WatchlistSimulationPosition(
    id: row.id,
    simulationId: row.simulationId,
    watchlistItemId: row.watchlistItemId,
    targetWeight: row.targetWeight,
    createdAt: row.createdAt,
    sync: SyncMeta(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
      deletedAt: row.deletedAt,
    ),
  );
}

WatchlistSimulationObservation _observationFromRow(
  WatchlistSimulationObservationRow row,
) => WatchlistSimulationObservation(
  id: row.id,
  simulationId: row.simulationId,
  observationDay: row.observationDay,
  observedAt: row.observedAt,
  projectedValue: row.projectedValue,
  weightedDailyChange: row.weightedDailyChange,
  pricedWeight: row.pricedWeight,
  missingQuoteWeight: row.missingQuoteWeight,
);

SyncMeta _syncFromStamp(MutationStamp stamp) => SyncMeta(
  ownerUserId: stamp.ownerUserId,
  updatedAt: stamp.now,
  updatedByDevice: stamp.deviceId,
  hlc: stamp.hlc,
);
