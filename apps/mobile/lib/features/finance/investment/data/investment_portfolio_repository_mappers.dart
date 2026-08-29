part of 'investment_portfolio_repository.dart';

InvestmentPortfoliosCompanion _portfolioCompanion(
  InvestmentPortfolio portfolio,
) {
  return InvestmentPortfoliosCompanion.insert(
    id: portfolio.id,
    name: portfolio.name,
    baseCurrency: Value(portfolio.baseCurrency),
    goalId: Value(portfolio.goalId),
    color: Value(portfolio.color),
    createdAt: portfolio.createdAt,
    archived: Value(portfolio.archived),
    ownerUserId: portfolio.sync.ownerUserId,
    updatedAt: portfolio.sync.updatedAt,
    updatedByDevice: portfolio.sync.updatedByDevice,
    hlc: portfolio.sync.hlc,
    deletedAt: Value(portfolio.sync.deletedAt),
  );
}

RebalanceUniversesCompanion _universeCompanion(RebalanceUniverse universe) {
  return RebalanceUniversesCompanion.insert(
    id: universe.id,
    name: universe.name,
    baseCurrency: universe.baseCurrency,
    createdAt: universe.createdAt,
    archived: Value(universe.archived),
    ownerUserId: universe.sync.ownerUserId,
    updatedAt: universe.sync.updatedAt,
    updatedByDevice: universe.sync.updatedByDevice,
    hlc: universe.sync.hlc,
    deletedAt: Value(universe.sync.deletedAt),
  );
}

PortfolioAllocationTargetsCompanion _portfolioTargetCompanion(
  PortfolioAllocationTarget target,
) {
  return PortfolioAllocationTargetsCompanion.insert(
    id: target.id,
    universeId: target.universeId,
    portfolioId: target.portfolioId,
    targetWeightBps: target.targetWeightBps,
    driftBandBps: target.driftBandBps,
    transferPolicy: target.transferPolicy.name,
    ownerUserId: target.sync.ownerUserId,
    updatedAt: target.sync.updatedAt,
    updatedByDevice: target.sync.updatedByDevice,
    hlc: target.sync.hlc,
    deletedAt: Value(target.sync.deletedAt),
  );
}

PortfolioRebalanceGroupsCompanion _groupCompanion(
  PortfolioRebalanceGroup group,
) {
  return PortfolioRebalanceGroupsCompanion.insert(
    id: group.id,
    portfolioId: group.portfolioId,
    name: group.name,
    strategyKind: group.strategyKind.wire,
    targetWeightBps: group.targetWeightBps,
    driftBandBps: group.driftBandBps,
    transferPolicy: group.transferPolicy.name,
    internalTargetJson: jsonEncode(group.internalTarget.toJson()),
    createdAt: group.createdAt,
    archived: Value(group.archived),
    ownerUserId: group.sync.ownerUserId,
    updatedAt: group.sync.updatedAt,
    updatedByDevice: group.sync.updatedByDevice,
    hlc: group.sync.hlc,
    deletedAt: Value(group.sync.deletedAt),
  );
}

PortfolioCapitalAssignmentsCompanion _assignmentCompanion(
  PortfolioCapitalAssignment assignment,
) {
  return PortfolioCapitalAssignmentsCompanion.insert(
    id: assignment.id,
    portfolioId: assignment.portfolioId,
    rebalanceGroupId: assignment.rebalanceGroupId,
    sourceKind: assignment.sourceKind.name,
    sourceId: assignment.sourceId,
    quantity: Value(assignment.quantity),
    amount: Value(assignment.amount),
    currency: Value(assignment.currency),
    assignedAt: assignment.assignedAt,
    unassignedAt: Value(assignment.unassignedAt),
    ownerUserId: assignment.sync.ownerUserId,
    updatedAt: assignment.sync.updatedAt,
    updatedByDevice: assignment.sync.updatedByDevice,
    hlc: assignment.sync.hlc,
    deletedAt: Value(assignment.sync.deletedAt),
  );
}

InvestmentPortfolio _portfolioFromRow(InvestmentPortfolioRow row) {
  return InvestmentPortfolio(
    id: row.id,
    name: row.name,
    baseCurrency: row.baseCurrency,
    goalId: row.goalId,
    color: row.color,
    createdAt: row.createdAt,
    archived: row.archived,
    sync: _syncFromRow(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );
}

RebalanceUniverse _universeFromRow(RebalanceUniverseRow row) {
  return RebalanceUniverse(
    id: row.id,
    name: row.name,
    baseCurrency: row.baseCurrency,
    createdAt: row.createdAt,
    archived: row.archived,
    sync: _syncFromRow(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );
}

PortfolioAllocationTarget _portfolioTargetFromRow(
  PortfolioAllocationTargetRow row,
) {
  final target = PortfolioAllocationTarget(
    id: row.id,
    universeId: row.universeId,
    portfolioId: row.portfolioId,
    targetWeightBps: row.targetWeightBps,
    driftBandBps: row.driftBandBps,
    transferPolicy: groupTransferPolicyFromWire(row.transferPolicy),
    sync: _syncFromRow(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );
  if (!target.isValid) {
    throw FormatException('${row.id} portfolio target is invalid.');
  }
  return target;
}

PortfolioRebalanceGroup _groupFromRow(PortfolioRebalanceGroupRow row) {
  final decoded = jsonDecode(row.internalTargetJson);
  if (decoded is! Map) {
    throw FormatException('${row.id} target must be a JSON object.');
  }
  return PortfolioRebalanceGroup(
    id: row.id,
    portfolioId: row.portfolioId,
    name: row.name,
    strategyKind: portfolioStrategyKindFromWire(row.strategyKind),
    targetWeightBps: row.targetWeightBps,
    driftBandBps: row.driftBandBps,
    transferPolicy: groupTransferPolicyFromWire(row.transferPolicy),
    internalTarget: TargetAllocation.fromJson(
      Map<String, dynamic>.from(decoded),
    ),
    createdAt: row.createdAt,
    archived: row.archived,
    sync: _syncFromRow(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );
}

PortfolioCapitalAssignment _assignmentFromRow(
  PortfolioCapitalAssignmentRow row,
) {
  final assignment = PortfolioCapitalAssignment(
    id: row.id,
    portfolioId: row.portfolioId,
    rebalanceGroupId: row.rebalanceGroupId,
    sourceKind: portfolioCapitalSourceKindFromWire(row.sourceKind),
    sourceId: row.sourceId,
    quantity: row.quantity,
    amount: row.amount,
    currency: row.currency,
    assignedAt: row.assignedAt,
    unassignedAt: row.unassignedAt,
    sync: _syncFromRow(
      ownerUserId: row.ownerUserId,
      updatedAt: row.updatedAt,
      updatedByDevice: row.updatedByDevice,
      hlc: row.hlc,
    ),
  );
  assignment.validate();
  return assignment;
}

String defaultRebalanceUniverseId(String ownerUserId) =>
    '$ownerUserId::rebalance-universe::default';

String portfolioAllocationTargetId(String universeId, String portfolioId) =>
    '$universeId::portfolio::$portfolioId';

SyncMeta _syncFromStamp(MutationStamp stamp) => SyncMeta(
  ownerUserId: stamp.ownerUserId,
  updatedAt: stamp.now,
  updatedByDevice: stamp.deviceId,
  hlc: stamp.hlc,
);

SyncMeta _syncFromRow({
  required String ownerUserId,
  required DateTime updatedAt,
  required String updatedByDevice,
  required Hlc hlc,
}) => SyncMeta(
  ownerUserId: ownerUserId,
  updatedAt: updatedAt,
  updatedByDevice: updatedByDevice,
  hlc: hlc,
);

String? _nullableTrimmed(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
