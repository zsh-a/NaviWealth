part of 'investment_portfolio_repository.dart';

mixin InvestmentPortfolioRepositoryRemovalMixin {
  AppDatabase get _db;
  OutboxStore get _outbox;
  MutationStamper get _stamper;

  Future<List<PortfolioRebalanceGroupRow>> _activeGroupRows(String portfolioId);

  Future<void> _requireActiveGroup(String portfolioId, String groupId);

  Future<void> remove(
    InvestmentPortfolio portfolio, {
    String? destinationPortfolioId,
    String? destinationGroupId,
  }) async {
    if ((destinationPortfolioId == null) != (destinationGroupId == null) ||
        destinationPortfolioId == portfolio.id) {
      throw const PortfolioRemovalException(
        PortfolioRemovalFailureReason.transferTargetInvalid,
      );
    }
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      final activeTargets =
          await (_db.select(_db.portfolioAllocationTargets)..where(
                (table) =>
                    table.portfolioId.equals(portfolio.id) &
                    table.deletedAt.isNull(),
              ))
              .get();
      if (activeTargets.isEmpty) {
        throw const PortfolioRemovalException(
          PortfolioRemovalFailureReason.portfolioNotActive,
        );
      }
      final siblingUniverseIds = await _portfolioTargetSiblingUniverseIds(
        activeTargets,
      );
      if (siblingUniverseIds.isNotEmpty &&
          (destinationPortfolioId == null || destinationGroupId == null)) {
        throw const PortfolioRemovalException(
          PortfolioRemovalFailureReason.transferTargetRequired,
        );
      }
      if (destinationPortfolioId != null && destinationGroupId != null) {
        await _requireActiveGroup(destinationPortfolioId, destinationGroupId);
      }
      for (final target in activeTargets) {
        final destinationTarget = destinationPortfolioId == null
            ? null
            : await (_db.select(_db.portfolioAllocationTargets)..where(
                    (table) =>
                        table.universeId.equals(target.universeId) &
                        table.portfolioId.equals(destinationPortfolioId) &
                        table.deletedAt.isNull(),
                  ))
                  .getSingleOrNull();
        final targetHasSiblings = siblingUniverseIds.contains(
          target.universeId,
        );
        if (targetHasSiblings && destinationTarget == null) {
          throw const PortfolioRemovalException(
            PortfolioRemovalFailureReason.transferTargetInvalid,
          );
        }
        if (targetHasSiblings && destinationTarget != null) {
          await (_db.update(
            _db.portfolioAllocationTargets,
          )..where((table) => table.id.equals(destinationTarget.id))).write(
            PortfolioAllocationTargetsCompanion(
              targetWeightBps: Value(
                destinationTarget.targetWeightBps + target.targetWeightBps,
              ),
              updatedAt: Value(stamp.now),
              updatedByDevice: Value(stamp.deviceId),
              hlc: Value(stamp.hlc),
            ),
          );
          await _outbox.enqueue(
            table: portfolioTargetsTable,
            rowId: destinationTarget.id,
          );
        }
      }
      await _tombstonePortfolioTargets(portfolio.id, stamp);
      await _tombstonePortfolioRow(portfolio.id, stamp);
      await _tombstoneStrategies(portfolio.id, stamp);
      await _tombstoneGroups(portfolio.id, stamp);
      if (destinationPortfolioId != null && destinationGroupId != null) {
        await _transferAssignments(
          sourcePortfolioId: portfolio.id,
          destinationPortfolioId: destinationPortfolioId,
          destinationGroupId: destinationGroupId,
          stamp: stamp,
        );
      } else {
        await _tombstoneAssignments(portfolio.id, stamp);
      }
      await _outbox.enqueue(table: portfoliosTable, rowId: portfolio.id);
    });
  }

  /// Transfers a capital strategy into a sibling and removes its aggregate in
  /// one transaction.
  ///
  /// Target weight and capital assignments move to the selected destination.
  /// Overlays mounted on the source group are removed with their host. The
  /// final capital owner is protected because a portfolio without a rebalance
  /// group is not a valid aggregate.
  Future<void> removeCapitalStrategy(
    PortfolioRebalanceGroup group, {
    String? destinationGroupId,
  }) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      final activeGroups = await _activeGroupRows(group.portfolioId);
      final activeGroup = activeGroups
          .where((row) => row.id == group.id)
          .firstOrNull;
      if (activeGroup == null) {
        throw const PortfolioRemovalException(
          PortfolioRemovalFailureReason.strategyNotActive,
        );
      }
      if (activeGroups.length == 1) {
        throw const PortfolioRemovalException(
          PortfolioRemovalFailureReason.lastCapitalStrategy,
        );
      }
      if (destinationGroupId == null) {
        throw const PortfolioRemovalException(
          PortfolioRemovalFailureReason.transferTargetRequired,
        );
      }
      final destinationGroup = activeGroups
          .where((row) => row.id == destinationGroupId)
          .firstOrNull;
      if (destinationGroupId == group.id || destinationGroup == null) {
        throw const PortfolioRemovalException(
          PortfolioRemovalFailureReason.transferTargetInvalid,
        );
      }

      await (_db.update(
        _db.portfolioRebalanceGroups,
      )..where((table) => table.id.equals(destinationGroup.id))).write(
        PortfolioRebalanceGroupsCompanion(
          targetWeightBps: Value(
            destinationGroup.targetWeightBps + activeGroup.targetWeightBps,
          ),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: groupsTable, rowId: destinationGroup.id);
      await _transferAssignments(
        sourcePortfolioId: group.portfolioId,
        sourceGroupId: group.id,
        destinationPortfolioId: group.portfolioId,
        destinationGroupId: destinationGroup.id,
        stamp: stamp,
      );
      await _tombstoneStrategies(
        group.portfolioId,
        stamp,
        rebalanceGroupId: group.id,
      );
      await _tombstoneGroups(group.portfolioId, stamp, groupId: group.id);
    });
  }

  Future<void> removeStrategyOverlay(PortfolioStrategyConfig strategy) async {
    if (strategy.capitalRole != StrategyCapitalRole.overlay) {
      throw ArgumentError.value(
        strategy.capitalRole,
        'strategy',
        'must be an overlay strategy',
      );
    }
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      final affected = await _tombstoneStrategies(
        strategy.portfolioId,
        stamp,
        strategyId: strategy.id,
      );
      if (affected == 0) {
        throw const PortfolioRemovalException(
          PortfolioRemovalFailureReason.strategyNotActive,
        );
      }
    });
  }

  Future<void> _tombstonePortfolioRow(String portfolioId, MutationStamp stamp) {
    return (_db.update(
      _db.investmentPortfolios,
    )..where((table) => table.id.equals(portfolioId))).write(
      InvestmentPortfoliosCompanion(
        deletedAt: Value(stamp.now),
        updatedAt: Value(stamp.now),
        updatedByDevice: Value(stamp.deviceId),
        hlc: Value(stamp.hlc),
      ),
    );
  }

  Future<Set<String>> _tombstonePortfolioTargets(
    String portfolioId,
    MutationStamp stamp,
  ) async {
    final rows =
        await (_db.select(_db.portfolioAllocationTargets)..where(
              (table) =>
                  table.portfolioId.equals(portfolioId) &
                  table.deletedAt.isNull(),
            ))
            .get();
    for (final row in rows) {
      await (_db.update(
        _db.portfolioAllocationTargets,
      )..where((table) => table.id.equals(row.id))).write(
        PortfolioAllocationTargetsCompanion(
          deletedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: portfolioTargetsTable, rowId: row.id);
    }
    return {for (final row in rows) row.universeId};
  }

  Future<int> _tombstoneStrategies(
    String portfolioId,
    MutationStamp stamp, {
    String? rebalanceGroupId,
    String? strategyId,
  }) async {
    final rows =
        await (_db.select(_db.portfolioStrategyConfigs)..where(
              (table) =>
                  table.portfolioId.equals(portfolioId) &
                  table.deletedAt.isNull() &
                  (rebalanceGroupId == null
                      ? const Constant(true)
                      : table.rebalanceGroupId.equals(rebalanceGroupId)) &
                  (strategyId == null
                      ? const Constant(true)
                      : table.id.equals(strategyId)),
            ))
            .get();
    for (final row in rows) {
      await (_db.update(
        _db.portfolioStrategyConfigs,
      )..where((table) => table.id.equals(row.id))).write(
        PortfolioStrategyConfigsCompanion(
          deletedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: strategiesTable, rowId: row.id);
    }
    return rows.length;
  }

  Future<void> _tombstoneGroups(
    String portfolioId,
    MutationStamp stamp, {
    String? groupId,
  }) async {
    final rows =
        await (_db.select(_db.portfolioRebalanceGroups)..where(
              (table) =>
                  table.portfolioId.equals(portfolioId) &
                  table.deletedAt.isNull() &
                  (groupId == null
                      ? const Constant(true)
                      : table.id.equals(groupId)),
            ))
            .get();
    for (final row in rows) {
      await (_db.update(
        _db.portfolioRebalanceGroups,
      )..where((table) => table.id.equals(row.id))).write(
        PortfolioRebalanceGroupsCompanion(
          deletedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: groupsTable, rowId: row.id);
    }
  }

  Future<void> _tombstoneAssignments(
    String portfolioId,
    MutationStamp stamp, {
    String? rebalanceGroupId,
  }) async {
    final rows =
        await (_db.select(_db.portfolioCapitalAssignments)..where(
              (table) =>
                  table.portfolioId.equals(portfolioId) &
                  table.deletedAt.isNull() &
                  (rebalanceGroupId == null
                      ? const Constant(true)
                      : table.rebalanceGroupId.equals(rebalanceGroupId)),
            ))
            .get();
    for (final row in rows) {
      await (_db.update(
        _db.portfolioCapitalAssignments,
      )..where((table) => table.id.equals(row.id))).write(
        PortfolioCapitalAssignmentsCompanion(
          deletedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: assignmentsTable, rowId: row.id);
    }
  }

  Future<Set<String>> _portfolioTargetSiblingUniverseIds(
    List<PortfolioAllocationTargetRow> targets,
  ) async {
    final universeIds = <String>{};
    for (final target in targets) {
      final count =
          await (_db.selectOnly(_db.portfolioAllocationTargets)
                ..addColumns([_db.portfolioAllocationTargets.id.count()])
                ..where(
                  _db.portfolioAllocationTargets.universeId.equals(
                        target.universeId,
                      ) &
                      _db.portfolioAllocationTargets.deletedAt.isNull(),
                ))
              .map(
                (row) =>
                    row.read(_db.portfolioAllocationTargets.id.count()) ?? 0,
              )
              .getSingle();
      if (count > 1) universeIds.add(target.universeId);
    }
    return universeIds;
  }

  Future<void> _transferAssignments({
    required String sourcePortfolioId,
    String? sourceGroupId,
    required String destinationPortfolioId,
    required String destinationGroupId,
    required MutationStamp stamp,
  }) async {
    final rows =
        await (_db.select(_db.portfolioCapitalAssignments)..where(
              (table) =>
                  table.portfolioId.equals(sourcePortfolioId) &
                  table.deletedAt.isNull() &
                  table.unassignedAt.isNull() &
                  (sourceGroupId == null
                      ? const Constant(true)
                      : table.rebalanceGroupId.equals(sourceGroupId)),
            ))
            .get();
    for (final row in rows) {
      await (_db.update(
        _db.portfolioCapitalAssignments,
      )..where((table) => table.id.equals(row.id))).write(
        PortfolioCapitalAssignmentsCompanion(
          unassignedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: assignmentsTable, rowId: row.id);
      final transferred = PortfolioCapitalAssignment(
        id: _uuid.v4(),
        portfolioId: destinationPortfolioId,
        rebalanceGroupId: destinationGroupId,
        sourceKind: portfolioCapitalSourceKindFromWire(row.sourceKind),
        sourceId: row.sourceId,
        quantity: row.quantity,
        amount: row.amount,
        currency: row.currency,
        assignedAt: stamp.now,
        sync: _syncFromStamp(stamp),
      );
      await _db
          .into(_db.portfolioCapitalAssignments)
          .insert(_assignmentCompanion(transferred));
      await _outbox.enqueue(table: assignmentsTable, rowId: transferred.id);
    }
  }
}
