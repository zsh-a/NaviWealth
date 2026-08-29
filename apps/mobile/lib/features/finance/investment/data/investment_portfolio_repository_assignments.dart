part of 'investment_portfolio_repository.dart';

mixin InvestmentPortfolioRepositoryAssignmentMixin {
  AppDatabase get _db;
  OutboxStore get _outbox;
  MutationStamper get _stamper;

  Future<void> _requireActiveGroup(String portfolioId, String groupId);

  Future<PortfolioCapitalAssignment> assignWholeLot({
    required String lotId,
    required String portfolioId,
    required String rebalanceGroupId,
  }) {
    return assignCapital(
      portfolioId: portfolioId,
      rebalanceGroupId: rebalanceGroupId,
      sourceKind: PortfolioCapitalSourceKind.lot,
      sourceId: lotId,
    );
  }

  Future<PortfolioCapitalAssignment> assignLotQuantity({
    required String lotId,
    required Decimal quantity,
    required Decimal availableQuantity,
    required String portfolioId,
    required String rebalanceGroupId,
  }) {
    return assignCapital(
      portfolioId: portfolioId,
      rebalanceGroupId: rebalanceGroupId,
      sourceKind: PortfolioCapitalSourceKind.lot,
      sourceId: lotId,
      quantity: quantity,
      sourceCapacity: availableQuantity,
    );
  }

  Future<PortfolioCapitalAssignment> assignCash({
    required String accountId,
    required Decimal amount,
    required Decimal availableAmount,
    required String currency,
    required String portfolioId,
    required String rebalanceGroupId,
  }) {
    return assignCapital(
      portfolioId: portfolioId,
      rebalanceGroupId: rebalanceGroupId,
      sourceKind: PortfolioCapitalSourceKind.cashAccount,
      sourceId: accountId,
      amount: amount,
      currency: currency,
      sourceCapacity: availableAmount,
    );
  }

  Future<PortfolioCapitalAssignment> assignCapital({
    required String portfolioId,
    required String rebalanceGroupId,
    required PortfolioCapitalSourceKind sourceKind,
    required String sourceId,
    Decimal? quantity,
    Decimal? amount,
    String? currency,
    Decimal? sourceCapacity,
  }) async {
    await _requireActiveGroup(portfolioId, rebalanceGroupId);
    final stamp = await _stamper.stamp();
    final normalizedSourceId = sourceId.trim();
    final assignment = PortfolioCapitalAssignment(
      id: _uuid.v4(),
      portfolioId: portfolioId,
      rebalanceGroupId: rebalanceGroupId,
      sourceKind: sourceKind,
      sourceId: normalizedSourceId,
      quantity: quantity,
      amount: amount,
      currency: currency?.trim().toUpperCase(),
      assignedAt: stamp.now,
      sync: _syncFromStamp(stamp),
    );
    assignment.validate();
    await _db.transaction(() async {
      await _validateAssignmentCapacity(
        assignment,
        sourceCapacity: sourceCapacity,
      );
      await _db
          .into(_db.portfolioCapitalAssignments)
          .insert(_assignmentCompanion(assignment));
      await _outbox.enqueue(table: assignmentsTable, rowId: assignment.id);
    });
    return assignment;
  }

  /// Ends [assignment] and creates its replacement as one auditable mutation.
  ///
  /// Sync observers can never see the capital without an owner between the two
  /// writes because both rows and both outbox entries commit together.
  Future<PortfolioCapitalAssignment> moveCapitalAssignment({
    required PortfolioCapitalAssignment assignment,
    required String portfolioId,
    required String rebalanceGroupId,
    Decimal? sourceCapacity,
  }) async {
    if (!assignment.isActive) {
      throw StateError('Only an active capital assignment can be moved.');
    }
    await _requireActiveGroup(portfolioId, rebalanceGroupId);
    final stamp = await _stamper.stamp();
    final replacement = PortfolioCapitalAssignment(
      id: _uuid.v4(),
      portfolioId: portfolioId,
      rebalanceGroupId: rebalanceGroupId,
      sourceKind: assignment.sourceKind,
      sourceId: assignment.sourceId,
      quantity: assignment.quantity,
      amount: assignment.amount,
      currency: assignment.currency,
      assignedAt: stamp.now,
      sync: _syncFromStamp(stamp),
    );
    replacement.validate();
    await _db.transaction(() async {
      final changed =
          await (_db.update(_db.portfolioCapitalAssignments)..where(
                (table) =>
                    table.id.equals(assignment.id) &
                    table.deletedAt.isNull() &
                    table.unassignedAt.isNull(),
              ))
              .write(
                PortfolioCapitalAssignmentsCompanion(
                  unassignedAt: Value(stamp.now),
                  updatedAt: Value(stamp.now),
                  updatedByDevice: Value(stamp.deviceId),
                  hlc: Value(stamp.hlc),
                ),
              );
      if (changed != 1) {
        throw StateError(
          'Capital assignment changed before it could be moved.',
        );
      }
      await _validateAssignmentCapacity(
        replacement,
        sourceCapacity: sourceCapacity,
        excludingAssignmentId: assignment.id,
      );
      await _db
          .into(_db.portfolioCapitalAssignments)
          .insert(_assignmentCompanion(replacement));
      await _outbox.enqueue(table: assignmentsTable, rowId: assignment.id);
      await _outbox.enqueue(table: assignmentsTable, rowId: replacement.id);
    });
    return replacement;
  }

  Future<void> unassignCapital(PortfolioCapitalAssignment assignment) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.portfolioCapitalAssignments,
      )..where((table) => table.id.equals(assignment.id))).write(
        PortfolioCapitalAssignmentsCompanion(
          unassignedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: assignmentsTable, rowId: assignment.id);
    });
  }

  Future<void> _validateAssignmentCapacity(
    PortfolioCapitalAssignment assignment, {
    Decimal? sourceCapacity,
    String? excludingAssignmentId,
  }) async {
    final rows =
        await (_db.select(_db.portfolioCapitalAssignments)..where(
              (table) =>
                  table.sourceKind.equals(assignment.sourceKind.name) &
                  table.sourceId.equals(assignment.sourceId) &
                  table.deletedAt.isNull() &
                  table.unassignedAt.isNull() &
                  (excludingAssignmentId == null
                      ? const Constant(true)
                      : table.id.equals(excludingAssignmentId).not()),
            ))
            .get();
    switch (assignment.sourceKind) {
      case PortfolioCapitalSourceKind.lot:
        if (assignment.isWholeLot && rows.isNotEmpty ||
            rows.any((row) => row.quantity == null)) {
          throw StateError(
            'A whole-lot assignment cannot overlap another capital owner.',
          );
        }
        if (assignment.quantity case final quantity?
            when sourceCapacity != null) {
          final assigned = rows.fold<Decimal>(
            quantity,
            (sum, row) => sum + (row.quantity ?? sourceCapacity),
          );
          if (assigned > sourceCapacity) {
            throw StateError(
              'Lot assignments exceed the available open quantity.',
            );
          }
        }
      case PortfolioCapitalSourceKind.cashAccount:
        if (sourceCapacity == null) return;
        final assigned = rows
            .where((row) => row.currency == assignment.currency)
            .fold<Decimal>(
              assignment.amount!,
              (sum, row) => sum + (row.amount ?? Decimal.zero),
            );
        if (assigned > sourceCapacity) {
          throw StateError('Cash assignments exceed the available balance.');
        }
    }
  }
}
