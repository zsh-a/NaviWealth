import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';
import 'package:uuid/uuid.dart';

import '../domain/models/investment_portfolio.dart';
import '../domain/models/portfolio_capital_assignment.dart';
import '../domain/strategy/portfolio_strategy.dart';

const _uuid = Uuid();

class InvestmentPortfolioRepository {
  InvestmentPortfolioRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    PortfolioStrategyRegistry? strategyRegistry,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _strategyRegistry =
           strategyRegistry ?? PortfolioStrategyRegistry.standard();

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final PortfolioStrategyRegistry _strategyRegistry;

  static const portfoliosTable = 'investment_portfolios';
  static const strategiesTable = 'portfolio_strategy_configs';
  static const groupsTable = 'portfolio_rebalance_groups';
  static const assignmentsTable = 'portfolio_capital_assignments';

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
      ..where((table) => table.deletedAt.isNull());
    return query.watch().map(
      (rows) => rows.map(_assignmentFromRow).toList(growable: false),
    );
  }

  /// Creates one complete, valid portfolio aggregate in a single transaction.
  ///
  /// The first strategy owns the default 100% rebalance group. Additional
  /// owner or overlay modules can be attached independently afterwards.
  Future<InvestmentPortfolio> create({
    required String name,
    required PortfolioStrategyKind initialStrategyKind,
    String? baseCurrency,
    String? goalId,
    String? color,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final definition = _strategyRegistry.definitionFor(initialStrategyKind);
    if (definition == null) {
      throw ArgumentError.value(
        initialStrategyKind.wire,
        'initialStrategyKind',
        'must be registered',
      );
    }
    final stamp = await _stamper.stamp();
    final portfolioId = _uuid.v4();
    final groupId = portfolioRebalanceGroupId(portfolioId, initialStrategyKind);
    final strategyId = portfolioStrategyConfigId(
      portfolioId,
      initialStrategyKind,
    );
    final portfolio = InvestmentPortfolio(
      id: portfolioId,
      name: normalizedName,
      baseCurrency: _nullableTrimmed(baseCurrency)?.toUpperCase(),
      goalId: _nullableTrimmed(goalId),
      color: _nullableTrimmed(color),
      createdAt: stamp.now,
      archived: false,
      sync: _syncFromStamp(stamp),
    );
    final group = PortfolioRebalanceGroup(
      id: groupId,
      portfolioId: portfolioId,
      name: _defaultGroupName(initialStrategyKind),
      strategyKind: initialStrategyKind,
      targetWeightBps: 10000,
      driftBandBps: 500,
      transferPolicy: _defaultTransferPolicy(initialStrategyKind),
      internalTarget: _defaultTarget(initialStrategyKind),
      createdAt: stamp.now,
      archived: false,
      sync: _syncFromStamp(stamp),
    );
    final strategy = PortfolioStrategyConfig(
      id: strategyId,
      portfolioId: portfolioId,
      kind: initialStrategyKind,
      schemaVersion: definition.currentSchemaVersion,
      enabled: true,
      capitalRole: definition.defaultCapitalRole,
      rebalanceGroupId: groupId,
      settings: definition.defaultSettings,
      sync: _syncFromStamp(stamp),
    );

    await _db.transaction(() async {
      await _db
          .into(_db.investmentPortfolios)
          .insert(_portfolioCompanion(portfolio));
      await _db
          .into(_db.portfolioRebalanceGroups)
          .insert(_groupCompanion(group));
      await _db
          .into(_db.portfolioStrategyConfigs)
          .insert(_strategyCompanion(strategy));
      await _outbox.enqueue(table: portfoliosTable, rowId: portfolio.id);
      await _outbox.enqueue(table: groupsTable, rowId: group.id);
      await _outbox.enqueue(table: strategiesTable, rowId: strategy.id);
    });
    return portfolio;
  }

  Future<InvestmentPortfolio> update(InvestmentPortfolio portfolio) async {
    final normalizedName = portfolio.name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(portfolio.name, 'name', 'must not be empty');
    }
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.investmentPortfolios,
      )..where((table) => table.id.equals(portfolio.id))).write(
        InvestmentPortfoliosCompanion(
          name: Value(normalizedName),
          baseCurrency: Value(portfolio.baseCurrency),
          goalId: Value(portfolio.goalId),
          color: Value(portfolio.color),
          archived: Value(portfolio.archived),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: portfoliosTable, rowId: portfolio.id);
    });
    return portfolio.copyWith(
      name: normalizedName,
      sync: _syncFromStamp(stamp),
    );
  }

  Future<PortfolioStrategyConfig> updateStrategy(
    PortfolioStrategyConfig strategy,
  ) async {
    final definition = _strategyRegistry.definitionFor(strategy.kind);
    final issues = definition?.validate(strategy.settings) ?? const <String>[];
    if (issues.isNotEmpty) {
      throw ArgumentError.value(issues, 'strategy', issues.join('; '));
    }
    final stamp = await _stamper.stamp();
    final updated = strategy.copyWith(sync: _syncFromStamp(stamp));
    await _db.transaction(() async {
      await (_db.update(_db.portfolioStrategyConfigs)
            ..where((table) => table.id.equals(strategy.id)))
          .write(_strategyCompanion(updated));
      await _outbox.enqueue(table: strategiesTable, rowId: strategy.id);
    });
    return updated;
  }

  /// Adds a capital-owning strategy module and its group atomically.
  ///
  /// Existing group weights are redistributed evenly with the new group so
  /// the aggregate remains valid at every observable database state.
  Future<PortfolioRebalanceGroup> addCapitalStrategy({
    required String portfolioId,
    required PortfolioStrategyKind kind,
    String? groupName,
  }) async {
    final definition = _strategyRegistry.definitionFor(kind);
    if (definition == null) {
      throw ArgumentError.value(kind.wire, 'kind', 'must be registered');
    }
    final stamp = await _stamper.stamp();
    final groupId = portfolioRebalanceGroupId(portfolioId, kind);
    final strategyId = portfolioStrategyConfigId(portfolioId, kind);
    late final PortfolioRebalanceGroup created;
    await _db.transaction(() async {
      final existing = await _activeGroupRows(portfolioId);
      if (existing.any((row) => row.id == groupId)) {
        throw StateError('${kind.wire} is already a capital strategy.');
      }
      final weights = _equalWeights(existing.length + 1);
      for (var index = 0; index < existing.length; index++) {
        await _writeGroupWeight(existing[index].id, weights[index], stamp);
      }
      created = PortfolioRebalanceGroup(
        id: groupId,
        portfolioId: portfolioId,
        name: _nullableTrimmed(groupName) ?? _defaultGroupName(kind),
        strategyKind: kind,
        targetWeightBps: weights.last,
        driftBandBps: 500,
        transferPolicy: _defaultTransferPolicy(kind),
        internalTarget: _defaultTarget(kind),
        createdAt: stamp.now,
        archived: false,
        sync: _syncFromStamp(stamp),
      );
      final strategy = PortfolioStrategyConfig(
        id: strategyId,
        portfolioId: portfolioId,
        kind: kind,
        schemaVersion: definition.currentSchemaVersion,
        enabled: true,
        capitalRole: StrategyCapitalRole.owner,
        rebalanceGroupId: groupId,
        settings: definition.defaultSettings,
        sync: _syncFromStamp(stamp),
      );
      await _db
          .into(_db.portfolioRebalanceGroups)
          .insert(_groupCompanion(created));
      await _db
          .into(_db.portfolioStrategyConfigs)
          .insert(_strategyCompanion(strategy));
      await _outbox.enqueue(table: groupsTable, rowId: created.id);
      await _outbox.enqueue(table: strategiesTable, rowId: strategy.id);
    });
    return created;
  }

  /// Attaches a non-capital-owning module to an existing group.
  Future<PortfolioStrategyConfig> addStrategyOverlay({
    required String portfolioId,
    required String rebalanceGroupId,
    required PortfolioStrategyKind kind,
  }) async {
    final definition = _strategyRegistry.definitionFor(kind);
    if (definition == null) {
      throw ArgumentError.value(kind.wire, 'kind', 'must be registered');
    }
    await _requireActiveGroup(portfolioId, rebalanceGroupId);
    final stamp = await _stamper.stamp();
    final strategy = PortfolioStrategyConfig(
      id: portfolioStrategyConfigId(portfolioId, kind),
      portfolioId: portfolioId,
      kind: kind,
      schemaVersion: definition.currentSchemaVersion,
      enabled: true,
      capitalRole: StrategyCapitalRole.overlay,
      rebalanceGroupId: rebalanceGroupId,
      settings: definition.defaultSettings,
      sync: _syncFromStamp(stamp),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.portfolioStrategyConfigs)
          .insert(_strategyCompanion(strategy));
      await _outbox.enqueue(table: strategiesTable, rowId: strategy.id);
    });
    return strategy;
  }

  /// Changes one group target and proportionally redistributes the remainder.
  Future<void> setGroupTargetWeight({
    required String portfolioId,
    required String groupId,
    required int targetWeightBps,
  }) async {
    if (targetWeightBps < 0 || targetWeightBps > 10000) {
      throw ArgumentError.value(
        targetWeightBps,
        'targetWeightBps',
        'must be between 0 and 10000',
      );
    }
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      final rows = await _activeGroupRows(portfolioId);
      final selectedIndex = rows.indexWhere((row) => row.id == groupId);
      if (selectedIndex < 0) {
        throw StateError('Group $groupId is not active in $portfolioId.');
      }
      if (rows.length == 1 && targetWeightBps != 10000) {
        throw StateError('A single group must own 100% of portfolio capital.');
      }
      final weights = _redistributeWeights(
        rows: rows,
        selectedIndex: selectedIndex,
        selectedWeight: targetWeightBps,
      );
      for (var index = 0; index < rows.length; index++) {
        await _writeGroupWeight(rows[index].id, weights[index], stamp);
      }
    });
  }

  Future<PortfolioRebalanceGroup> updateGroup(
    PortfolioRebalanceGroup group,
  ) async {
    if (!group.hasValidWeight || !group.internalTarget.isValid) {
      throw ArgumentError.value(group, 'group', 'contains invalid weights');
    }
    final activeGroups = await _activeGroupRows(group.portfolioId);
    final aggregateWeight = activeGroups.fold<int>(
      0,
      (sum, row) =>
          sum +
          (row.id == group.id ? group.targetWeightBps : row.targetWeightBps),
    );
    if (aggregateWeight != 10000) {
      throw ArgumentError.value(
        group.targetWeightBps,
        'targetWeightBps',
        'use setGroupTargetWeight to preserve the 100% aggregate',
      );
    }
    final stamp = await _stamper.stamp();
    final updated = group.copyWith(sync: _syncFromStamp(stamp));
    await _db.transaction(() async {
      await (_db.update(_db.portfolioRebalanceGroups)
            ..where((table) => table.id.equals(group.id)))
          .write(_groupCompanion(updated));
      await _outbox.enqueue(table: groupsTable, rowId: group.id);
    });
    return updated;
  }

  Future<void> remove(InvestmentPortfolio portfolio) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await _tombstonePortfolioRow(portfolio.id, stamp);
      await _tombstoneStrategies(portfolio.id, stamp);
      await _tombstoneGroups(portfolio.id, stamp);
      await _tombstoneAssignments(portfolio.id, stamp);
      await _outbox.enqueue(table: portfoliosTable, rowId: portfolio.id);
    });
  }

  Future<void> assignWholeLot({
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

  Future<void> assignLotQuantity({
    required String lotId,
    required Decimal quantity,
    required String portfolioId,
    required String rebalanceGroupId,
  }) {
    return assignCapital(
      portfolioId: portfolioId,
      rebalanceGroupId: rebalanceGroupId,
      sourceKind: PortfolioCapitalSourceKind.lot,
      sourceId: lotId,
      quantity: quantity,
    );
  }

  Future<void> assignCash({
    required String accountId,
    required Decimal amount,
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
    );
  }

  Future<void> assignCapital({
    required String portfolioId,
    required String rebalanceGroupId,
    required PortfolioCapitalSourceKind sourceKind,
    required String sourceId,
    Decimal? quantity,
    Decimal? amount,
    String? currency,
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
      if (sourceKind == PortfolioCapitalSourceKind.lot) {
        final existing =
            await (_db.select(_db.portfolioCapitalAssignments)..where(
                  (table) =>
                      table.sourceKind.equals(
                        PortfolioCapitalSourceKind.lot.name,
                      ) &
                      table.sourceId.equals(normalizedSourceId) &
                      table.deletedAt.isNull(),
                ))
                .get();
        if (quantity == null && existing.isNotEmpty ||
            existing.any((row) => row.quantity == null)) {
          throw StateError(
            'A whole-lot assignment cannot overlap another capital owner.',
          );
        }
      }
      await _db
          .into(_db.portfolioCapitalAssignments)
          .insert(_assignmentCompanion(assignment));
      await _outbox.enqueue(table: assignmentsTable, rowId: assignment.id);
    });
  }

  Future<void> unassignCapital(PortfolioCapitalAssignment assignment) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.portfolioCapitalAssignments,
      )..where((table) => table.id.equals(assignment.id))).write(
        PortfolioCapitalAssignmentsCompanion(
          deletedAt: Value(stamp.now),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: assignmentsTable, rowId: assignment.id);
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

  Future<void> _tombstoneStrategies(
    String portfolioId,
    MutationStamp stamp,
  ) async {
    final rows =
        await (_db.select(_db.portfolioStrategyConfigs)..where(
              (table) =>
                  table.portfolioId.equals(portfolioId) &
                  table.deletedAt.isNull(),
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
  }

  Future<void> _tombstoneGroups(String portfolioId, MutationStamp stamp) async {
    final rows =
        await (_db.select(_db.portfolioRebalanceGroups)..where(
              (table) =>
                  table.portfolioId.equals(portfolioId) &
                  table.deletedAt.isNull(),
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
    MutationStamp stamp,
  ) async {
    final rows =
        await (_db.select(_db.portfolioCapitalAssignments)..where(
              (table) =>
                  table.portfolioId.equals(portfolioId) &
                  table.deletedAt.isNull(),
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

  Future<List<PortfolioRebalanceGroupRow>> _activeGroupRows(
    String portfolioId,
  ) {
    return (_db.select(_db.portfolioRebalanceGroups)
          ..where(
            (table) =>
                table.portfolioId.equals(portfolioId) &
                table.deletedAt.isNull() &
                table.archived.equals(false),
          )
          ..orderBy([(table) => OrderingTerm.asc(table.createdAt)]))
        .get();
  }

  Future<void> _requireActiveGroup(String portfolioId, String groupId) async {
    final row =
        await (_db.select(_db.portfolioRebalanceGroups)..where(
              (table) =>
                  table.id.equals(groupId) &
                  table.portfolioId.equals(portfolioId) &
                  table.deletedAt.isNull() &
                  table.archived.equals(false),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw StateError('Group $groupId is not active in $portfolioId.');
    }
  }

  Future<void> _writeGroupWeight(
    String groupId,
    int targetWeightBps,
    MutationStamp stamp,
  ) async {
    await (_db.update(
      _db.portfolioRebalanceGroups,
    )..where((table) => table.id.equals(groupId))).write(
      PortfolioRebalanceGroupsCompanion(
        targetWeightBps: Value(targetWeightBps),
        updatedAt: Value(stamp.now),
        updatedByDevice: Value(stamp.deviceId),
        hlc: Value(stamp.hlc),
      ),
    );
    await _outbox.enqueue(table: groupsTable, rowId: groupId);
  }

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

  PortfolioStrategyConfigsCompanion _strategyCompanion(
    PortfolioStrategyConfig strategy,
  ) {
    return PortfolioStrategyConfigsCompanion.insert(
      id: strategy.id,
      portfolioId: strategy.portfolioId,
      kind: strategy.kind.wire,
      schemaVersion: strategy.schemaVersion,
      enabled: Value(strategy.enabled),
      capitalRole: strategy.capitalRole.name,
      rebalanceGroupId: Value(strategy.rebalanceGroupId),
      configJson: jsonEncode(
        _strategyRegistry.encode(strategy.kind, strategy.settings),
      ),
      ownerUserId: strategy.sync.ownerUserId,
      updatedAt: strategy.sync.updatedAt,
      updatedByDevice: strategy.sync.updatedByDevice,
      hlc: strategy.sync.hlc,
      deletedAt: Value(strategy.sync.deletedAt),
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

  PortfolioStrategyConfig _strategyFromRow(PortfolioStrategyConfigRow row) {
    final kind = portfolioStrategyKindFromWire(row.kind);
    final decoded = jsonDecode(row.configJson);
    if (decoded is! Map) {
      throw FormatException('${row.kind} config must be a JSON object.');
    }
    final payload = Map<String, Object?>.from(decoded);
    return PortfolioStrategyConfig(
      id: row.id,
      portfolioId: row.portfolioId,
      kind: kind,
      schemaVersion: row.schemaVersion,
      enabled: row.enabled,
      capitalRole: StrategyCapitalRole.values.byName(row.capitalRole),
      rebalanceGroupId: row.rebalanceGroupId,
      settings: _strategyRegistry.decode(
        kind: kind,
        schemaVersion: row.schemaVersion,
        payload: payload,
      ),
      sync: _syncFromRow(
        ownerUserId: row.ownerUserId,
        updatedAt: row.updatedAt,
        updatedByDevice: row.updatedByDevice,
        hlc: row.hlc,
      ),
    );
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
}

String portfolioStrategyConfigId(
  String portfolioId,
  PortfolioStrategyKind kind,
) => '$portfolioId::strategy::${kind.wire}';

String portfolioRebalanceGroupId(
  String portfolioId,
  PortfolioStrategyKind kind,
) => '$portfolioId::group::${kind.wire}';

String _defaultGroupName(PortfolioStrategyKind kind) {
  if (kind == PortfolioStrategyKind.indexCore) return 'Index core';
  if (kind == PortfolioStrategyKind.dividendIncome) return 'Dividend income';
  if (kind == PortfolioStrategyKind.optionsIncome) return 'Options collateral';
  return kind.wire;
}

GroupTransferPolicy _defaultTransferPolicy(PortfolioStrategyKind kind) {
  if (kind == PortfolioStrategyKind.dividendIncome) {
    return GroupTransferPolicy.inflowsOnly;
  }
  if (kind == PortfolioStrategyKind.optionsIncome) {
    return GroupTransferPolicy.isolated;
  }
  return GroupTransferPolicy.bidirectional;
}

TargetAllocation _defaultTarget(PortfolioStrategyKind kind) {
  if (kind == PortfolioStrategyKind.indexCore) {
    return const TargetAllocation(weights: {AssetCategory.etf: 1});
  }
  if (kind == PortfolioStrategyKind.dividendIncome) {
    return const TargetAllocation(
      weights: {AssetCategory.stock: 0.5, AssetCategory.etf: 0.5},
    );
  }
  if (kind == PortfolioStrategyKind.optionsIncome) {
    return const TargetAllocation(
      weights: {AssetCategory.stock: 0.4, AssetCategory.cash: 0.6},
    );
  }
  return const TargetAllocation(weights: {AssetCategory.etf: 1});
}

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

List<int> _equalWeights(int count) {
  if (count <= 0) throw ArgumentError.value(count, 'count', 'must be positive');
  final base = 10000 ~/ count;
  var remainder = 10000 - base * count;
  return List<int>.generate(count, (_) {
    if (remainder == 0) return base;
    remainder -= 1;
    return base + 1;
  }, growable: false);
}

List<int> _redistributeWeights({
  required List<PortfolioRebalanceGroupRow> rows,
  required int selectedIndex,
  required int selectedWeight,
}) {
  final result = List<int>.filled(rows.length, 0);
  result[selectedIndex] = selectedWeight;
  final remainder = 10000 - selectedWeight;
  final otherIndexes = [
    for (var index = 0; index < rows.length; index++)
      if (index != selectedIndex) index,
  ];
  if (otherIndexes.isEmpty) return result;
  final currentOtherTotal = otherIndexes.fold<int>(
    0,
    (sum, index) => sum + rows[index].targetWeightBps,
  );
  if (currentOtherTotal == 0) {
    final equal = _equalWeights(otherIndexes.length);
    var assigned = 0;
    for (var index = 0; index < otherIndexes.length; index++) {
      final weight = index == otherIndexes.length - 1
          ? remainder - assigned
          : (equal[index] * remainder / 10000).floor();
      result[otherIndexes[index]] = weight;
      assigned += weight;
    }
    return result;
  }
  var assigned = 0;
  for (var index = 0; index < otherIndexes.length; index++) {
    final rowIndex = otherIndexes[index];
    final weight = index == otherIndexes.length - 1
        ? remainder - assigned
        : (remainder * rows[rowIndex].targetWeightBps / currentOtherTotal)
              .floor();
    result[rowIndex] = weight;
    assigned += weight;
  }
  return result;
}
