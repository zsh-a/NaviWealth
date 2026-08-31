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
  cancelled,
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
  final Decimal? withholdingTaxAmount;
  final Decimal? netAmount;
  final Decimal? baseCurrencyAmount;
  final DateTime createdAt;
  final SyncMeta sync;

  bool get isReferenceOnly =>
      paperState == WatchlistSimulationPaperActionState.referenceOnly &&
      eligibleQuantity == null &&
      grossAmount == null &&
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
  }) async {
    if (actionsByWatchlistItemId.isEmpty) return const [];
    final stamp = await _stamper.stamp();
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
      final activeItemIds = activePositions
          .map((row) => row.watchlistItemId)
          .toSet();

      for (final entry in actionsByWatchlistItemId.entries) {
        if (!activeItemIds.contains(entry.key)) continue;
        for (final action in entry.value) {
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
          if (action.status == MarketCorporateActionStatus.cancelled) {
            paperState = WatchlistSimulationPaperActionState.cancelled;
          } else if (activeSimulation.calculationMode ==
                  WatchlistSimulationCalculationMode
                      .holdingsTotalReturnV2
                      .name &&
              action.recordDate != null) {
            final holdingQuery =
                _db.select(_db.watchlistSimulationHoldingVersions)
                  ..where((t) => t.ownerUserId.equals(stamp.ownerUserId))
                  ..where((t) => t.simulationId.equals(simulation.id))
                  ..where((t) => t.watchlistItemId.equals(entry.key))
                  ..where(
                    (t) => t.effectiveAt.isSmallerOrEqualValue(
                      action.recordDate!.toUtc(),
                    ),
                  )
                  ..where((t) => t.deletedAt.isNull())
                  ..orderBy([(t) => OrderingTerm.desc(t.effectiveAt)])
                  ..limit(1);
            final holding = await holdingQuery.getSingleOrNull();
            eligibleQuantity = holding?.quantity;
            if (eligibleQuantity != null) {
              grossAmount = (eligibleQuantity * action.cashPerShare!).round(
                scale: 12,
              );
              paperState =
                  WatchlistSimulationPaperActionState.entitlementRecorded;
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
    final resolved = <String, _ResolvedHoldingVersion>{};
    for (final entry in targetWeights.entries) {
      final input = holdingInputs[entry.key];
      final price = input?.rawPrice;
      final priceCurrency = input?.priceCurrency?.trim().toUpperCase();
      final sameCurrency =
          priceCurrency != null && priceCurrency == simulation.baseCurrency;
      Decimal? quantity;
      if (capitalBase != null &&
          (input?.quantityEligible ?? false) &&
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
        priceAsOf: input?.priceAsOf?.toUtc(),
        priceSource: input?.priceSource,
        fxToBase: price != null && sameCurrency ? Decimal.one : null,
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
            effectiveAt: stamp.now,
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
              effectiveAt: stamp.now,
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

bool _actionEntryMatches(
  WatchlistSimulationActionEntryRow row,
  String watchlistItemId,
  MarketCorporateAction action, {
  required WatchlistSimulationPaperActionState paperState,
  required Decimal? eligibleQuantity,
  required Decimal? grossAmount,
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
