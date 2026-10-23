import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';
import 'package:uuid/uuid.dart';

import '../domain/watchlist_simulation.dart';
import 'watchlist_simulation_action_store.dart';
import 'watchlist_simulation_allocation_store.dart';
import 'watchlist_simulation_observation_store.dart';

export '../domain/watchlist_simulation.dart';

const _uuid = Uuid();

/// Paper-only repository for watchlist allocation scenarios.
///
/// This repository intentionally has no dependency on the real investment
/// portfolio, lots, accounts, journal entries, or postings. Every mutation is
/// confined to the `watchlist_simulation*` row families. Definitions, target
/// weights, and paper action references use Sync v3; observations remain a
/// derived device-local read model.
class WatchlistSimulationRepository {
  WatchlistSimulationRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper;

  static const simulationsTable = 'watchlist_simulations';
  static const allocationHeadsTable = 'watchlist_simulation_allocation_heads';
  static const allocationVersionsTable =
      'watchlist_simulation_allocation_versions';
  static const holdingVersionsTable = 'watchlist_simulation_holding_versions';
  static const actionEntriesTable = WatchlistSimulationActionStore.tableName;

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
  }) => watchResolvedAllocation(
    ownerUserId: ownerUserId,
    simulationId: simulationId,
  ).map((allocation) => allocation.positions);

  late final _allocations = WatchlistSimulationAllocationStore(_db);
  late final _actions = WatchlistSimulationActionStore(
    _db,
    _outbox,
    _stamper,
    _allocations,
  );
  late final _observations = WatchlistSimulationObservationStore(
    _db,
    _allocations,
  );

  Stream<ResolvedWatchlistSimulationAllocation> watchResolvedAllocation({
    required String ownerUserId,
    required String simulationId,
  }) =>
      _allocations.watch(ownerUserId: ownerUserId, simulationId: simulationId);

  Future<ResolvedWatchlistSimulationAllocation> resolveAllocation({
    required String ownerUserId,
    required String simulationId,
  }) => _allocations.resolve(
    ownerUserId: ownerUserId,
    simulationId: simulationId,
  );

  Stream<List<WatchlistSimulationActionEntry>> watchActionEntries({
    required String ownerUserId,
    required String simulationId,
  }) => _actions.watchActionEntries(
    ownerUserId: ownerUserId,
    simulationId: simulationId,
  );

  Future<List<WatchlistSimulationActionTarget>> listActionTargets({
    required String ownerUserId,
    required String simulationId,
  }) => _actions.listActionTargets(
    ownerUserId: ownerUserId,
    simulationId: simulationId,
  );

  Future<List<WatchlistSimulationActionEntry>> advanceDividendLifecycle({
    required WatchlistSimulation simulation,
    required DateTime asOf,
  }) => _actions.advanceDividendLifecycle(simulation: simulation, asOf: asOf);

  Future<List<WatchlistSimulationActionEntry>> materializeDividendReferences({
    required WatchlistSimulation simulation,
    required Map<String, Iterable<MarketCorporateAction>>
    actionsByWatchlistItemId,
    Set<String> trustedAdjustmentCoverageItemIds = const {},
    DateTime? lifecycleAsOf,
  }) => _actions.materializeDividendReferences(
    simulation: simulation,
    actionsByWatchlistItemId: actionsByWatchlistItemId,
    trustedAdjustmentCoverageItemIds: trustedAdjustmentCoverageItemIds,
    lifecycleAsOf: lifecycleAsOf,
  );

  Stream<List<WatchlistSimulationObservation>> watchObservations({
    required String ownerUserId,
    required String simulationId,
  }) => _observations.watchObservations(
    ownerUserId: ownerUserId,
    simulationId: simulationId,
  );

  Future<WatchlistSimulationObservation?> recordObservation({
    required WatchlistSimulation simulation,
    required DateTime observedAt,
    required Decimal weightedDailyChange,
    required Decimal pricedWeight,
    required Decimal missingQuoteWeight,
    required String allocationBasisKey,
  }) => _observations.recordObservation(
    simulation: simulation,
    observedAt: observedAt,
    weightedDailyChange: weightedDailyChange,
    pricedWeight: pricedWeight,
    missingQuoteWeight: missingQuoteWeight,
    allocationBasisKey: allocationBasisKey,
  );

  Future<int> mergeObservationInputs({
    required WatchlistSimulation simulation,
    required Iterable<WatchlistSimulationObservationInput> inputs,
    required String allocationBasisKey,
    bool repairIncompleteObservations = false,
  }) => _observations.mergeObservationInputs(
    simulation: simulation,
    inputs: inputs,
    allocationBasisKey: allocationBasisKey,
    repairIncompleteObservations: repairIncompleteObservations,
  );

  Future<WatchlistSimulation> create({
    required String collectionId,
    required String name,
    required String baseCurrency,
    required Decimal startingCapital,
    required Map<String, Decimal> targetWeights,
    required Decimal cashWeight,
    Map<String, WatchlistSimulationHoldingInput>? holdingInputs,
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
              baselineAt: simulation.baselineAt,
              createdAt: simulation.createdAt,
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
          );
      await _outbox.enqueue(table: simulationsTable, rowId: simulation.id);
      final allocationVersionId = await _writeAllocationVersion(
        simulation: simulation,
        targetWeights: targetWeights,
        cashWeight: cashWeight,
        holdingInputs: holdingInputs ?? const {},
        reason: WatchlistSimulationAllocationReason.creation,
        capitalBase: startingCapital,
        previousAllocationVersionId: null,
        stamp: stamp,
      );
      await _writeAllocationHead(
        simulationId: simulation.id,
        allocationVersionId: allocationVersionId,
        stamp: stamp,
      );
      await _observations.ensureBaseline(
        ownerUserId: stamp.ownerUserId,
        simulationId: simulation.id,
      );
    });
    return simulation;
  }

  /// Saves the editable definition and allocation as one local transaction.
  /// A stale editor must reopen rather than overwrite a newly selected head.
  Future<void> saveConfiguration({
    required WatchlistSimulation simulation,
    required String name,
    required Map<String, Decimal> targetWeights,
    required Decimal cashWeight,
    String? expectedAllocationBasisKey,
    Map<String, WatchlistSimulationHoldingInput>? holdingInputs,
  }) async {
    _requireName(name);
    _validateAllocation(targetWeights, cashWeight);
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.watchlistSimulations)..where(
                (t) =>
                    t.id.equals(simulation.id) &
                    t.ownerUserId.equals(simulation.sync.ownerUserId) &
                    t.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (row == null || row.hlc != simulation.sync.hlc) {
        throw const WatchlistSimulationSaveException(
          WatchlistSimulationSaveFailure.changed,
        );
      }
      final allocation = await resolveAllocation(
        ownerUserId: row.ownerUserId,
        simulationId: row.id,
      );
      if (allocation.status == WatchlistSimulationAllocationStatus.pending) {
        throw const WatchlistSimulationSaveException(
          WatchlistSimulationSaveFailure.syncing,
        );
      }
      if (expectedAllocationBasisKey != null &&
          allocation.allocationBasisKey != expectedAllocationBasisKey) {
        throw const WatchlistSimulationSaveException(
          WatchlistSimulationSaveFailure.changed,
        );
      }
      final updated = await updateDefinition(
        simulation: _simulationFromRow(row),
        name: name,
        startingCapital: row.startingCapital,
      );
      await replaceAllocation(
        simulation: updated,
        targetWeights: targetWeights,
        cashWeight: cashWeight,
        holdingInputs: holdingInputs,
      );
    });
  }

  /// Renames a simulation without changing its historical capital baseline.
  /// A different capital amount requires a new simulation and baseline.
  Future<WatchlistSimulation> updateDefinition({
    required WatchlistSimulation simulation,
    required String name,
    required Decimal startingCapital,
  }) async {
    final normalizedName = _requireName(name);
    if (startingCapital <= Decimal.zero ||
        startingCapital != simulation.startingCapital) {
      throw ArgumentError.value(startingCapital, 'startingCapital');
    }
    if (normalizedName == simulation.name &&
        startingCapital == simulation.startingCapital) {
      return simulation;
    }
    final stamp = await _stamper.stamp();
    final updated = WatchlistSimulation(
      id: simulation.id,
      collectionId: simulation.collectionId,
      name: normalizedName,
      baseCurrency: simulation.baseCurrency,
      startingCapital: startingCapital,
      baselineAt: simulation.baselineAt,
      createdAt: simulation.createdAt,
      sync: _syncFromStamp(stamp),
    );
    await _db.transaction(() async {
      final current =
          await (_db.select(_db.watchlistSimulations)..where(
                (t) =>
                    t.id.equals(simulation.id) &
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (current == null || current.startingCapital != startingCapital) {
        throw const WatchlistSimulationSaveException(
          WatchlistSimulationSaveFailure.changed,
        );
      }
      final changed =
          await (_db.update(_db.watchlistSimulations)..where(
                (t) =>
                    t.id.equals(simulation.id) &
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.deletedAt.isNull(),
              ))
              .write(
                WatchlistSimulationsCompanion(
                  name: Value(normalizedName),
                  startingCapital: Value(startingCapital),
                  updatedAt: Value(stamp.now),
                  updatedByDevice: Value(stamp.deviceId),
                  hlc: Value(stamp.hlc),
                ),
              );
      if (changed == 0) {
        throw StateError('Watchlist simulation is not active.');
      }
      await _outbox.enqueue(table: simulationsTable, rowId: simulation.id);
    });
    return updated;
  }

  Future<void> replaceAllocation({
    required WatchlistSimulation simulation,
    required Map<String, Decimal> targetWeights,
    required Decimal cashWeight,
    Map<String, WatchlistSimulationHoldingInput>? holdingInputs,
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
      final resolved = await resolveAllocation(
        ownerUserId: stamp.ownerUserId,
        simulationId: simulation.id,
      );
      if (!resolved.isUsable) {
        throw StateError('Watchlist simulation allocation is not usable.');
      }
      final currentWeights = <String, Decimal>{
        for (final position in resolved.positions)
          position.watchlistItemId: position.targetWeight,
      };
      if (resolved.cashWeight == cashWeight &&
          _decimalMapsEqual(currentWeights, targetWeights)) {
        return;
      }
      final previousAllocationVersionId = resolved.allocationVersionId;
      final allocationVersionId = await _writeAllocationVersion(
        simulation: simulation,
        targetWeights: targetWeights,
        cashWeight: cashWeight,
        holdingInputs: holdingInputs ?? const {},
        reason: WatchlistSimulationAllocationReason.reallocation,
        capitalBase: null,
        previousAllocationVersionId: previousAllocationVersionId,
        stamp: stamp,
      );
      await _writeAllocationHead(
        simulationId: simulation.id,
        allocationVersionId: allocationVersionId,
        stamp: stamp,
      );
    });
  }

  /// Tombstones the scenario so the delete can be undone by [restore].
  ///
  /// Every syncable child row is soft-deleted with the same stamp; the
  /// device-local observation rows are left untouched so an undo brings the
  /// whole observed curve back instead of restarting it at the baseline.
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

      final allocationHead =
          await (_db.select(_db.watchlistSimulationAllocationHeads)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.id.equals(simulation.id) &
                    t.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (allocationHead != null) {
        await (_db.update(
          _db.watchlistSimulationAllocationHeads,
        )..where((t) => t.id.equals(simulation.id))).write(
          WatchlistSimulationAllocationHeadsCompanion(
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
            deletedAt: Value(stamp.now),
          ),
        );
        await _outbox.enqueue(
          table: allocationHeadsTable,
          rowId: simulation.id,
        );
      }

      final activeAllocationVersions =
          await (_db.select(_db.watchlistSimulationAllocationVersions)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.simulationId.equals(simulation.id) &
                    t.deletedAt.isNull(),
              ))
              .get();
      for (final row in activeAllocationVersions) {
        await (_db.update(
          _db.watchlistSimulationAllocationVersions,
        )..where((t) => t.id.equals(row.id))).write(
          WatchlistSimulationAllocationVersionsCompanion(
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
            deletedAt: Value(stamp.now),
          ),
        );
        await _outbox.enqueue(table: allocationVersionsTable, rowId: row.id);
      }
      final activeHoldingVersions =
          await (_db.select(_db.watchlistSimulationHoldingVersions)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.simulationId.equals(simulation.id) &
                    t.deletedAt.isNull(),
              ))
              .get();
      for (final row in activeHoldingVersions) {
        await (_db.update(
          _db.watchlistSimulationHoldingVersions,
        )..where((t) => t.id.equals(row.id))).write(
          WatchlistSimulationHoldingVersionsCompanion(
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
            deletedAt: Value(stamp.now),
          ),
        );
        await _outbox.enqueue(table: holdingVersionsTable, rowId: row.id);
      }
      final activeActionEntries =
          await (_db.select(_db.watchlistSimulationActionEntries)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.simulationId.equals(simulation.id) &
                    t.deletedAt.isNull(),
              ))
              .get();
      for (final row in activeActionEntries) {
        await (_db.update(
          _db.watchlistSimulationActionEntries,
        )..where((t) => t.id.equals(row.id))).write(
          WatchlistSimulationActionEntriesCompanion(
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
            deletedAt: Value(stamp.now),
          ),
        );
        await _outbox.enqueue(table: actionEntriesTable, rowId: row.id);
      }
      // Observation rows are deliberately kept: they carry no SyncMeta and
      // are hidden while the definition is tombstoned, so keeping them lets
      // [restore] bring back the whole observed curve instead of resetting a
      // months-long series to the baseline.
    });
  }

  /// Reverts [delete] for a simulation that is still tombstoned.
  ///
  /// Only rows tombstoned by the same delete stamp are revived; previously
  /// removed children stay removed and the restored head selects its snapshot.
  Future<void> restore(WatchlistSimulation simulation) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.watchlistSimulations)..where(
                (t) =>
                    t.id.equals(simulation.id) &
                    t.ownerUserId.equals(stamp.ownerUserId),
              ))
              .getSingleOrNull();
      final deletedAt = row?.deletedAt;
      if (row == null || deletedAt == null) return;

      await (_db.update(_db.watchlistSimulations)..where(
            (t) =>
                t.id.equals(simulation.id) &
                t.ownerUserId.equals(stamp.ownerUserId),
          ))
          .write(
            WatchlistSimulationsCompanion(
              updatedAt: Value(stamp.now),
              updatedByDevice: Value(stamp.deviceId),
              hlc: Value(stamp.hlc),
              deletedAt: const Value(null),
            ),
          );
      await _outbox.enqueue(table: simulationsTable, rowId: simulation.id);

      final heads =
          await (_db.select(_db.watchlistSimulationAllocationHeads)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.simulationId.equals(simulation.id) &
                    t.deletedAt.equals(deletedAt),
              ))
              .get();
      for (final head in heads) {
        await (_db.update(
          _db.watchlistSimulationAllocationHeads,
        )..where((t) => t.id.equals(head.id))).write(
          WatchlistSimulationAllocationHeadsCompanion(
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
            deletedAt: const Value(null),
          ),
        );
        await _outbox.enqueue(table: allocationHeadsTable, rowId: head.id);
      }

      final allocationVersions =
          await (_db.select(_db.watchlistSimulationAllocationVersions)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.simulationId.equals(simulation.id) &
                    t.deletedAt.equals(deletedAt),
              ))
              .get();
      for (final version in allocationVersions) {
        await (_db.update(
          _db.watchlistSimulationAllocationVersions,
        )..where((t) => t.id.equals(version.id))).write(
          WatchlistSimulationAllocationVersionsCompanion(
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
            deletedAt: const Value(null),
          ),
        );
        await _outbox.enqueue(
          table: allocationVersionsTable,
          rowId: version.id,
        );
      }

      final holdingVersions =
          await (_db.select(_db.watchlistSimulationHoldingVersions)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.simulationId.equals(simulation.id) &
                    t.deletedAt.equals(deletedAt),
              ))
              .get();
      for (final version in holdingVersions) {
        await (_db.update(
          _db.watchlistSimulationHoldingVersions,
        )..where((t) => t.id.equals(version.id))).write(
          WatchlistSimulationHoldingVersionsCompanion(
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
            deletedAt: const Value(null),
          ),
        );
        await _outbox.enqueue(table: holdingVersionsTable, rowId: version.id);
      }

      final actionEntries =
          await (_db.select(_db.watchlistSimulationActionEntries)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.simulationId.equals(simulation.id) &
                    t.deletedAt.equals(deletedAt),
              ))
              .get();
      for (final entry in actionEntries) {
        await (_db.update(
          _db.watchlistSimulationActionEntries,
        )..where((t) => t.id.equals(entry.id))).write(
          WatchlistSimulationActionEntriesCompanion(
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
            deletedAt: const Value(null),
          ),
        );
        await _outbox.enqueue(table: actionEntriesTable, rowId: entry.id);
      }
    });
  }

  Future<String> _writeAllocationVersion({
    required WatchlistSimulation simulation,
    required Map<String, Decimal> targetWeights,
    required Decimal cashWeight,
    required Map<String, WatchlistSimulationHoldingInput> holdingInputs,
    required WatchlistSimulationAllocationReason reason,
    required Decimal? capitalBase,
    required String? previousAllocationVersionId,
    required MutationStamp stamp,
  }) async {
    final versionId = _uuid.v4();
    var effectiveAt = stamp.now.toUtc();
    final latestVersionQuery =
        _db.select(_db.watchlistSimulationAllocationVersions)
          ..where((t) => t.ownerUserId.equals(stamp.ownerUserId))
          ..where((t) => t.simulationId.equals(simulation.id))
          ..orderBy([(t) => OrderingTerm.desc(t.effectiveAt)])
          ..limit(1);
    final latestVersion = await latestVersionQuery.getSingleOrNull();
    if (latestVersion != null &&
        effectiveAt.millisecondsSinceEpoch ~/ 1000 <=
            latestVersion.effectiveAt.toUtc().millisecondsSinceEpoch ~/ 1000) {
      effectiveAt = latestVersion.effectiveAt.toUtc().add(
        const Duration(seconds: 1),
      );
    }
    final resolved = <String, _ResolvedHoldingVersion>{};
    for (final entry in targetWeights.entries) {
      final input = holdingInputs[entry.key];
      final price = input?.rawPrice;
      final priceCurrency = input?.priceCurrency?.trim().toUpperCase();
      final sameCurrency =
          priceCurrency != null && priceCurrency == simulation.baseCurrency;
      final inputSymbol = input?.symbol.trim().toUpperCase();
      final inputSource = input?.priceSource?.trim();
      final priceAsOf = input?.priceAsOf?.toUtc();
      final evidenceIdentity = input == null
          ? null
          : '${input.market.wire}:$inputSymbol';
      final hasTrustedEvidence =
          input != null &&
          evidenceIdentity == entry.key &&
          inputSymbol != null &&
          inputSymbol.isNotEmpty &&
          inputSource != null &&
          inputSource.isNotEmpty &&
          priceAsOf != null &&
          !priceAsOf.isAfter(stamp.now.toUtc()) &&
          input.quantityEligible;
      Decimal? quantity;
      if (capitalBase != null &&
          hasTrustedEvidence &&
          price != null &&
          price > Decimal.zero &&
          sameCurrency) {
        quantity = ((capitalBase * entry.value) / price).toDecimal(
          scaleOnInfinitePrecision: 12,
        );
      }
      final separator = entry.key.indexOf(':');
      resolved[entry.key] = _ResolvedHoldingVersion(
        symbol:
            input?.symbol.toUpperCase() ??
            (separator < 0
                ? entry.key.toUpperCase()
                : entry.key.substring(separator + 1).toUpperCase()),
        market:
            input?.market.wire ??
            (separator < 0
                ? AssetMarket.unknown.wire
                : entry.key.substring(0, separator)),
        targetWeight: entry.value,
        quantity: quantity,
        rawPrice: price,
        priceCurrency: priceCurrency,
        priceAsOf: priceAsOf,
        priceSource: inputSource,
        fxToBase:
            hasTrustedEvidence &&
                price != null &&
                price > Decimal.zero &&
                sameCurrency
            ? Decimal.one
            : null,
      );
    }
    await _db
        .into(_db.watchlistSimulationAllocationVersions)
        .insert(
          WatchlistSimulationAllocationVersionsCompanion.insert(
            id: versionId,
            simulationId: simulation.id,
            effectiveAt: effectiveAt,
            reason: reason.name,
            previousAllocationVersionId: Value(previousAllocationVersionId),
            cashWeight: cashWeight,
            createdAt: stamp.now,
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        );
    await _outbox.enqueue(table: allocationVersionsTable, rowId: versionId);
    for (final entry in resolved.entries) {
      final id = _holdingVersionId(
        allocationVersionId: versionId,
        watchlistItemId: entry.key,
      );
      final holding = entry.value;
      await _db
          .into(_db.watchlistSimulationHoldingVersions)
          .insert(
            WatchlistSimulationHoldingVersionsCompanion.insert(
              id: id,
              allocationVersionId: versionId,
              simulationId: simulation.id,
              watchlistItemId: entry.key,
              symbol: holding.symbol,
              market: holding.market,
              targetWeight: holding.targetWeight,
              quantity: Value(holding.quantity),
              rawPrice: Value(holding.rawPrice),
              priceCurrency: Value(holding.priceCurrency),
              priceAsOf: Value(holding.priceAsOf),
              priceSource: Value(holding.priceSource),
              fxToBase: Value(holding.fxToBase),
              effectiveAt: effectiveAt,
              createdAt: stamp.now,
              ownerUserId: stamp.ownerUserId,
              updatedAt: stamp.now,
              updatedByDevice: stamp.deviceId,
              hlc: stamp.hlc,
            ),
          );
      await _outbox.enqueue(table: holdingVersionsTable, rowId: id);
    }
    return versionId;
  }

  Future<void> _writeAllocationHead({
    required String simulationId,
    required String allocationVersionId,
    required MutationStamp stamp,
  }) async {
    final existing =
        await (_db.select(_db.watchlistSimulationAllocationHeads)..where(
              (t) =>
                  t.ownerUserId.equals(stamp.ownerUserId) &
                  t.id.equals(simulationId),
            ))
            .getSingleOrNull();
    await _db
        .into(_db.watchlistSimulationAllocationHeads)
        .insertOnConflictUpdate(
          WatchlistSimulationAllocationHeadsCompanion.insert(
            id: simulationId,
            simulationId: simulationId,
            allocationVersionId: allocationVersionId,
            createdAt: existing?.createdAt ?? stamp.now,
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
            deletedAt: const Value(null),
          ),
        );
    await _outbox.enqueue(table: allocationHeadsTable, rowId: simulationId);
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

  static String _holdingVersionId({
    required String allocationVersionId,
    required String watchlistItemId,
  }) {
    final digest = sha256.convert(
      utf8.encode('$allocationVersionId\u0000$watchlistItemId'),
    );
    return 'watchlist-simulation-holding:$digest';
  }
}

class _ResolvedHoldingVersion {
  const _ResolvedHoldingVersion({
    required this.symbol,
    required this.market,
    required this.targetWeight,
    required this.quantity,
    required this.rawPrice,
    required this.priceCurrency,
    required this.priceAsOf,
    required this.priceSource,
    required this.fxToBase,
  });

  final String symbol;
  final String market;
  final Decimal targetWeight;
  final Decimal? quantity;
  final Decimal? rawPrice;
  final String? priceCurrency;
  final DateTime? priceAsOf;
  final String? priceSource;
  final Decimal? fxToBase;
}

WatchlistSimulation _simulationFromRow(WatchlistSimulationRow row) {
  return WatchlistSimulation(
    id: row.id,
    collectionId: row.collectionId,
    name: row.name,
    baseCurrency: row.baseCurrency,
    startingCapital: row.startingCapital,
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

bool _decimalMapsEqual(Map<String, Decimal> left, Map<String, Decimal> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

SyncMeta _syncFromStamp(MutationStamp stamp) => SyncMeta(
  ownerUserId: stamp.ownerUserId,
  updatedAt: stamp.now,
  updatedByDevice: stamp.deviceId,
  hlc: stamp.hlc,
);
