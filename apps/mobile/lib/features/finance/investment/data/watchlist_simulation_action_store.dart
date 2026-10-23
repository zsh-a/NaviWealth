import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../../core/persistence/app_database.dart';
import '../../../../core/sync/mutation_context.dart';
import '../../../../core/sync/op_outbox.dart';
import '../../../../core/sync/sync_meta.dart';
import '../../market/domain/asset_market.dart';
import '../../market/domain/market_corporate_action.dart';
import '../domain/watchlist_simulation.dart';
import 'watchlist_simulation_allocation_store.dart';

/// Synced paper dividends and their provider-independent lifecycle reducer.
class WatchlistSimulationActionStore {
  WatchlistSimulationActionStore(
    this._db,
    this._outbox,
    this._stamper,
    this._allocations,
  );

  static const tableName = 'watchlist_simulation_action_entries';
  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final WatchlistSimulationAllocationStore _allocations;

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
  }) => _db.transaction(() async {
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
    }
    return List<WatchlistSimulationActionTarget>.unmodifiable(targets.values);
  });

  Future<WatchlistSimulationAllocationLineage> _selectedAllocationLineage({
    required String ownerUserId,
    required String simulationId,
  }) => _allocations.lineage(
    ownerUserId: ownerUserId,
    simulationId: simulationId,
  );

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
            : watchlistSimulationAllocationBasisKey(allocationVersion.id);
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
          await _outbox.enqueue(table: tableName, rowId: row.id);
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
        await _outbox.enqueue(table: tableName, rowId: row.id);
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
  /// revised or cancelled. Trusted holdings may attach record-date virtual quantity
  /// and gross paper entitlement; tax, net cash, base value, and NAV remain
  /// unapplied. Holdings without trusted quantity remain reference-only.
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
            await _outbox.enqueue(table: tableName, rowId: existing.id);
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
                : watchlistSimulationAllocationBasisKey(allocationVersion.id);
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
          await _outbox.enqueue(table: tableName, rowId: id);
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

  Future<WatchlistSimulationRecordDateAllocation> _allocationVersionAt({
    required String ownerUserId,
    required String simulationId,
    required DateTime effectiveAt,
  }) => _allocations.at(
    ownerUserId: ownerUserId,
    simulationId: simulationId,
    effectiveAt: effectiveAt,
  );

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

  Future<ResolvedWatchlistSimulationAllocation> resolveAllocation({
    required String ownerUserId,
    required String simulationId,
  }) => _allocations.resolve(
    ownerUserId: ownerUserId,
    simulationId: simulationId,
  );
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
