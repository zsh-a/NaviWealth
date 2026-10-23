import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../../core/persistence/app_database.dart';
import '../domain/watchlist_simulation.dart';
import 'watchlist_simulation_allocation_store.dart';

/// Local observation curves derived from the selected allocation lineage.
/// This store cannot enqueue sync mutations or write real investment state.
class WatchlistSimulationObservationStore {
  WatchlistSimulationObservationStore(this._db, this._allocations);

  final AppDatabase _db;
  final WatchlistSimulationAllocationStore _allocations;

  Stream<List<WatchlistSimulationObservation>> watchObservations({
    required String ownerUserId,
    required String simulationId,
  }) async* {
    final active = await ensureBaseline(
      ownerUserId: ownerUserId,
      simulationId: simulationId,
    );
    if (!active) {
      yield const <WatchlistSimulationObservation>[];
      return;
    }
    final query = _db.select(_db.watchlistSimulationObservations)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.simulationId.equals(simulationId))
      ..orderBy([(t) => OrderingTerm.asc(t.observationDay)]);
    yield* query.watch().map(
      (rows) => rows.map(_observationFromRow).toList(growable: false),
    );
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
    required String allocationBasisKey,
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
    final allocationReady = await ensureBaseline(
      ownerUserId: ownerUserId,
      simulationId: simulation.id,
    );
    if (!allocationReady) {
      throw StateError('Watchlist simulation allocation is not usable.');
    }
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
      final allocation = await resolveAllocation(
        ownerUserId: ownerUserId,
        simulationId: simulation.id,
      );
      if (!allocation.isUsable ||
          allocation.allocationBasisKey != allocationBasisKey) {
        throw StateError('Watchlist simulation allocation changed.');
      }
      final validBasisKeys = allocation.validAllocationBasisKeys;
      final observationQuery = _db.select(_db.watchlistSimulationObservations)
        ..where((t) => t.ownerUserId.equals(ownerUserId))
        ..where((t) => t.simulationId.equals(simulation.id))
        ..orderBy([(t) => OrderingTerm.asc(t.observationDay)]);
      final allRows = await observationQuery.get();
      final validRows = <WatchlistSimulationObservationRow>[];
      for (final row in allRows) {
        if (watchlistSimulationObservationIsInAllocationLineage(
          allocationBasisKey: row.allocationBasisKey,
          validAllocationBasisKeys: validBasisKeys,
        )) {
          validRows.add(row);
        } else {
          await (_db.delete(
            _db.watchlistSimulationObservations,
          )..where((t) => t.id.equals(row.id))).go();
        }
      }
      final latest = validRows.lastOrNull;
      if (latest != null && latest.observationDay.compareTo(day) > 0) return;

      final current = validRows
          .where((row) => row.observationDay == day)
          .firstOrNull;
      if (current != null && observedAt.isBefore(current.observedAt)) {
        result = _observationFromRow(current);
        return;
      }
      final previous = validRows
          .where((row) => row.observationDay.compareTo(day) < 0)
          .lastOrNull;
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
        allocationBasisKey: Value(allocationBasisKey),
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
        allocationBasisKey: allocationBasisKey,
      );
    });
    return result;
  }

  /// Merges historical daily returns and rebuilds the projected-value chain.
  ///
  /// A simulation may already have a newer live observation when the user
  /// returns after several days. Inserting the missed days through
  /// [recordObservation] would be rejected as out-of-order and would leave
  /// later projected values stale. This method fills only missing days in the
  /// active allocation lineage (or repairs incomplete days when requested), then
  /// recomputes every later row from the baseline in one transaction. Observations
  /// remain a local derived read model; no sync/outbox rows are created.
  Future<int> mergeObservationInputs({
    required WatchlistSimulation simulation,
    required Iterable<WatchlistSimulationObservationInput> inputs,
    required String allocationBasisKey,
    bool repairIncompleteObservations = false,
  }) async {
    final baselineDay = _observationDay(simulation.baselineAt);
    final byDay = <String, WatchlistSimulationObservationInput>{};
    for (final input in inputs) {
      if (input.observedAt.isBefore(simulation.baselineAt) ||
          input.pricedWeight <= Decimal.zero ||
          input.weightedDailyChange < -Decimal.one ||
          input.pricedWeight > Decimal.one ||
          input.missingQuoteWeight < Decimal.zero ||
          input.missingQuoteWeight > Decimal.one) {
        throw ArgumentError('Invalid paper simulation observation input.');
      }
      final day = _observationDay(input.observedAt);
      if (day == baselineDay) continue;
      byDay[day] = input;
    }
    if (byDay.isEmpty) return 0;

    final ownerUserId = simulation.sync.ownerUserId;
    final allocationReady = await ensureBaseline(
      ownerUserId: ownerUserId,
      simulationId: simulation.id,
    );
    if (!allocationReady) {
      throw StateError('Watchlist simulation allocation is not usable.');
    }

    var changedDays = 0;
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
      final allocation = await resolveAllocation(
        ownerUserId: ownerUserId,
        simulationId: simulation.id,
      );
      if (!allocation.isUsable ||
          allocation.allocationBasisKey != allocationBasisKey) {
        throw StateError('Watchlist simulation allocation changed.');
      }
      var allocationEffectiveAt = simulation.baselineAt.toUtc();
      final allocationVersionId = allocation.allocationVersionId;
      if (allocationVersionId != null) {
        final version =
            await (_db.select(_db.watchlistSimulationAllocationVersions)..where(
                  (t) =>
                      t.ownerUserId.equals(ownerUserId) &
                      t.simulationId.equals(simulation.id) &
                      t.id.equals(allocationVersionId),
                ))
                .getSingleOrNull();
        if (version != null) {
          allocationEffectiveAt = version.effectiveAt.toUtc();
        }
      }
      final validBasisKeys = allocation.validAllocationBasisKeys;
      final observationQuery = _db.select(_db.watchlistSimulationObservations)
        ..where((t) => t.ownerUserId.equals(ownerUserId))
        ..where((t) => t.simulationId.equals(simulation.id))
        ..orderBy([(t) => OrderingTerm.asc(t.observationDay)]);
      final allRows = await observationQuery.get();
      final validRows = <WatchlistSimulationObservationRow>[];
      for (final row in allRows) {
        if (!watchlistSimulationObservationIsInAllocationLineage(
          allocationBasisKey: row.allocationBasisKey,
          validAllocationBasisKeys: validBasisKeys,
        )) {
          await (_db.delete(
            _db.watchlistSimulationObservations,
          )..where((t) => t.id.equals(row.id))).go();
        } else {
          validRows.add(row);
        }
      }

      final sortedEntries = byDay.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      validRows.sort(
        (left, right) => left.observationDay.compareTo(right.observationDay),
      );
      var existingIndex = 0;
      String? previousBasis;
      final now = DateTime.now().toUtc();
      for (final entry in sortedEntries) {
        // Preserve recorded rows unless explicitly repairing an incomplete day
        // with better coverage in the same allocation. Complete observations
        // and earlier allocation lineages remain unchanged.
        final input = entry.value;
        while (existingIndex < validRows.length &&
            validRows[existingIndex].observationDay.compareTo(entry.key) < 0) {
          previousBasis = validRows[existingIndex].allocationBasisKey;
          existingIndex++;
        }
        if (existingIndex < validRows.length &&
            validRows[existingIndex].observationDay == entry.key) {
          final existing = validRows[existingIndex];
          previousBasis = existing.allocationBasisKey;
          if (repairIncompleteObservations &&
              existing.allocationBasisKey == allocationBasisKey &&
              existing.missingQuoteWeight > Decimal.zero &&
              input.pricedWeight > existing.pricedWeight &&
              input.missingQuoteWeight < existing.missingQuoteWeight) {
            await (_db.update(
              _db.watchlistSimulationObservations,
            )..where((t) => t.id.equals(existing.id))).write(
              WatchlistSimulationObservationsCompanion(
                observedAt: Value(input.observedAt.toUtc()),
                weightedDailyChange: Value(input.weightedDailyChange),
                pricedWeight: Value(input.pricedWeight),
                missingQuoteWeight: Value(input.missingQuoteWeight),
                updatedAt: Value(now),
              ),
            );
            changedDays++;
          }
          existingIndex++;
          continue;
        }
        if (previousBasis != null &&
            previousBasis != allocationBasisKey &&
            input.observedAt.toUtc().isBefore(allocationEffectiveAt)) {
          continue;
        }
        await _db
            .into(_db.watchlistSimulationObservations)
            .insert(
              WatchlistSimulationObservationsCompanion.insert(
                id: _observationId(
                  simulationId: simulation.id,
                  observationDay: entry.key,
                ),
                ownerUserId: ownerUserId,
                simulationId: simulation.id,
                observationDay: entry.key,
                observedAt: input.observedAt.toUtc(),
                projectedValue: Decimal.zero,
                weightedDailyChange: input.weightedDailyChange,
                pricedWeight: input.pricedWeight,
                missingQuoteWeight: input.missingQuoteWeight,
                allocationBasisKey: Value(allocationBasisKey),
                createdAt: now,
                updatedAt: now,
              ),
            );
        previousBasis = allocationBasisKey;
        changedDays++;
      }

      final rows = await observationQuery.get();
      rows.sort(
        (left, right) => left.observationDay.compareTo(right.observationDay),
      );
      final baselineRow = rows
          .where((row) => row.observationDay == baselineDay)
          .firstOrNull;
      var projectedValue =
          baselineRow?.projectedValue ?? simulation.startingCapital;
      for (final row in rows) {
        if (row.observationDay.compareTo(baselineDay) < 0) continue;
        final nextProjected = row.observationDay == baselineDay
            ? projectedValue
            : (projectedValue * (Decimal.one + row.weightedDailyChange)).round(
                scale: 8,
              );
        if (row.projectedValue != nextProjected) {
          await (_db.update(
            _db.watchlistSimulationObservations,
          )..where((t) => t.id.equals(row.id))).write(
            WatchlistSimulationObservationsCompanion(
              projectedValue: Value(nextProjected),
              updatedAt: Value(now),
            ),
          );
        }
        projectedValue = nextProjected;
      }
    });
    return changedDays;
  }

  /// Advances already trusted paper dividend rows from entitlement to gross
  /// receivable and then to gross paper cash using only persisted dates.
  ///
  /// This reducer is intentionally provider-independent and monotonic. Once a
  /// trusted amount reaches a later lifecycle state, offline refreshes or a
  /// device with an earlier clock cannot move it backward.
  Future<bool> ensureBaseline({
    required String ownerUserId,
    required String simulationId,
  }) => _db.transaction(() async {
    final simulation =
        await (_db.select(_db.watchlistSimulations)..where(
              (t) =>
                  t.ownerUserId.equals(ownerUserId) & t.id.equals(simulationId),
            ))
            .getSingleOrNull();
    if (simulation == null || simulation.deletedAt != null) return false;
    final allocation = await resolveAllocation(
      ownerUserId: ownerUserId,
      simulationId: simulationId,
    );
    if (!allocation.isUsable || allocation.cashWeight == null) return false;
    final baselineId = _observationId(
      simulationId: simulationId,
      observationDay: _observationDay(simulation.baselineAt),
    );
    final existing = await (_db.select(
      _db.watchlistSimulationObservations,
    )..where((t) => t.id.equals(baselineId))).getSingleOrNull();
    if (existing != null) return true;
    final now = DateTime.now().toUtc();
    await _db
        .into(_db.watchlistSimulationObservations)
        .insert(
          WatchlistSimulationObservationsCompanion.insert(
            id: baselineId,
            ownerUserId: ownerUserId,
            simulationId: simulationId,
            observationDay: _observationDay(simulation.baselineAt),
            observedAt: simulation.baselineAt.toUtc(),
            projectedValue: simulation.startingCapital,
            weightedDailyChange: Decimal.zero,
            pricedWeight: Decimal.zero,
            missingQuoteWeight: Decimal.one - allocation.cashWeight!,
            allocationBasisKey: const Value(
              kWatchlistSimulationBaselineBasisKey,
            ),
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return true;
  });

  static String _observationId({
    required String simulationId,
    required String observationDay,
  }) => 'watchlist-simulation-observation:$simulationId:$observationDay';

  Future<ResolvedWatchlistSimulationAllocation> resolveAllocation({
    required String ownerUserId,
    required String simulationId,
  }) => _allocations.resolve(
    ownerUserId: ownerUserId,
    simulationId: simulationId,
  );
}

String _observationDay(DateTime value) {
  final utc = value.toUtc();
  String twoDigits(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${twoDigits(utc.month)}-${twoDigits(utc.day)}';
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
  allocationBasisKey: row.allocationBasisKey,
);
