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

const _uuid = Uuid();

enum WatchlistSimulationCalculationMode {
  weightedDailyChangeV1,
  holdingsTotalReturnV2,
}

enum WatchlistSimulationAllocationReason { creation, reallocation }

class WatchlistSimulationHoldingInput {
  const WatchlistSimulationHoldingInput({
    required this.symbol,
    required this.market,
    this.rawPrice,
    this.priceCurrency,
    this.priceAsOf,
    this.priceSource,
    this.quantityEligible = true,
  });

  final String symbol;
  final AssetMarket market;
  final Decimal? rawPrice;
  final String? priceCurrency;
  final DateTime? priceAsOf;
  final String? priceSource;

  /// False when quote evidence is stale or otherwise unsuitable for creating
  /// a baseline quantity. Price provenance is still persisted for review.
  final bool quantityEligible;
}

class WatchlistSimulation {
  const WatchlistSimulation({
    required this.id,
    required this.collectionId,
    required this.name,
    required this.baseCurrency,
    required this.startingCapital,
    required this.cashWeight,
    this.calculationMode =
        WatchlistSimulationCalculationMode.weightedDailyChangeV1,
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
  final WatchlistSimulationCalculationMode calculationMode;
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

enum WatchlistSimulationPaperActionState {
  referenceOnly,
  entitlementRecorded,
  receivableGross,
  grossCashPendingTax,
  cancelled,
}

class WatchlistSimulationActionTarget {
  const WatchlistSimulationActionTarget({
    required this.watchlistItemId,
    required this.symbol,
    required this.market,
  });

  final String watchlistItemId;
  final String symbol;
  final AssetMarket market;
}

class WatchlistSimulationActionEntry {
  const WatchlistSimulationActionEntry({
    required this.id,
    required this.simulationId,
    required this.watchlistItemId,
    required this.symbol,
    required this.market,
    required this.source,
    required this.dataset,
    required this.sourceKey,
    required this.revisionHash,
    required this.kind,
    required this.status,
    required this.paperState,
    required this.recordDate,
    required this.exDate,
    required this.payDate,
    required this.currency,
    required this.cashPerShare,
    required this.eligibleQuantity,
    required this.grossAmount,
    this.receivableGrossAmount,
    this.paperCashGrossAmount,
    this.stateAt,
    required this.withholdingTaxAmount,
    required this.netAmount,
    required this.baseCurrencyAmount,
    required this.createdAt,
    required this.sync,
  });

  final String id;
  final String simulationId;
  final String watchlistItemId;
  final String symbol;
  final String market;
  final String source;
  final String dataset;
  final String sourceKey;
  final String revisionHash;
  final MarketCorporateActionKind kind;
  final MarketCorporateActionStatus status;
  final WatchlistSimulationPaperActionState paperState;
  final DateTime? recordDate;
  final DateTime? exDate;
  final DateTime? payDate;
  final String currency;
  final Decimal cashPerShare;
  final Decimal? eligibleQuantity;
  final Decimal? grossAmount;
  final Decimal? receivableGrossAmount;
  final Decimal? paperCashGrossAmount;
  final DateTime? stateAt;
  final Decimal? withholdingTaxAmount;
  final Decimal? netAmount;
  final Decimal? baseCurrencyAmount;
  final DateTime createdAt;
  final SyncMeta sync;

  bool get isReferenceOnly =>
      paperState == WatchlistSimulationPaperActionState.referenceOnly &&
      eligibleQuantity == null &&
      grossAmount == null &&
      receivableGrossAmount == null &&
      paperCashGrossAmount == null &&
      withholdingTaxAmount == null &&
      netAmount == null &&
      baseCurrencyAmount == null;
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
  static const positionsTable = 'watchlist_simulation_positions';
  static const allocationVersionsTable =
      'watchlist_simulation_allocation_versions';
  static const holdingVersionsTable = 'watchlist_simulation_holding_versions';
  static const actionEntriesTable = 'watchlist_simulation_action_entries';

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

  Stream<List<WatchlistSimulationActionEntry>> watchActionEntries({
    required String ownerUserId,
    required String simulationId,
  }) {
    final query = _db.select(_db.watchlistSimulationActionEntries)
      ..where((t) => t.ownerUserId.equals(ownerUserId))
      ..where((t) => t.simulationId.equals(simulationId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_actionEntryFromRow).toList(growable: false),
    );
  }

  Future<List<WatchlistSimulationActionTarget>> listActionTargets({
    required String ownerUserId,
    required String simulationId,
  }) async {
    final targets = <String, WatchlistSimulationActionTarget>{};
    final holdings =
        await (_db.select(_db.watchlistSimulationHoldingVersions)..where(
              (t) =>
                  t.ownerUserId.equals(ownerUserId) &
                  t.simulationId.equals(simulationId) &
                  t.deletedAt.isNull(),
            ))
            .get();
    for (final row in holdings) {
      final market = assetMarketFromWire(row.market);
      if (market == null) continue;
      targets[row.watchlistItemId] = WatchlistSimulationActionTarget(
        watchlistItemId: row.watchlistItemId,
        symbol: row.symbol,
        market: market,
      );
    }
    final actions =
        await (_db.select(_db.watchlistSimulationActionEntries)..where(
              (t) =>
                  t.ownerUserId.equals(ownerUserId) &
                  t.simulationId.equals(simulationId) &
                  t.deletedAt.isNull(),
            ))
            .get();
    for (final row in actions) {
      final market = assetMarketFromWire(row.market);
      if (market == null) continue;
      targets.putIfAbsent(
        row.watchlistItemId,
        () => WatchlistSimulationActionTarget(
          watchlistItemId: row.watchlistItemId,
          symbol: row.symbol,
          market: market,
        ),
      );
    }
    return List<WatchlistSimulationActionTarget>.unmodifiable(targets.values);
  }

  Stream<List<WatchlistSimulationObservation>> watchObservations({
    required String ownerUserId,
    required String simulationId,
  }) async* {
    final active = await _ensureObservationBaseline(
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
      cashWeight: cashWeight,
      calculationMode: holdingInputs == null
          ? WatchlistSimulationCalculationMode.weightedDailyChangeV1
          : WatchlistSimulationCalculationMode.holdingsTotalReturnV2,
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
              calculationMode: Value(simulation.calculationMode.name),
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
      if (holdingInputs != null) {
        await _writeAllocationVersion(
          simulation: simulation,
          targetWeights: targetWeights,
          cashWeight: cashWeight,
          holdingInputs: holdingInputs,
          reason: WatchlistSimulationAllocationReason.creation,
          capitalBase: startingCapital,
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
    await _ensureObservationBaseline(
      ownerUserId: ownerUserId,
      simulationId: simulation.id,
    );
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

  /// Advances already trusted paper dividend rows from entitlement to gross
  /// receivable and then to gross paper cash using only persisted dates.
  ///
  /// This reducer is intentionally provider-independent and monotonic. Once a
  /// trusted amount reaches a later lifecycle state, offline refreshes or a
  /// device with an earlier clock cannot move it backward.
  Future<List<WatchlistSimulationActionEntry>> advanceDividendLifecycle({
    required WatchlistSimulation simulation,
    required DateTime asOf,
  }) async {
    final stamp = await _stamper.stamp();
    final effectiveAsOf = asOf.toUtc();
    final changedIds = <String>[];
    await _db.transaction(() async {
      final rows =
          await (_db.select(_db.watchlistSimulationActionEntries)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.simulationId.equals(simulation.id) &
                    t.deletedAt.isNull(),
              ))
              .get();
      for (final row in rows) {
        if (row.status == MarketCorporateActionStatus.cancelled.name ||
            row.grossAmount == null ||
            !_isTrustedEntitlementState(row.paperState)) {
          continue;
        }
        final current = _enumByName(
          WatchlistSimulationPaperActionState.values,
          row.paperState,
        );
        final target = _paperLifecycleAt(
          current: current,
          exDate: row.exDate,
          payDate: row.payDate,
          asOf: effectiveAsOf,
        );
        if (_paperStateRank(target) <= _paperStateRank(current)) continue;
        await (_db.update(
          _db.watchlistSimulationActionEntries,
        )..where((t) => t.id.equals(row.id))).write(
          WatchlistSimulationActionEntriesCompanion(
            paperState: Value(target.name),
            receivableGrossAmount: Value(
              target == WatchlistSimulationPaperActionState.receivableGross
                  ? row.grossAmount
                  : null,
            ),
            paperCashGrossAmount: Value(
              target == WatchlistSimulationPaperActionState.grossCashPendingTax
                  ? row.grossAmount
                  : null,
            ),
            stateAt: Value(
              target == WatchlistSimulationPaperActionState.grossCashPendingTax
                  ? row.payDate?.toUtc()
                  : row.exDate?.toUtc(),
            ),
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
          ),
        );
        await _outbox.enqueue(table: actionEntriesTable, rowId: row.id);
        changedIds.add(row.id);
      }
    });
    if (changedIds.isEmpty) return const [];
    final rows = await (_db.select(
      _db.watchlistSimulationActionEntries,
    )..where((t) => t.id.isIn(changedIds))).get();
    return List<WatchlistSimulationActionEntry>.unmodifiable(
      rows.map(_actionEntryFromRow),
    );
  }

  /// Materializes implemented dividend terms as synced paper references.
  ///
  /// New rows require an implemented action whose best entitlement date is on
  /// or after the simulation baseline. Existing deterministic rows may be
  /// revised or cancelled. Holdings V2 may attach record-date virtual quantity
  /// and gross paper entitlement; tax, net cash, base value, and NAV remain
  /// unapplied. Legacy weight-only simulations stay reference-only.
  Future<List<WatchlistSimulationActionEntry>> materializeDividendReferences({
    required WatchlistSimulation simulation,
    required Map<String, Iterable<MarketCorporateAction>>
    actionsByWatchlistItemId,
    Set<String> trustedAdjustmentCoverageItemIds = const <String>{},
    DateTime? lifecycleAsOf,
  }) async {
    if (actionsByWatchlistItemId.isEmpty) return const [];
    final stamp = await _stamper.stamp();
    final asOf = (lifecycleAsOf ?? stamp.now).toUtc();
    final materialized = <WatchlistSimulationActionEntry>[];
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
      final activePositions =
          await (_db.select(_db.watchlistSimulationPositions)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.simulationId.equals(simulation.id) &
                    t.deletedAt.isNull(),
              ))
              .get();
      final eligibleItemIds = activePositions
          .map((row) => row.watchlistItemId)
          .toSet();
      if (activeSimulation.calculationMode ==
          WatchlistSimulationCalculationMode.holdingsTotalReturnV2.name) {
        final historicalHoldings =
            await (_db.select(_db.watchlistSimulationHoldingVersions)..where(
                  (t) =>
                      t.ownerUserId.equals(stamp.ownerUserId) &
                      t.simulationId.equals(simulation.id) &
                      t.deletedAt.isNull(),
                ))
                .get();
        eligibleItemIds.addAll(
          historicalHoldings.map((row) => row.watchlistItemId),
        );
      }
      final existingActionRows =
          await (_db.select(_db.watchlistSimulationActionEntries)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.simulationId.equals(simulation.id) &
                    t.deletedAt.isNull(),
              ))
              .get();
      eligibleItemIds.addAll(
        existingActionRows.map((row) => row.watchlistItemId),
      );

      for (final entry in actionsByWatchlistItemId.entries) {
        if (!eligibleItemIds.contains(entry.key)) continue;
        final itemActions = entry.value.toList(growable: false);
        final hasTrustedAdjustmentCoverage = trustedAdjustmentCoverageItemIds
            .contains(entry.key);
        for (final action in itemActions) {
          final expectedItemId =
              '${action.market.wire}:${action.symbol.toUpperCase()}';
          if (entry.key != expectedItemId ||
              action.kind != MarketCorporateActionKind.distribution ||
              !action.hasCashDistribution ||
              action.currency == null) {
            continue;
          }
          final id = _actionEntryId(
            simulationId: simulation.id,
            action: action,
          );
          final existing =
              await (_db.select(_db.watchlistSimulationActionEntries)..where(
                    (t) =>
                        t.id.equals(id) &
                        t.ownerUserId.equals(stamp.ownerUserId),
                  ))
                  .getSingleOrNull();
          if (existing == null) {
            final entitlementDate =
                action.recordDate ?? action.exDate ?? action.payDate;
            if (action.status != MarketCorporateActionStatus.implemented ||
                entitlementDate == null ||
                entitlementDate.isBefore(activeSimulation.baselineAt)) {
              continue;
            }
          }
          var paperState = WatchlistSimulationPaperActionState.referenceOnly;
          Decimal? eligibleQuantity;
          Decimal? grossAmount;
          Decimal? receivableGrossAmount;
          Decimal? paperCashGrossAmount;
          DateTime? stateAt;
          if (action.status == MarketCorporateActionStatus.cancelled) {
            paperState = WatchlistSimulationPaperActionState.cancelled;
            stateAt = action.timelineDate?.toUtc();
          } else if (_isTrustedEntitlementState(existing?.paperState) &&
              action.status != MarketCorporateActionStatus.implemented) {
            // A non-final provider revision cannot erase a trusted entitlement.
            // Cancellation is the only non-implemented terminal transition.
            continue;
          } else if (!hasTrustedAdjustmentCoverage &&
              _isTrustedEntitlementState(existing?.paperState)) {
            // A partial/stale fetch must not downgrade or revise a previously
            // trusted entitlement with an incomplete adjustment history.
            continue;
          } else if (hasTrustedAdjustmentCoverage &&
              activeSimulation.calculationMode ==
                  WatchlistSimulationCalculationMode
                      .holdingsTotalReturnV2
                      .name &&
              action.recordDate != null) {
            final allocationQuery =
                _db.select(_db.watchlistSimulationAllocationVersions)
                  ..where((t) => t.ownerUserId.equals(stamp.ownerUserId))
                  ..where((t) => t.simulationId.equals(simulation.id))
                  ..where(
                    (t) => t.effectiveAt.isSmallerOrEqualValue(
                      action.recordDate!.toUtc(),
                    ),
                  )
                  ..where((t) => t.deletedAt.isNull())
                  ..orderBy([(t) => OrderingTerm.desc(t.effectiveAt)])
                  ..limit(1);
            final allocation = await allocationQuery.getSingleOrNull();
            final holding = allocation == null
                ? null
                : await (_db.select(_db.watchlistSimulationHoldingVersions)
                        ..where(
                          (t) =>
                              t.ownerUserId.equals(stamp.ownerUserId) &
                              t.allocationVersionId.equals(allocation.id) &
                              t.watchlistItemId.equals(entry.key) &
                              t.deletedAt.isNull(),
                        ))
                      .getSingleOrNull();
            eligibleQuantity = holding?.quantity;
            if (eligibleQuantity != null && holding != null) {
              for (final adjustment in itemActions) {
                final decision = _quantityAdjustmentDecision(
                  adjustment,
                  after: holding.effectiveAt.toUtc(),
                  before: action.recordDate!.toUtc(),
                );
                if (decision.blocksEntitlement) {
                  eligibleQuantity = null;
                  break;
                }
                final multiplier = decision.multiplier;
                if (multiplier != null) {
                  eligibleQuantity = (eligibleQuantity! * multiplier).round(
                    scale: 12,
                  );
                }
              }
              if (eligibleQuantity != null) {
                grossAmount = (eligibleQuantity * action.cashPerShare!).round(
                  scale: 12,
                );
                paperState =
                    WatchlistSimulationPaperActionState.entitlementRecorded;
                stateAt = action.recordDate?.toUtc();
                final exDate = action.exDate?.toUtc();
                final payDate = action.payDate?.toUtc();
                if (exDate != null && !asOf.isBefore(exDate)) {
                  paperState =
                      WatchlistSimulationPaperActionState.receivableGross;
                  receivableGrossAmount = grossAmount;
                  stateAt = exDate;
                }
                if (payDate != null && !asOf.isBefore(payDate)) {
                  paperState =
                      WatchlistSimulationPaperActionState.grossCashPendingTax;
                  receivableGrossAmount = null;
                  paperCashGrossAmount = grossAmount;
                  stateAt = payDate;
                }
              }
            }
          }
          if (_isTrustedEntitlementState(existing?.paperState)) {
            if (!_isTrustedEntitlementState(paperState.name)) {
              // Complete refreshes may correct terms, but missing evidence must
              // not erase a quantity that was established from trusted history.
              continue;
            }
            final currentState = _enumByName(
              WatchlistSimulationPaperActionState.values,
              existing!.paperState,
            );
            if (_paperStateRank(currentState) > _paperStateRank(paperState)) {
              paperState = currentState;
              stateAt = existing.stateAt?.toUtc();
              receivableGrossAmount =
                  paperState ==
                      WatchlistSimulationPaperActionState.receivableGross
                  ? grossAmount
                  : null;
              paperCashGrossAmount =
                  paperState ==
                      WatchlistSimulationPaperActionState.grossCashPendingTax
                  ? grossAmount
                  : null;
            }
          }
          if (existing != null &&
              _actionEntryMatches(
                existing,
                entry.key,
                action,
                paperState: paperState,
                eligibleQuantity: eligibleQuantity,
                grossAmount: grossAmount,
                receivableGrossAmount: receivableGrossAmount,
                paperCashGrossAmount: paperCashGrossAmount,
                stateAt: stateAt,
              )) {
            continue;
          }
          final createdAt = existing?.createdAt ?? stamp.now;
          await _db
              .into(_db.watchlistSimulationActionEntries)
              .insertOnConflictUpdate(
                WatchlistSimulationActionEntriesCompanion.insert(
                  id: id,
                  simulationId: simulation.id,
                  watchlistItemId: entry.key,
                  symbol: action.symbol,
                  market: action.market.wire,
                  source: action.source,
                  dataset: action.dataset,
                  sourceKey: action.sourceKey,
                  revisionHash: action.revisionHash,
                  kind: action.kind.name,
                  status: action.status.name,
                  paperState: Value(paperState.name),
                  recordDate: Value(action.recordDate?.toUtc()),
                  exDate: Value(action.exDate?.toUtc()),
                  payDate: Value(action.payDate?.toUtc()),
                  currency: action.currency!,
                  cashPerShare: action.cashPerShare!,
                  eligibleQuantity: Value(eligibleQuantity),
                  grossAmount: Value(grossAmount),
                  receivableGrossAmount: Value(receivableGrossAmount),
                  paperCashGrossAmount: Value(paperCashGrossAmount),
                  stateAt: Value(stateAt),
                  withholdingTaxAmount: const Value(null),
                  netAmount: const Value(null),
                  baseCurrencyAmount: const Value(null),
                  createdAt: createdAt,
                  ownerUserId: stamp.ownerUserId,
                  updatedAt: stamp.now,
                  updatedByDevice: stamp.deviceId,
                  hlc: stamp.hlc,
                  deletedAt: const Value(null),
                ),
              );
          await _outbox.enqueue(table: actionEntriesTable, rowId: id);
          materialized.add(
            WatchlistSimulationActionEntry(
              id: id,
              simulationId: simulation.id,
              watchlistItemId: entry.key,
              symbol: action.symbol,
              market: action.market.wire,
              source: action.source,
              dataset: action.dataset,
              sourceKey: action.sourceKey,
              revisionHash: action.revisionHash,
              kind: action.kind,
              status: action.status,
              paperState: paperState,
              recordDate: action.recordDate?.toUtc(),
              exDate: action.exDate?.toUtc(),
              payDate: action.payDate?.toUtc(),
              currency: action.currency!,
              cashPerShare: action.cashPerShare!,
              eligibleQuantity: eligibleQuantity,
              grossAmount: grossAmount,
              receivableGrossAmount: receivableGrossAmount,
              paperCashGrossAmount: paperCashGrossAmount,
              stateAt: stateAt,
              withholdingTaxAmount: null,
              netAmount: null,
              baseCurrencyAmount: null,
              createdAt: createdAt,
              sync: _syncFromStamp(stamp),
            ),
          );
        }
      }
    });
    return List<WatchlistSimulationActionEntry>.unmodifiable(materialized);
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
      final existingRows =
          await (_db.select(_db.watchlistSimulationPositions)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.simulationId.equals(simulation.id),
              ))
              .get();
      final activeWeights = <String, Decimal>{
        for (final row in existingRows)
          if (row.deletedAt == null) row.watchlistItemId: row.targetWeight,
      };
      if (activeSimulation.cashWeight == cashWeight &&
          _decimalMapsEqual(activeWeights, targetWeights)) {
        return;
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
      if (activeSimulation.calculationMode ==
          WatchlistSimulationCalculationMode.holdingsTotalReturnV2.name) {
        await _writeAllocationVersion(
          simulation: simulation,
          targetWeights: targetWeights,
          cashWeight: cashWeight,
          holdingInputs: holdingInputs ?? const {},
          reason: WatchlistSimulationAllocationReason.reallocation,
          capitalBase: null,
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
      await (_db.delete(_db.watchlistSimulationObservations)..where(
            (t) =>
                t.ownerUserId.equals(stamp.ownerUserId) &
                t.simulationId.equals(simulation.id),
          ))
          .go();
    });
  }

  Future<bool> _ensureObservationBaseline({
    required String ownerUserId,
    required String simulationId,
  }) async {
    final simulation =
        await (_db.select(_db.watchlistSimulations)..where(
              (t) =>
                  t.ownerUserId.equals(ownerUserId) & t.id.equals(simulationId),
            ))
            .getSingleOrNull();
    if (simulation == null || simulation.deletedAt != null) return false;
    final now = DateTime.now().toUtc();
    await _db
        .into(_db.watchlistSimulationObservations)
        .insert(
          WatchlistSimulationObservationsCompanion.insert(
            id: _observationId(
              simulationId: simulationId,
              observationDay: _observationDay(simulation.baselineAt),
            ),
            ownerUserId: ownerUserId,
            simulationId: simulationId,
            observationDay: _observationDay(simulation.baselineAt),
            observedAt: simulation.baselineAt.toUtc(),
            projectedValue: simulation.startingCapital,
            weightedDailyChange: Decimal.zero,
            pricedWeight: Decimal.zero,
            missingQuoteWeight: Decimal.one - simulation.cashWeight,
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return true;
  }

  Future<void> _writeAllocationVersion({
    required WatchlistSimulation simulation,
    required Map<String, Decimal> targetWeights,
    required Decimal cashWeight,
    required Map<String, WatchlistSimulationHoldingInput> holdingInputs,
    required WatchlistSimulationAllocationReason reason,
    required Decimal? capitalBase,
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
    final isComplete =
        resolved.length == targetWeights.length &&
        resolved.values.every((holding) => holding.quantity != null);
    await _db
        .into(_db.watchlistSimulationAllocationVersions)
        .insert(
          WatchlistSimulationAllocationVersionsCompanion.insert(
            id: versionId,
            simulationId: simulation.id,
            effectiveAt: effectiveAt,
            reason: reason.name,
            cashWeight: cashWeight,
            isComplete: Value(isComplete),
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

  static String _holdingVersionId({
    required String allocationVersionId,
    required String watchlistItemId,
  }) {
    final digest = sha256.convert(
      utf8.encode('$allocationVersionId\u0000$watchlistItemId'),
    );
    return 'watchlist-simulation-holding:$digest';
  }

  static String _actionEntryId({
    required String simulationId,
    required MarketCorporateAction action,
  }) {
    final digest = sha256.convert(
      utf8.encode(
        '$simulationId\u0000${action.source}\u0000${action.dataset}'
        '\u0000${action.sourceKey}\u0000${action.kind.name}',
      ),
    );
    return 'watchlist-simulation-action:$digest';
  }

  static String _observationId({
    required String simulationId,
    required String observationDay,
  }) => 'watchlist-simulation-observation:$simulationId:$observationDay';
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
    calculationMode: _enumByName(
      WatchlistSimulationCalculationMode.values,
      row.calculationMode,
    ),
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

bool _decimalMapsEqual(Map<String, Decimal> left, Map<String, Decimal> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) return false;
  }
  return true;
}

WatchlistSimulationPaperActionState _paperLifecycleAt({
  required WatchlistSimulationPaperActionState current,
  required DateTime? exDate,
  required DateTime? payDate,
  required DateTime asOf,
}) {
  if (payDate != null && !asOf.isBefore(payDate.toUtc())) {
    return WatchlistSimulationPaperActionState.grossCashPendingTax;
  }
  if (exDate != null && !asOf.isBefore(exDate.toUtc())) {
    return WatchlistSimulationPaperActionState.receivableGross;
  }
  return current;
}

int _paperStateRank(WatchlistSimulationPaperActionState state) {
  return switch (state) {
    WatchlistSimulationPaperActionState.referenceOnly => 0,
    WatchlistSimulationPaperActionState.entitlementRecorded => 1,
    WatchlistSimulationPaperActionState.receivableGross => 2,
    WatchlistSimulationPaperActionState.grossCashPendingTax => 3,
    WatchlistSimulationPaperActionState.cancelled => 4,
  };
}

bool _isTrustedEntitlementState(String? value) {
  return value ==
          WatchlistSimulationPaperActionState.entitlementRecorded.name ||
      value == WatchlistSimulationPaperActionState.receivableGross.name ||
      value == WatchlistSimulationPaperActionState.grossCashPendingTax.name;
}

class _QuantityAdjustmentDecision {
  const _QuantityAdjustmentDecision({
    this.multiplier,
    this.blocksEntitlement = false,
  });

  final Decimal? multiplier;
  final bool blocksEntitlement;
}

_QuantityAdjustmentDecision _quantityAdjustmentDecision(
  MarketCorporateAction action, {
  required DateTime after,
  required DateTime before,
}) {
  final isSplit =
      action.kind == MarketCorporateActionKind.split && action.hasSplit;
  final isStockDistribution =
      action.kind == MarketCorporateActionKind.distribution &&
      action.status == MarketCorporateActionStatus.implemented &&
      action.hasStockDistribution;
  if (!isSplit && !isStockDistribution) {
    return const _QuantityAdjustmentDecision();
  }
  if (action.status == MarketCorporateActionStatus.cancelled ||
      action.status == MarketCorporateActionStatus.proposed ||
      action.status == MarketCorporateActionStatus.approved) {
    return const _QuantityAdjustmentDecision();
  }
  final effectiveDate = action.exDate?.toUtc();
  if (effectiveDate == null) {
    final referenceDate = action.timelineDate?.toUtc();
    final couldAffectEntitlement =
        referenceDate == null ||
        (!referenceDate.isBefore(after) && !referenceDate.isAfter(before));
    return _QuantityAdjustmentDecision(
      blocksEntitlement: couldAffectEntitlement,
    );
  }
  if (effectiveDate.isBefore(after) || effectiveDate.isAfter(before)) {
    return const _QuantityAdjustmentDecision();
  }
  if (effectiveDate == after || effectiveDate == before) {
    return const _QuantityAdjustmentDecision(blocksEntitlement: true);
  }
  if (isSplit) {
    return _QuantityAdjustmentDecision(
      multiplier:
          (Decimal.fromInt(action.splitNumerator!) /
                  Decimal.fromInt(action.splitDenominator!))
              .toDecimal(scaleOnInfinitePrecision: 12),
    );
  }

  final components =
      (action.bonusRatio ?? Decimal.zero) +
      (action.capitalizationRatio ?? Decimal.zero);
  final combined = action.totalStockDistributionRatio;
  if (combined != null &&
      combined > Decimal.zero &&
      components > Decimal.zero &&
      combined != components) {
    return const _QuantityAdjustmentDecision(blocksEntitlement: true);
  }
  final addedRatio = combined != null && combined > Decimal.zero
      ? combined
      : components;
  return addedRatio > Decimal.zero
      ? _QuantityAdjustmentDecision(multiplier: Decimal.one + addedRatio)
      : const _QuantityAdjustmentDecision();
}

bool _actionEntryMatches(
  WatchlistSimulationActionEntryRow row,
  String watchlistItemId,
  MarketCorporateAction action, {
  required WatchlistSimulationPaperActionState paperState,
  required Decimal? eligibleQuantity,
  required Decimal? grossAmount,
  required Decimal? receivableGrossAmount,
  required Decimal? paperCashGrossAmount,
  required DateTime? stateAt,
}) {
  return row.deletedAt == null &&
      row.watchlistItemId == watchlistItemId &&
      row.symbol == action.symbol &&
      row.market == action.market.wire &&
      row.source == action.source &&
      row.dataset == action.dataset &&
      row.sourceKey == action.sourceKey &&
      row.revisionHash == action.revisionHash &&
      row.kind == action.kind.name &&
      row.status == action.status.name &&
      row.paperState == paperState.name &&
      _sameInstant(row.recordDate, action.recordDate) &&
      _sameInstant(row.exDate, action.exDate) &&
      _sameInstant(row.payDate, action.payDate) &&
      row.currency == action.currency &&
      row.cashPerShare == action.cashPerShare &&
      row.eligibleQuantity == eligibleQuantity &&
      row.grossAmount == grossAmount &&
      row.receivableGrossAmount == receivableGrossAmount &&
      row.paperCashGrossAmount == paperCashGrossAmount &&
      _sameInstant(row.stateAt, stateAt) &&
      row.withholdingTaxAmount == null &&
      row.netAmount == null &&
      row.baseCurrencyAmount == null;
}

bool _sameInstant(DateTime? left, DateTime? right) {
  if (left == null || right == null) return left == null && right == null;
  return left.toUtc() == right.toUtc();
}

WatchlistSimulationActionEntry _actionEntryFromRow(
  WatchlistSimulationActionEntryRow row,
) => WatchlistSimulationActionEntry(
  id: row.id,
  simulationId: row.simulationId,
  watchlistItemId: row.watchlistItemId,
  symbol: row.symbol,
  market: row.market,
  source: row.source,
  dataset: row.dataset,
  sourceKey: row.sourceKey,
  revisionHash: row.revisionHash,
  kind: _enumByName(MarketCorporateActionKind.values, row.kind),
  status: _enumByName(MarketCorporateActionStatus.values, row.status),
  paperState: _enumByName(
    WatchlistSimulationPaperActionState.values,
    row.paperState,
  ),
  recordDate: row.recordDate?.toUtc(),
  exDate: row.exDate?.toUtc(),
  payDate: row.payDate?.toUtc(),
  currency: row.currency,
  cashPerShare: row.cashPerShare,
  eligibleQuantity: row.eligibleQuantity,
  grossAmount: row.grossAmount,
  receivableGrossAmount: row.receivableGrossAmount,
  paperCashGrossAmount: row.paperCashGrossAmount,
  stateAt: row.stateAt?.toUtc(),
  withholdingTaxAmount: row.withholdingTaxAmount,
  netAmount: row.netAmount,
  baseCurrencyAmount: row.baseCurrencyAmount,
  createdAt: row.createdAt.toUtc(),
  sync: SyncMeta(
    ownerUserId: row.ownerUserId,
    updatedAt: row.updatedAt.toUtc(),
    updatedByDevice: row.updatedByDevice,
    hlc: row.hlc,
    deletedAt: row.deletedAt?.toUtc(),
  ),
);

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

T _enumByName<T extends Enum>(Iterable<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw StateError('Unknown persisted enum value: $name');
}

SyncMeta _syncFromStamp(MutationStamp stamp) => SyncMeta(
  ownerUserId: stamp.ownerUserId,
  updatedAt: stamp.now,
  updatedByDevice: stamp.deviceId,
  hlc: stamp.hlc,
);
