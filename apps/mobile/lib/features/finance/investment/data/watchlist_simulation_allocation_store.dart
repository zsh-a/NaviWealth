import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../../core/persistence/app_database.dart';
import '../../../../core/sync/sync_meta.dart';
import '../domain/watchlist_simulation.dart';

/// Reads one selected allocation and its explicit predecessor lineage.
///
/// Header, lineage and current holdings are separate normalized reads within
/// one SQLite transaction. Old branches never multiply current holding rows.
class WatchlistSimulationAllocationStore {
  WatchlistSimulationAllocationStore(this._db);

  final AppDatabase _db;

  Stream<ResolvedWatchlistSimulationAllocation> watch({
    required String ownerUserId,
    required String simulationId,
  }) => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          _db.watchlistSimulations,
          _db.watchlistSimulationAllocationHeads,
          _db.watchlistSimulationAllocationVersions,
          _db.watchlistSimulationHoldingVersions,
        },
      )
      .watch()
      .asyncMap(
        (_) => resolve(ownerUserId: ownerUserId, simulationId: simulationId),
      );

  Future<ResolvedWatchlistSimulationAllocation> resolve({
    required String ownerUserId,
    required String simulationId,
  }) => _db.transaction(() async {
    final snapshot = await _read(ownerUserId, simulationId);
    return snapshot.allocation;
  });

  Future<WatchlistSimulationAllocationLineage> lineage({
    required String ownerUserId,
    required String simulationId,
  }) => _db.transaction(() async {
    final snapshot = await _read(ownerUserId, simulationId);
    return snapshot.allocation.isUsable
        ? WatchlistSimulationAllocationLineage(snapshot.versions.keys.toSet())
        : const WatchlistSimulationAllocationLineage.pending();
  });

  Future<WatchlistSimulationRecordDateAllocation> at({
    required String ownerUserId,
    required String simulationId,
    required DateTime effectiveAt,
  }) => _db.transaction(() async {
    final snapshot = await _read(ownerUserId, simulationId);
    if (!snapshot.allocation.isUsable) {
      return const WatchlistSimulationRecordDateAllocation.pending();
    }
    final visited = <String>{};
    var current = snapshot.versions[snapshot.allocation.allocationVersionId];
    while (current != null && visited.add(current.id)) {
      if (!current.effectiveAt.toUtc().isAfter(effectiveAt.toUtc())) {
        final holdings = await _holdings(ownerUserId, simulationId, current.id);
        if (!_resolveVersion(current, holdings, {current.id}).isUsable) {
          return const WatchlistSimulationRecordDateAllocation.pending();
        }
        return WatchlistSimulationRecordDateAllocation.usable(current);
      }
      final previousId = current.previousAllocationVersionId;
      if (previousId == null) {
        return const WatchlistSimulationRecordDateAllocation.none();
      }
      current = snapshot.versions[previousId];
    }
    // A missing predecessor may still be in flight. A cycle is unusable too.
    return const WatchlistSimulationRecordDateAllocation.pending();
  });

  Future<_AllocationSnapshot> _read(String owner, String simulationId) async {
    final simulation =
        await (_db.select(_db.watchlistSimulations)..where(
              (t) =>
                  t.ownerUserId.equals(owner) &
                  t.id.equals(simulationId) &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (simulation == null) return const _AllocationSnapshot(_invalid, {});
    final head =
        await (_db.select(_db.watchlistSimulationAllocationHeads)..where(
              (t) =>
                  t.ownerUserId.equals(owner) &
                  t.id.equals(simulationId) &
                  t.simulationId.equals(simulationId) &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (head == null) return const _AllocationSnapshot(_pending, {});

    // UNION bounds a malformed cyclic lineage. Both anchor and recursive step
    // enforce owner/simulation scope; unrelated historical branches are unread.
    final rows = await _db
        .customSelect(
          '''
      WITH RECURSIVE lineage AS (
        SELECT * FROM watchlist_simulation_allocation_versions
        WHERE owner_user_id = ? AND simulation_id = ? AND id = ?
          AND deleted_at IS NULL
        UNION
        SELECT previous.* FROM watchlist_simulation_allocation_versions previous
        JOIN lineage ON previous.id = lineage.previous_allocation_version_id
        WHERE previous.owner_user_id = ? AND previous.simulation_id = ?
          AND previous.deleted_at IS NULL
      ) SELECT * FROM lineage
    ''',
          variables: [
            Variable(owner),
            Variable(simulationId),
            Variable(head.allocationVersionId),
            Variable(owner),
            Variable(simulationId),
          ],
        )
        .get();
    final versions = <String, WatchlistSimulationAllocationVersionRow>{};
    for (final result in rows) {
      final version = _db.watchlistSimulationAllocationVersions.map(
        result.data,
      );
      versions[version.id] = version;
    }
    final current = versions[head.allocationVersionId];
    if (current == null) return _AllocationSnapshot(_pending, versions);
    final holdings = await _holdings(owner, simulationId, current.id);
    return _AllocationSnapshot(
      _resolveVersion(current, holdings, versions.keys.toSet()),
      versions,
    );
  }

  Future<List<WatchlistSimulationHoldingVersionRow>> _holdings(
    String owner,
    String simulationId,
    String versionId,
  ) =>
      (_db.select(_db.watchlistSimulationHoldingVersions)
            ..where(
              (t) =>
                  t.ownerUserId.equals(owner) &
                  t.simulationId.equals(simulationId) &
                  t.allocationVersionId.equals(versionId) &
                  t.deletedAt.isNull(),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.watchlistItemId)]))
          .get();
}

ResolvedWatchlistSimulationAllocation _resolveVersion(
  WatchlistSimulationAllocationVersionRow version,
  List<WatchlistSimulationHoldingVersionRow> holdings,
  Set<String> lineage,
) {
  final total = holdings.fold(
    version.cashWeight,
    (sum, h) => sum + h.targetWeight,
  );
  final malformed =
      version.cashWeight < Decimal.zero ||
      version.cashWeight > Decimal.one ||
      holdings.any(
        (h) => h.targetWeight <= Decimal.zero || h.targetWeight > Decimal.one,
      ) ||
      holdings.map((h) => h.watchlistItemId).toSet().length != holdings.length;
  if (malformed || total != Decimal.one) {
    return ResolvedWatchlistSimulationAllocation(
      status: malformed || total > Decimal.one
          ? WatchlistSimulationAllocationStatus.invalid
          : WatchlistSimulationAllocationStatus.pending,
      allocationVersionId: version.id,
      cashWeight: null,
      positions: const [],
    );
  }
  final knownQuantities = holdings.where((h) => h.quantity != null).length;
  return ResolvedWatchlistSimulationAllocation(
    status: WatchlistSimulationAllocationStatus.selected,
    allocationVersionId: version.id,
    cashWeight: version.cashWeight,
    quantityCoverage: knownQuantities == holdings.length
        ? WatchlistSimulationQuantityCoverage.complete
        : knownQuantities == 0
        ? WatchlistSimulationQuantityCoverage.unavailable
        : WatchlistSimulationQuantityCoverage.partial,
    validAllocationBasisKeys: lineage
        .map(watchlistSimulationAllocationBasisKey)
        .toSet(),
    positions: List.unmodifiable(
      holdings.map(
        (h) => WatchlistSimulationPosition(
          id: h.id,
          simulationId: h.simulationId,
          watchlistItemId: h.watchlistItemId,
          targetWeight: h.targetWeight,
          quantity: h.quantity,
          createdAt: h.createdAt,
          sync: SyncMeta(
            ownerUserId: h.ownerUserId,
            updatedAt: h.updatedAt,
            updatedByDevice: h.updatedByDevice,
            hlc: h.hlc,
            deletedAt: h.deletedAt,
          ),
        ),
      ),
    ),
  );
}

class _AllocationSnapshot {
  const _AllocationSnapshot(this.allocation, this.versions);
  final ResolvedWatchlistSimulationAllocation allocation;
  final Map<String, WatchlistSimulationAllocationVersionRow> versions;
}

class WatchlistSimulationAllocationLineage {
  const WatchlistSimulationAllocationLineage(this.versionIds) : pending = false;
  const WatchlistSimulationAllocationLineage.pending()
    : versionIds = const {},
      pending = true;
  final Set<String> versionIds;
  final bool pending;
}

class WatchlistSimulationRecordDateAllocation {
  const WatchlistSimulationRecordDateAllocation.usable(this.version)
    : pending = false;
  const WatchlistSimulationRecordDateAllocation.pending()
    : version = null,
      pending = true;
  const WatchlistSimulationRecordDateAllocation.none()
    : version = null,
      pending = false;
  final WatchlistSimulationAllocationVersionRow? version;
  final bool pending;
}

const _pending = ResolvedWatchlistSimulationAllocation(
  status: WatchlistSimulationAllocationStatus.pending,
  allocationVersionId: null,
  cashWeight: null,
  positions: [],
);
const _invalid = ResolvedWatchlistSimulationAllocation(
  status: WatchlistSimulationAllocationStatus.invalid,
  allocationVersionId: null,
  cashWeight: null,
  positions: [],
);
