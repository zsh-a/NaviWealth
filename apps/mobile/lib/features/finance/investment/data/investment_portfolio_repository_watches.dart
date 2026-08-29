part of 'investment_portfolio_repository.dart';

mixin InvestmentPortfolioRepositoryWatchMixin {
  AppDatabase get _db;

  PortfolioStrategyConfig _strategyFromRow(PortfolioStrategyConfigRow row);

  PortfolioStrategyTemplate _strategyTemplateFromRow(
    PortfolioStrategyTemplateRow row,
  );

  Stream<List<InvestmentPortfolio>> watchActive(String ownerUserId) {
    final query = _db.select(_db.investmentPortfolios)
      ..where((table) => table.ownerUserId.equals(ownerUserId))
      ..where((table) => table.deletedAt.isNull())
      ..where((table) => table.archived.equals(false))
      ..orderBy([
        (table) => OrderingTerm.asc(table.createdAt),
        (table) => OrderingTerm.asc(table.name),
      ]);
    return query.watch().map(
      (rows) => rows.map(_portfolioFromRow).toList(growable: false),
    );
  }

  Stream<List<PortfolioStrategyConfig>> watchStrategies(String ownerUserId) {
    final query = _db.select(_db.portfolioStrategyConfigs)
      ..where((table) => table.ownerUserId.equals(ownerUserId))
      ..where((table) => table.deletedAt.isNull())
      ..orderBy([(table) => OrderingTerm.asc(table.kind)]);
    return query.watch().map(
      (rows) => rows.map(_strategyFromRow).toList(growable: false),
    );
  }

  Stream<List<PortfolioStrategyTemplate>> watchCustomStrategyTemplates(
    String ownerUserId,
  ) {
    final query = _db.select(_db.portfolioStrategyTemplates)
      ..where((table) => table.ownerUserId.equals(ownerUserId))
      ..where((table) => table.deletedAt.isNull())
      ..where((table) => table.archived.equals(false))
      ..orderBy([(table) => OrderingTerm.asc(table.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_strategyTemplateFromRow).toList(growable: false),
    );
  }

  Stream<List<RebalanceUniverse>> watchUniverses(String ownerUserId) {
    final query = _db.select(_db.rebalanceUniverses)
      ..where((table) => table.ownerUserId.equals(ownerUserId))
      ..where((table) => table.deletedAt.isNull())
      ..where((table) => table.archived.equals(false))
      ..orderBy([(table) => OrderingTerm.asc(table.createdAt)]);
    return query.watch().map(
      (rows) => rows.map(_universeFromRow).toList(growable: false),
    );
  }

  Stream<List<PortfolioAllocationTarget>> watchPortfolioTargets(
    String ownerUserId,
  ) {
    final query = _db.select(_db.portfolioAllocationTargets)
      ..where((table) => table.ownerUserId.equals(ownerUserId))
      ..where((table) => table.deletedAt.isNull())
      ..orderBy([
        (table) => OrderingTerm.asc(table.universeId),
        (table) => OrderingTerm.asc(table.portfolioId),
      ]);
    return query.watch().map(
      (rows) => rows.map(_portfolioTargetFromRow).toList(growable: false),
    );
  }

  Stream<List<PortfolioRebalanceGroup>> watchGroups(String ownerUserId) {
    final query = _db.select(_db.portfolioRebalanceGroups)
      ..where((table) => table.ownerUserId.equals(ownerUserId))
      ..where((table) => table.deletedAt.isNull())
      ..where((table) => table.archived.equals(false))
      ..orderBy([
        (table) => OrderingTerm.asc(table.createdAt),
        (table) => OrderingTerm.asc(table.name),
      ]);
    return query.watch().map(
      (rows) => rows.map(_groupFromRow).toList(growable: false),
    );
  }

  Stream<List<PortfolioCapitalAssignment>> watchAssignments(
    String ownerUserId,
  ) {
    final query = _db.select(_db.portfolioCapitalAssignments)
      ..where((table) => table.ownerUserId.equals(ownerUserId))
      ..where((table) => table.deletedAt.isNull())
      ..where((table) => table.unassignedAt.isNull());
    return query.watch().map(
      (rows) => rows.map(_assignmentFromRow).toList(growable: false),
    );
  }

  Stream<List<PortfolioCapitalAssignment>> watchAssignmentHistory(
    String ownerUserId,
  ) {
    final query = _db.select(_db.portfolioCapitalAssignments)
      ..where((table) => table.ownerUserId.equals(ownerUserId))
      ..where((table) => table.deletedAt.isNull())
      ..orderBy([
        (table) => OrderingTerm.asc(table.assignedAt),
        (table) => OrderingTerm.asc(table.id),
      ]);
    return query.watch().map(
      (rows) => rows.map(_assignmentFromRow).toList(growable: false),
    );
  }
}
