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

enum WatchlistSimulationAllocationStatus {
  selected,
  legacyFallback,
  pending,
  invalid,
}

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
    this.allocationProtocolVersion = 0,
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
  final int allocationProtocolVersion;
  final DateTime baselineAt;
  final DateTime createdAt;
  final SyncMeta sync;
}

class ResolvedWatchlistSimulationAllocation {
  const ResolvedWatchlistSimulationAllocation({
    required this.status,
    required this.allocationVersionId,
    required this.cashWeight,
    required this.positions,
    String? allocationBasisKey,
    Set<String> validAllocationBasisKeys = const <String>{},
  }) : _allocationBasisKey = allocationBasisKey,
       _validAllocationBasisKeys = validAllocationBasisKeys;

  final WatchlistSimulationAllocationStatus status;
  final String? allocationVersionId;
  final Decimal? cashWeight;
  final List<WatchlistSimulationPosition> positions;
  final String? _allocationBasisKey;
  final Set<String> _validAllocationBasisKeys;

  String? get allocationBasisKey =>
      _allocationBasisKey ??
      (allocationVersionId == null
          ? null
          : _versionAllocationBasisKey(allocationVersionId!));

  Set<String> get validAllocationBasisKeys {
    if (_validAllocationBasisKeys.isNotEmpty) return _validAllocationBasisKeys;
    final basisKey = allocationBasisKey;
    return basisKey == null ? const <String>{} : {basisKey};
  }

  bool get isUsable =>
      status == WatchlistSimulationAllocationStatus.selected ||
      status == WatchlistSimulationAllocationStatus.legacyFallback;
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
    this.allocationBasisKey,
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
  final String? allocationBasisKey;
  final DateTime createdAt;
  final SyncMeta sync;

  bool get hasPaperValue =>
      eligibleQuantity != null ||
      grossAmount != null ||
      receivableGrossAmount != null ||
      paperCashGrossAmount != null ||
      withholdingTaxAmount != null ||
      netAmount != null ||
      baseCurrencyAmount != null;

  bool get isReferenceOnly =>
      paperState == WatchlistSimulationPaperActionState.referenceOnly &&
      !hasPaperValue;
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
    this.allocationBasisKey,
  });

  final String id;
  final String simulationId;
  final String observationDay;
  final DateTime observedAt;
  final Decimal projectedValue;
  final Decimal weightedDailyChange;
  final Decimal pricedWeight;
  final Decimal missingQuoteWeight;
  final String? allocationBasisKey;
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
  static const allocationHeadsTable = 'watchlist_simulation_allocation_heads';
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
  }) => watchResolvedAllocation(
    ownerUserId: ownerUserId,
    simulationId: simulationId,
  ).map((allocation) => allocation.positions);

  Stream<ResolvedWatchlistSimulationAllocation> watchResolvedAllocation({
    required String ownerUserId,
    required String simulationId,
  }) {
    return _allocationSnapshotQuery(
      ownerUserId: ownerUserId,
      simulationId: simulationId,
    ).watch().map(_resolveAllocationSnapshot);
  }

  Future<ResolvedWatchlistSimulationAllocation> resolveAllocation({
    required String ownerUserId,
    required String simulationId,
  }) async {
    final rows = await _allocationSnapshotQuery(
      ownerUserId: ownerUserId,
      simulationId: simulationId,
    ).get();
    return _resolveAllocationSnapshot(rows);
  }

  JoinedSelectStatement<HasResultSet, dynamic> _allocationSnapshotQuery({
    required String ownerUserId,
    required String simulationId,
  }) {
    final simulations = _db.watchlistSimulations;
    final heads = _db.watchlistSimulationAllocationHeads;
    final versions = _db.watchlistSimulationAllocationVersions;
    final holdings = _db.watchlistSimulationHoldingVersions;
    final positions = _db.watchlistSimulationPositions;
    return _db.select(simulations).join([
        leftOuterJoin(
          heads,
          heads.ownerUserId.equalsExp(simulations.ownerUserId) &
              heads.simulationId.equalsExp(simulations.id),
        ),
        leftOuterJoin(
          versions,
          versions.ownerUserId.equalsExp(simulations.ownerUserId) &
              versions.simulationId.equalsExp(simulations.id),
        ),
        leftOuterJoin(
          holdings,
          holdings.ownerUserId.equalsExp(simulations.ownerUserId) &
              holdings.simulationId.equalsExp(simulations.id) &
              holdings.allocationVersionId.equalsExp(versions.id),
        ),
        leftOuterJoin(
          positions,
          positions.ownerUserId.equalsExp(simulations.ownerUserId) &
              positions.simulationId.equalsExp(simulations.id),
        ),
      ])
      ..where(simulations.ownerUserId.equals(ownerUserId))
      ..where(simulations.id.equals(simulationId))
      ..where(simulations.deletedAt.isNull());
  }

  ResolvedWatchlistSimulationAllocation _resolveAllocationSnapshot(
    List<TypedResult> rows,
  ) {
    if (rows.isEmpty) return _invalidAllocation;
    final simulation = rows.first.readTable(_db.watchlistSimulations);
    final heads = <String, WatchlistSimulationAllocationHeadRow>{};
    final versions = <String, WatchlistSimulationAllocationVersionRow>{};
    final holdings = <String, WatchlistSimulationHoldingVersionRow>{};
    final positionRows = <String, WatchlistSimulationPositionRow>{};
    for (final result in rows) {
      final head = result.readTableOrNull(
        _db.watchlistSimulationAllocationHeads,
      );
      if (head != null) heads[head.id] = head;
      final version = result.readTableOrNull(
        _db.watchlistSimulationAllocationVersions,
      );
      if (version != null) versions[version.id] = version;
      final holding = result.readTableOrNull(
        _db.watchlistSimulationHoldingVersions,
      );
      if (holding != null) holdings[holding.id] = holding;
      final position = result.readTableOrNull(_db.watchlistSimulationPositions);
      if (position != null) positionRows[position.id] = position;
    }

    final activeHead = heads.values
        .where(
          (head) =>
              head.id == simulation.id &&
              head.simulationId == simulation.id &&
              head.deletedAt == null,
        )
        .firstOrNull;
    final activeVersions = <String, WatchlistSimulationAllocationVersionRow>{
      for (final version in versions.values)
        if (version.deletedAt == null) version.id: version,
    };
    final activeHoldings = holdings.values
        .where((holding) => holding.deletedAt == null)
        .toList(growable: false);
    if (activeHead != null) {
      final version = activeVersions[activeHead.allocationVersionId];
      if (version == null) return _pendingAllocation;
      final lineageIds = _allocationLineageVersionIds(
        current: version,
        versions: activeVersions.values,
      );
      return _resolveVersionSnapshot(
        version: version,
        holdings: activeHoldings,
        status: WatchlistSimulationAllocationStatus.selected,
        incompleteStatus: WatchlistSimulationAllocationStatus.pending,
        validBasisKeys: lineageIds.map(_versionAllocationBasisKey).toSet(),
      );
    }

    final hasExplicitProtocolEvidence =
        simulation.allocationProtocolVersion > 0 ||
        heads.values.isNotEmpty ||
        versions.values.any((version) => version.requiresExplicitHead) ||
        positionRows.values.any((position) => position.requiresExplicitHead);
    if (hasExplicitProtocolEvidence) return _pendingAllocation;

    final legacyVersions = activeVersions.values.toList(growable: false)
      ..sort(_compareAllocationVersionsNewestFirst);
    for (final version in legacyVersions) {
      final resolved = _resolveVersionSnapshot(
        version: version,
        holdings: activeHoldings,
        status: WatchlistSimulationAllocationStatus.legacyFallback,
        incompleteStatus: WatchlistSimulationAllocationStatus.pending,
        validBasisKeys: legacyVersions
            .map((candidate) => _versionAllocationBasisKey(candidate.id))
            .toSet(),
      );
      if (resolved.isUsable) return resolved;
    }
    if (legacyVersions.isNotEmpty ||
        simulation.calculationMode !=
            WatchlistSimulationCalculationMode.weightedDailyChangeV1.name) {
      return _pendingAllocation;
    }

    final positions =
        positionRows.values
            .where((position) => position.deletedAt == null)
            .map(_positionFromRow)
            .toList(growable: false)
          ..sort(
            (left, right) =>
                left.watchlistItemId.compareTo(right.watchlistItemId),
          );
    if (!_validAllocation(positions, simulation.cashWeight)) {
      return _invalidAllocation;
    }
    return ResolvedWatchlistSimulationAllocation(
      status: WatchlistSimulationAllocationStatus.legacyFallback,
      allocationVersionId: null,
      allocationBasisKey: _legacyAllocationBasisKey(
        cashWeight: simulation.cashWeight,
        positions: positions,
      ),
      validAllocationBasisKeys: {
        _legacyAllocationBasisKey(
          cashWeight: simulation.cashWeight,
          positions: positions,
        ),
      },
      cashWeight: simulation.cashWeight,
      positions: List<WatchlistSimulationPosition>.unmodifiable(positions),
    );
  }

  Future<ResolvedWatchlistSimulationAllocation> _resolveVersion({
    required String ownerUserId,
    required WatchlistSimulationAllocationVersionRow version,
    required WatchlistSimulationAllocationStatus status,
    required WatchlistSimulationAllocationStatus incompleteStatus,
  }) async {
    final holdings =
        await (_db.select(_db.watchlistSimulationHoldingVersions)..where(
              (t) =>
                  t.ownerUserId.equals(ownerUserId) &
                  t.simulationId.equals(version.simulationId) &
                  t.allocationVersionId.equals(version.id) &
                  t.deletedAt.isNull(),
            ))
            .get();
    return _resolveVersionSnapshot(
      version: version,
      holdings: holdings,
      status: status,
      incompleteStatus: incompleteStatus,
    );
  }

  ResolvedWatchlistSimulationAllocation _resolveVersionSnapshot({
    required WatchlistSimulationAllocationVersionRow version,
    required Iterable<WatchlistSimulationHoldingVersionRow> holdings,
    required WatchlistSimulationAllocationStatus status,
    required WatchlistSimulationAllocationStatus incompleteStatus,
    Set<String>? validBasisKeys,
  }) {
    final positions =
        holdings
            .where((holding) => holding.allocationVersionId == version.id)
            .map(_positionFromHoldingRow)
            .toList(growable: false)
          ..sort(
            (left, right) =>
                left.watchlistItemId.compareTo(right.watchlistItemId),
          );
    final malformed =
        version.cashWeight < Decimal.zero ||
        version.cashWeight > Decimal.one ||
        positions.any(
          (position) =>
              position.targetWeight <= Decimal.zero ||
              position.targetWeight > Decimal.one,
        ) ||
        positions.map((position) => position.watchlistItemId).toSet().length !=
            positions.length;
    final total = positions.fold<Decimal>(
      version.cashWeight,
      (sum, position) => sum + position.targetWeight,
    );
    if (malformed || total > Decimal.one) {
      return ResolvedWatchlistSimulationAllocation(
        status: WatchlistSimulationAllocationStatus.invalid,
        allocationVersionId: version.id,
        cashWeight: null,
        positions: const [],
      );
    }
    if (total < Decimal.one) {
      return ResolvedWatchlistSimulationAllocation(
        status: incompleteStatus,
        allocationVersionId: version.id,
        cashWeight: null,
        positions: const [],
      );
    }
    return ResolvedWatchlistSimulationAllocation(
      status: status,
      allocationVersionId: version.id,
      allocationBasisKey: _versionAllocationBasisKey(version.id),
      validAllocationBasisKeys:
          validBasisKeys ?? {_versionAllocationBasisKey(version.id)},
      cashWeight: version.cashWeight,
      positions: List<WatchlistSimulationPosition>.unmodifiable(positions),
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
    final lineage = await _selectedAllocationLineage(
      ownerUserId: ownerUserId,
      simulationId: simulationId,
    );
    if (lineage.versionIds.isNotEmpty) {
      final holdings =
          await (_db.select(_db.watchlistSimulationHoldingVersions)..where(
                (t) =>
                    t.ownerUserId.equals(ownerUserId) &
                    t.simulationId.equals(simulationId) &
                    t.allocationVersionId.isIn(lineage.versionIds) &
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
    } else if (lineage.allowsLegacyPositions) {
      final positions =
          await (_db.select(_db.watchlistSimulationPositions)..where(
                (t) =>
                    t.ownerUserId.equals(ownerUserId) &
                    t.simulationId.equals(simulationId) &
                    t.deletedAt.isNull(),
              ))
              .get();
      for (final row in positions) {
        final separator = row.watchlistItemId.indexOf(':');
        if (separator <= 0) continue;
        final market = assetMarketFromWire(
          row.watchlistItemId.substring(0, separator),
        );
        if (market == null) continue;
        targets[row.watchlistItemId] = WatchlistSimulationActionTarget(
          watchlistItemId: row.watchlistItemId,
          symbol: row.watchlistItemId.substring(separator + 1),
          market: market,
        );
      }
    }
    return List<WatchlistSimulationActionTarget>.unmodifiable(targets.values);
  }

  Future<_SelectedAllocationLineage> _selectedAllocationLineage({
    required String ownerUserId,
    required String simulationId,
  }) async {
    final simulation =
        await (_db.select(_db.watchlistSimulations)..where(
              (t) =>
                  t.ownerUserId.equals(ownerUserId) &
                  t.id.equals(simulationId) &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (simulation == null) return const _SelectedAllocationLineage.pending();
    final versions =
        await (_db.select(_db.watchlistSimulationAllocationVersions)..where(
              (t) =>
                  t.ownerUserId.equals(ownerUserId) &
                  t.simulationId.equals(simulationId),
            ))
            .get();
    final activeVersions = <String, WatchlistSimulationAllocationVersionRow>{
      for (final version in versions)
        if (version.deletedAt == null) version.id: version,
    };
    final headEvidence =
        await (_db.select(_db.watchlistSimulationAllocationHeads)..where(
              (t) =>
                  t.ownerUserId.equals(ownerUserId) &
                  t.id.equals(simulationId) &
                  t.simulationId.equals(simulationId),
            ))
            .getSingleOrNull();
    final head = headEvidence?.deletedAt == null ? headEvidence : null;
    if (head != null) {
      final ids = <String>{};
      final visited = <String>{};
      var current = activeVersions[head.allocationVersionId];
      while (current != null && visited.add(current.id)) {
        ids.add(current.id);
        final previousId = current.previousAllocationVersionId;
        if (previousId != null) {
          current = activeVersions[previousId];
        } else if (!current.requiresExplicitHead) {
          current = _legacyAllocationPredecessor(
            current: current,
            versions: activeVersions.values,
          );
        } else {
          current = null;
        }
      }
      if (ids.isEmpty) return const _SelectedAllocationLineage.pending();
      return _SelectedAllocationLineage(versionIds: ids);
    }
    final positions =
        await (_db.select(_db.watchlistSimulationPositions)..where(
              (t) =>
                  t.ownerUserId.equals(ownerUserId) &
                  t.simulationId.equals(simulationId),
            ))
            .get();
    final hasExplicitEvidence =
        simulation.allocationProtocolVersion > 0 ||
        headEvidence != null ||
        versions.any((version) => version.requiresExplicitHead) ||
        positions.any((position) => position.requiresExplicitHead);
    if (hasExplicitEvidence) {
      return const _SelectedAllocationLineage.pending();
    }
    if (activeVersions.isNotEmpty) {
      return _SelectedAllocationLineage(
        versionIds: activeVersions.keys.toSet(),
      );
    }
    return const _SelectedAllocationLineage.legacyPositions();
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
      allocationProtocolVersion: 1,
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
              allocationProtocolVersion: const Value(1),
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
      final allocationVersionId = await _writeAllocationVersion(
        simulation: simulation,
        targetWeights: targetWeights,
        cashWeight: cashWeight,
        holdingInputs: holdingInputs ?? const {},
        reason: WatchlistSimulationAllocationReason.creation,
        capitalBase: holdingInputs == null ? null : startingCapital,
        previousAllocationVersionId: null,
        stamp: stamp,
      );
      await _writeAllocationHead(
        simulationId: simulation.id,
        allocationVersionId: allocationVersionId,
        stamp: stamp,
      );
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
    final allocationReady = await _ensureObservationBaseline(
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
      final baselineDay = _observationDay(activeSimulation.baselineAt);
      final validRows = <WatchlistSimulationObservationRow>[];
      for (final row in allRows) {
        final isBaseline =
            row.allocationBasisKey == null && row.observationDay == baselineDay;
        final isValidBasis =
            row.allocationBasisKey != null &&
            validBasisKeys.contains(row.allocationBasisKey);
        if (isBaseline || isValidBasis) {
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
        final recordDate = row.recordDate?.toUtc();
        if (recordDate == null || row.allocationBasisKey == null) {
          // Migrated valued rows without provenance cannot advance until a
          // trusted rematerialization establishes their allocation basis.
          continue;
        }
        final allocation = await _allocationVersionAt(
          ownerUserId: stamp.ownerUserId,
          simulationId: simulation.id,
          effectiveAt: recordDate,
        );
        if (allocation.pending) continue;
        final allocationVersion = allocation.version;
        final expectedBasis = allocationVersion == null
            ? null
            : _versionAllocationBasisKey(allocationVersion.id);
        final holding = allocationVersion == null
            ? null
            : await (_db.select(_db.watchlistSimulationHoldingVersions)..where(
                    (t) =>
                        t.ownerUserId.equals(stamp.ownerUserId) &
                        t.allocationVersionId.equals(allocationVersion.id) &
                        t.watchlistItemId.equals(row.watchlistItemId) &
                        t.deletedAt.isNull(),
                  ))
                  .getSingleOrNull();
        if (expectedBasis != row.allocationBasisKey ||
            holding?.quantity == null) {
          await (_db.update(
            _db.watchlistSimulationActionEntries,
          )..where((t) => t.id.equals(row.id))).write(
            WatchlistSimulationActionEntriesCompanion(
              paperState: Value(
                WatchlistSimulationPaperActionState.referenceOnly.name,
              ),
              eligibleQuantity: const Value(null),
              grossAmount: const Value(null),
              receivableGrossAmount: const Value(null),
              paperCashGrossAmount: const Value(null),
              stateAt: const Value(null),
              allocationBasisKey: const Value(null),
              withholdingTaxAmount: const Value(null),
              netAmount: const Value(null),
              baseCurrencyAmount: const Value(null),
              updatedAt: Value(stamp.now),
              updatedByDevice: Value(stamp.deviceId),
              hlc: Value(stamp.hlc),
            ),
          );
          await _outbox.enqueue(table: actionEntriesTable, rowId: row.id);
          changedIds.add(row.id);
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
      final lineage = await _selectedAllocationLineage(
        ownerUserId: stamp.ownerUserId,
        simulationId: simulation.id,
      );
      if (lineage.pending) return;
      final allocationEligibleItemIds = <String>{};
      if (lineage.versionIds.isNotEmpty) {
        final selectedHoldings =
            await (_db.select(_db.watchlistSimulationHoldingVersions)..where(
                  (t) =>
                      t.ownerUserId.equals(stamp.ownerUserId) &
                      t.simulationId.equals(simulation.id) &
                      t.allocationVersionId.isIn(lineage.versionIds) &
                      t.deletedAt.isNull(),
                ))
                .get();
        allocationEligibleItemIds.addAll(
          selectedHoldings.map((row) => row.watchlistItemId),
        );
      } else if (lineage.allowsLegacyPositions) {
        final activePositions =
            await (_db.select(_db.watchlistSimulationPositions)..where(
                  (t) =>
                      t.ownerUserId.equals(stamp.ownerUserId) &
                      t.simulationId.equals(simulation.id) &
                      t.deletedAt.isNull(),
                ))
                .get();
        allocationEligibleItemIds.addAll(
          activePositions.map((row) => row.watchlistItemId),
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
      final existingActionIds = {for (final row in existingActionRows) row.id};

      for (final entry in actionsByWatchlistItemId.entries) {
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
          if (!allocationEligibleItemIds.contains(entry.key) &&
              !existingActionIds.contains(id)) {
            continue;
          }
          final existing =
              await (_db.select(_db.watchlistSimulationActionEntries)..where(
                    (t) =>
                        t.id.equals(id) &
                        t.ownerUserId.equals(stamp.ownerUserId),
                  ))
                  .getSingleOrNull();
          if (existing != null &&
              lineage.versionIds.isNotEmpty &&
              !allocationEligibleItemIds.contains(entry.key)) {
            await (_db.update(
              _db.watchlistSimulationActionEntries,
            )..where((t) => t.id.equals(existing.id))).write(
              WatchlistSimulationActionEntriesCompanion(
                eligibleQuantity: const Value(null),
                grossAmount: const Value(null),
                receivableGrossAmount: const Value(null),
                paperCashGrossAmount: const Value(null),
                allocationBasisKey: const Value(null),
                updatedAt: Value(stamp.now),
                updatedByDevice: Value(stamp.deviceId),
                hlc: Value(stamp.hlc),
                deletedAt: Value(stamp.now),
              ),
            );
            await _outbox.enqueue(
              table: actionEntriesTable,
              rowId: existing.id,
            );
            continue;
          }
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
          String? allocationBasisKey;
          var provenanceInvalidated = false;
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
            final allocation = await _allocationVersionAt(
              ownerUserId: stamp.ownerUserId,
              simulationId: simulation.id,
              effectiveAt: action.recordDate!.toUtc(),
            );
            if (allocation.pending) continue;
            final allocationVersion = allocation.version;
            allocationBasisKey = allocationVersion == null
                ? null
                : _versionAllocationBasisKey(allocationVersion.id);
            final holding = allocationVersion == null
                ? null
                : await (_db.select(
                        _db.watchlistSimulationHoldingVersions,
                      )..where(
                        (t) =>
                            t.ownerUserId.equals(stamp.ownerUserId) &
                            t.allocationVersionId.equals(allocationVersion.id) &
                            t.watchlistItemId.equals(entry.key) &
                            t.deletedAt.isNull(),
                      ))
                      .getSingleOrNull();
            provenanceInvalidated =
                _isTrustedEntitlementState(existing?.paperState) &&
                (holding == null ||
                    (existing!.allocationBasisKey != null &&
                        existing.allocationBasisKey != allocationBasisKey));
            eligibleQuantity = holding?.quantity;
            var adjustmentEvidenceBlocked = false;
            if (eligibleQuantity != null && holding != null) {
              for (final adjustment in itemActions) {
                final decision = _quantityAdjustmentDecision(
                  adjustment,
                  after: holding.effectiveAt.toUtc(),
                  before: action.recordDate!.toUtc(),
                );
                if (decision.blocksEntitlement) {
                  eligibleQuantity = null;
                  adjustmentEvidenceBlocked = true;
                  break;
                }
                final multiplier = decision.multiplier;
                if (multiplier != null) {
                  eligibleQuantity = (eligibleQuantity! * multiplier).round(
                    scale: 12,
                  );
                }
              }
              if (adjustmentEvidenceBlocked &&
                  _isTrustedEntitlementState(existing?.paperState) &&
                  !provenanceInvalidated) {
                continue;
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
          } else if (_isTrustedEntitlementState(existing?.paperState)) {
            provenanceInvalidated = true;
          }
          if (_isTrustedEntitlementState(existing?.paperState) &&
              action.status != MarketCorporateActionStatus.cancelled) {
            if (provenanceInvalidated) {
              paperState = WatchlistSimulationPaperActionState.referenceOnly;
              eligibleQuantity = null;
              grossAmount = null;
              receivableGrossAmount = null;
              paperCashGrossAmount = null;
              stateAt = null;
              allocationBasisKey = null;
            } else if (!_isTrustedEntitlementState(paperState.name)) {
              continue;
            } else {
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
                allocationBasisKey: allocationBasisKey,
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
                  allocationBasisKey: Value(allocationBasisKey),
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
              allocationBasisKey: allocationBasisKey,
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
      final resolved = await resolveAllocation(
        ownerUserId: stamp.ownerUserId,
        simulationId: simulation.id,
      );
      if (resolved.status == WatchlistSimulationAllocationStatus.pending) {
        throw StateError('Watchlist simulation allocation is still syncing.');
      }
      final existingRows =
          await (_db.select(_db.watchlistSimulationPositions)..where(
                (t) =>
                    t.ownerUserId.equals(stamp.ownerUserId) &
                    t.simulationId.equals(simulation.id),
              ))
              .get();
      final currentWeights = resolved.isUsable
          ? <String, Decimal>{
              for (final position in resolved.positions)
                position.watchlistItemId: position.targetWeight,
            }
          : <String, Decimal>{
              for (final row in existingRows)
                if (row.deletedAt == null)
                  row.watchlistItemId: row.targetWeight,
            };
      final currentCashWeight = resolved.isUsable
          ? resolved.cashWeight
          : activeSimulation.cashWeight;
      if (currentCashWeight == cashWeight &&
          _decimalMapsEqual(currentWeights, targetWeights)) {
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
              allocationProtocolVersion: const Value(1),
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
            requiresExplicitHead: const Value(true),
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
      final allocationVersionId = await _writeAllocationVersion(
        simulation: simulation,
        targetWeights: targetWeights,
        cashWeight: cashWeight,
        holdingInputs: holdingInputs ?? const {},
        reason: WatchlistSimulationAllocationReason.reallocation,
        capitalBase: null,
        previousAllocationVersionId: resolved.allocationVersionId,
        stamp: stamp,
      );
      await _writeAllocationHead(
        simulationId: simulation.id,
        allocationVersionId: allocationVersionId,
        stamp: stamp,
      );
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

  Future<_RecordDateAllocationResolution> _allocationVersionAt({
    required String ownerUserId,
    required String simulationId,
    required DateTime effectiveAt,
  }) async {
    final simulation =
        await (_db.select(_db.watchlistSimulations)..where(
              (t) =>
                  t.ownerUserId.equals(ownerUserId) &
                  t.id.equals(simulationId) &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (simulation == null) {
      return const _RecordDateAllocationResolution.none();
    }
    final versions =
        await (_db.select(_db.watchlistSimulationAllocationVersions)..where(
              (t) =>
                  t.ownerUserId.equals(ownerUserId) &
                  t.simulationId.equals(simulationId),
            ))
            .get();
    final activeVersions = <String, WatchlistSimulationAllocationVersionRow>{
      for (final version in versions)
        if (version.deletedAt == null) version.id: version,
    };
    final headEvidence =
        await (_db.select(_db.watchlistSimulationAllocationHeads)..where(
              (t) =>
                  t.ownerUserId.equals(ownerUserId) &
                  t.id.equals(simulationId) &
                  t.simulationId.equals(simulationId),
            ))
            .getSingleOrNull();
    final head = headEvidence?.deletedAt == null ? headEvidence : null;
    if (head != null) {
      final visited = <String>{};
      var current = activeVersions[head.allocationVersionId];
      if (current == null) {
        return const _RecordDateAllocationResolution.pending();
      }
      while (current != null) {
        final selected = current;
        if (!visited.add(selected.id)) break;
        if (!selected.effectiveAt.toUtc().isAfter(effectiveAt)) {
          final resolved = await _resolveVersion(
            ownerUserId: ownerUserId,
            version: selected,
            status: WatchlistSimulationAllocationStatus.selected,
            incompleteStatus: WatchlistSimulationAllocationStatus.pending,
          );
          if (!resolved.isUsable) {
            return const _RecordDateAllocationResolution.pending();
          }
          return _RecordDateAllocationResolution.usable(selected);
        }
        final previousId = selected.previousAllocationVersionId;
        final previous = previousId == null
            ? (!selected.requiresExplicitHead
                  ? _legacyAllocationPredecessor(
                      current: selected,
                      versions: activeVersions.values,
                    )
                  : null)
            : activeVersions[previousId];
        if (previousId != null && previous == null) {
          return const _RecordDateAllocationResolution.pending();
        }
        if (previous == null) {
          return const _RecordDateAllocationResolution.none();
        }
        current = previous;
      }
      return const _RecordDateAllocationResolution.pending();
    }
    final positions =
        await (_db.select(_db.watchlistSimulationPositions)..where(
              (t) =>
                  t.ownerUserId.equals(ownerUserId) &
                  t.simulationId.equals(simulationId),
            ))
            .get();
    final hasExplicitEvidence =
        simulation.allocationProtocolVersion > 0 ||
        headEvidence != null ||
        versions.any((version) => version.requiresExplicitHead) ||
        positions.any((position) => position.requiresExplicitHead);
    if (hasExplicitEvidence) {
      return const _RecordDateAllocationResolution.pending();
    }
    final legacy =
        activeVersions.values
            .where(
              (version) => !version.effectiveAt.toUtc().isAfter(effectiveAt),
            )
            .toList(growable: false)
          ..sort(_compareAllocationVersionsNewestFirst);
    for (final version in legacy) {
      final resolved = await _resolveVersion(
        ownerUserId: ownerUserId,
        version: version,
        status: WatchlistSimulationAllocationStatus.legacyFallback,
        incompleteStatus: WatchlistSimulationAllocationStatus.pending,
      );
      if (resolved.isUsable) {
        return _RecordDateAllocationResolution.usable(version);
      }
    }
    return legacy.isEmpty
        ? const _RecordDateAllocationResolution.none()
        : const _RecordDateAllocationResolution.pending();
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
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return true;
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
            previousAllocationVersionId: Value(previousAllocationVersionId),
            requiresExplicitHead: const Value(true),
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
            requiresExplicitHead: const Value(true),
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
    allocationProtocolVersion: row.allocationProtocolVersion,
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

int _compareAllocationVersionsNewestFirst(
  WatchlistSimulationAllocationVersionRow left,
  WatchlistSimulationAllocationVersionRow right,
) {
  final byTime = right.effectiveAt.compareTo(left.effectiveAt);
  if (byTime != 0) return byTime;
  final byHlc = right.hlc.compareTo(left.hlc);
  if (byHlc != 0) return byHlc;
  return right.id.compareTo(left.id);
}

WatchlistSimulationAllocationVersionRow? _legacyAllocationPredecessor({
  required WatchlistSimulationAllocationVersionRow current,
  required Iterable<WatchlistSimulationAllocationVersionRow> versions,
}) {
  final legacy =
      versions
          .where((version) => !version.requiresExplicitHead)
          .toList(growable: false)
        ..sort(_compareAllocationVersionsNewestFirst);
  final index = legacy.indexWhere((version) => version.id == current.id);
  return index >= 0 && index + 1 < legacy.length ? legacy[index + 1] : null;
}

Set<String> _allocationLineageVersionIds({
  required WatchlistSimulationAllocationVersionRow current,
  required Iterable<WatchlistSimulationAllocationVersionRow> versions,
}) {
  final byId = {for (final version in versions) version.id: version};
  final ids = <String>{};
  var candidate = current;
  while (ids.add(candidate.id)) {
    final previousId = candidate.previousAllocationVersionId;
    final previous = previousId == null
        ? (!candidate.requiresExplicitHead
              ? _legacyAllocationPredecessor(
                  current: candidate,
                  versions: byId.values,
                )
              : null)
        : byId[previousId];
    if (previous == null) break;
    candidate = previous;
  }
  return ids;
}

String _versionAllocationBasisKey(String versionId) => 'version:$versionId';

String _legacyAllocationBasisKey({
  required Decimal cashWeight,
  required Iterable<WatchlistSimulationPosition> positions,
}) {
  final sorted = positions.toList(growable: false)
    ..sort(
      (left, right) => left.watchlistItemId.compareTo(right.watchlistItemId),
    );
  final parts = sorted.map(
    (position) => '${position.watchlistItemId}=${position.targetWeight}',
  );
  return 'legacy-v1:$cashWeight|${parts.join('|')}';
}

class _SelectedAllocationLineage {
  const _SelectedAllocationLineage({required this.versionIds})
    : pending = false,
      allowsLegacyPositions = false;

  const _SelectedAllocationLineage.pending()
    : versionIds = const <String>{},
      pending = true,
      allowsLegacyPositions = false;

  const _SelectedAllocationLineage.legacyPositions()
    : versionIds = const <String>{},
      pending = false,
      allowsLegacyPositions = true;

  final Set<String> versionIds;
  final bool pending;
  final bool allowsLegacyPositions;
}

class _RecordDateAllocationResolution {
  const _RecordDateAllocationResolution.usable(this.version) : pending = false;
  const _RecordDateAllocationResolution.pending()
    : version = null,
      pending = true;
  const _RecordDateAllocationResolution.none()
    : version = null,
      pending = false;

  final WatchlistSimulationAllocationVersionRow? version;
  final bool pending;
}

const _pendingAllocation = ResolvedWatchlistSimulationAllocation(
  status: WatchlistSimulationAllocationStatus.pending,
  allocationVersionId: null,
  cashWeight: null,
  positions: [],
);

const _invalidAllocation = ResolvedWatchlistSimulationAllocation(
  status: WatchlistSimulationAllocationStatus.invalid,
  allocationVersionId: null,
  cashWeight: null,
  positions: [],
);

bool _validAllocation(
  Iterable<WatchlistSimulationPosition> positions,
  Decimal cashWeight,
) {
  if (cashWeight < Decimal.zero || cashWeight > Decimal.one) return false;
  var total = cashWeight;
  final ids = <String>{};
  for (final position in positions) {
    if (!ids.add(position.watchlistItemId) ||
        position.targetWeight <= Decimal.zero ||
        position.targetWeight > Decimal.one) {
      return false;
    }
    total += position.targetWeight;
  }
  return total == Decimal.one;
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

WatchlistSimulationPosition _positionFromHoldingRow(
  WatchlistSimulationHoldingVersionRow row,
) {
  return WatchlistSimulationPosition(
    id:
        'watchlist-simulation-position:${row.simulationId}:'
        '${row.watchlistItemId}',
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
  required String? allocationBasisKey,
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
      row.allocationBasisKey == allocationBasisKey &&
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
  allocationBasisKey: row.allocationBasisKey,
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
  allocationBasisKey: row.allocationBasisKey,
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
