import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_universe.dart';
import 'package:uuid/uuid.dart';

import '../domain/models/investment_portfolio.dart';
import '../domain/models/portfolio_capital_assignment.dart';
import '../domain/strategy/portfolio_strategy.dart';
import '../domain/strategy/portfolio_strategy_template.dart';

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
  static const strategyTemplatesTable = 'portfolio_strategy_templates';
  static const universesTable = 'rebalance_universes';
  static const portfolioTargetsTable = 'portfolio_allocation_targets';
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
    required PortfolioStrategyTemplate initialStrategy,
    required String baseCurrency,
    required String languageCode,
    String? goalId,
    String? color,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    initialStrategy.validate();
    if (initialStrategy.defaultCapitalRole != StrategyCapitalRole.owner) {
      throw ArgumentError.value(
        initialStrategy.kind.wire,
        'initialStrategy',
        'must own capital',
      );
    }
    final stamp = await _stamper.stamp();
    final portfolioId = _uuid.v4();
    final kind = initialStrategy.kind;
    final groupId = portfolioRebalanceGroupId(portfolioId, kind);
    final strategyId = portfolioStrategyConfigId(portfolioId, kind);
    final normalizedCurrency = baseCurrency.trim().toUpperCase();
    if (normalizedCurrency.length < 3 || normalizedCurrency.length > 8) {
      throw ArgumentError.value(
        baseCurrency,
        'baseCurrency',
        'must contain 3 to 8 characters',
      );
    }
    final portfolio = InvestmentPortfolio(
      id: portfolioId,
      name: normalizedName,
      baseCurrency: normalizedCurrency,
      goalId: _nullableTrimmed(goalId),
      color: _nullableTrimmed(color),
      createdAt: stamp.now,
      archived: false,
      sync: _syncFromStamp(stamp),
    );
    final group = PortfolioRebalanceGroup(
      id: groupId,
      portfolioId: portfolioId,
      name: initialStrategy.displayName(languageCode),
      strategyKind: kind,
      targetWeightBps: 10000,
      driftBandBps: initialStrategy.defaultDriftBandBps,
      transferPolicy: initialStrategy.defaultTransferPolicy,
      internalTarget: initialStrategy.defaultInternalTarget,
      createdAt: stamp.now,
      archived: false,
      sync: _syncFromStamp(stamp),
    );
    final strategy = PortfolioStrategyConfig(
      id: strategyId,
      portfolioId: portfolioId,
      kind: kind,
      schemaVersion: initialStrategy.schemaVersion,
      enabled: true,
      capitalRole: initialStrategy.defaultCapitalRole,
      rebalanceGroupId: groupId,
      settings: initialStrategy.defaultSettings,
      sync: _syncFromStamp(stamp),
    );

    await _db.transaction(() async {
      final universe = await _ensureDefaultUniverse(
        ownerUserId: stamp.ownerUserId,
        baseCurrency: normalizedCurrency,
        stamp: stamp,
      );
      final existingTargets = await _activePortfolioTargetRows(universe.id);
      final weights = _equalWeights(existingTargets.length + 1);
      for (var index = 0; index < existingTargets.length; index++) {
        await _writePortfolioTargetWeight(
          existingTargets[index].id,
          weights[index],
          stamp,
        );
      }
      final portfolioTarget = PortfolioAllocationTarget(
        id: portfolioAllocationTargetId(universe.id, portfolioId),
        universeId: universe.id,
        portfolioId: portfolioId,
        targetWeightBps: weights.last,
        driftBandBps: 500,
        transferPolicy: GroupTransferPolicy.bidirectional,
        sync: _syncFromStamp(stamp),
      );
      await _db
          .into(_db.investmentPortfolios)
          .insert(_portfolioCompanion(portfolio));
      await _db
          .into(_db.portfolioAllocationTargets)
          .insert(_portfolioTargetCompanion(portfolioTarget));
      await _db
          .into(_db.portfolioRebalanceGroups)
          .insert(_groupCompanion(group));
      await _db
          .into(_db.portfolioStrategyConfigs)
          .insert(_strategyCompanion(strategy));
      await _outbox.enqueue(table: portfoliosTable, rowId: portfolio.id);
      await _outbox.enqueue(
        table: portfolioTargetsTable,
        rowId: portfolioTarget.id,
      );
      await _outbox.enqueue(table: groupsTable, rowId: group.id);
      await _outbox.enqueue(table: strategiesTable, rowId: strategy.id);
    });
    return portfolio;
  }

  Future<PortfolioStrategyTemplate> createCustomStrategyTemplate({
    required String name,
    required String languageCode,
    required String iconToken,
    required StrategyCapitalRole capitalRole,
    required TargetAllocation defaultInternalTarget,
    required int defaultDriftBandBps,
    required GroupTransferPolicy defaultTransferPolicy,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final stamp = await _stamper.stamp();
    final template = PortfolioStrategyTemplate(
      kind: PortfolioStrategyKind('user:${_uuid.v4()}'),
      localizedNames: {
        (languageCode.trim().isEmpty ? 'en' : languageCode.trim()):
            normalizedName,
      },
      iconToken: iconToken.trim().isEmpty ? 'layers' : iconToken.trim(),
      schemaVersion: 1,
      defaultCapitalRole: capitalRole,
      defaultSettings: const OpaquePortfolioStrategySettings({}),
      defaultInternalTarget: defaultInternalTarget,
      defaultDriftBandBps: defaultDriftBandBps,
      defaultTransferPolicy: defaultTransferPolicy,
      createdAt: stamp.now,
      archived: false,
      sync: _syncFromStamp(stamp),
    );
    template.validate();
    await _db.transaction(() async {
      await _db
          .into(_db.portfolioStrategyTemplates)
          .insert(_strategyTemplateCompanion(template));
      await _outbox.enqueue(
        table: strategyTemplatesTable,
        rowId: template.kind.wire,
      );
    });
    return template;
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
    required PortfolioStrategyTemplate template,
    String? groupName,
  }) async {
    template.validate();
    if (template.defaultCapitalRole != StrategyCapitalRole.owner) {
      throw ArgumentError.value(
        template.kind.wire,
        'template',
        'must own capital',
      );
    }
    final kind = template.kind;
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
        name: _nullableTrimmed(groupName) ?? template.displayName('en'),
        strategyKind: kind,
        targetWeightBps: weights.last,
        driftBandBps: template.defaultDriftBandBps,
        transferPolicy: template.defaultTransferPolicy,
        internalTarget: template.defaultInternalTarget,
        createdAt: stamp.now,
        archived: false,
        sync: _syncFromStamp(stamp),
      );
      final strategy = PortfolioStrategyConfig(
        id: strategyId,
        portfolioId: portfolioId,
        kind: kind,
        schemaVersion: template.schemaVersion,
        enabled: true,
        capitalRole: StrategyCapitalRole.owner,
        rebalanceGroupId: groupId,
        settings: template.defaultSettings,
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
    required PortfolioStrategyTemplate template,
  }) async {
    template.validate();
    final kind = template.kind;
    await _requireActiveGroup(portfolioId, rebalanceGroupId);
    final stamp = await _stamper.stamp();
    final strategy = PortfolioStrategyConfig(
      id: portfolioStrategyConfigId(portfolioId, kind),
      portfolioId: portfolioId,
      kind: kind,
      schemaVersion: template.schemaVersion,
      enabled: true,
      capitalRole: StrategyCapitalRole.overlay,
      rebalanceGroupId: rebalanceGroupId,
      settings: template.defaultSettings,
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

  /// Updates one portfolio policy and preserves the universe's 100% total.
  Future<PortfolioAllocationTarget> updatePortfolioTargetConfiguration({
    required PortfolioAllocationTarget target,
    required int targetWeightBps,
  }) async {
    final candidate = target.copyWith(targetWeightBps: targetWeightBps);
    if (!candidate.isValid) {
      throw ArgumentError.value(target, 'target', 'contains invalid values');
    }
    final stamp = await _stamper.stamp();
    late final PortfolioAllocationTarget updated;
    await _db.transaction(() async {
      final rows = await _activePortfolioTargetRows(target.universeId);
      final selectedIndex = rows.indexWhere((row) => row.id == target.id);
      if (selectedIndex < 0) {
        throw StateError(
          'Portfolio target ${target.id} is not active in '
          '${target.universeId}.',
        );
      }
      if (rows.length == 1 && targetWeightBps != 10000) {
        throw StateError(
          'A single portfolio must own 100% of universe capital.',
        );
      }
      final weights = _redistributeWeights(
        currentWeights: [for (final row in rows) row.targetWeightBps],
        selectedIndex: selectedIndex,
        selectedWeight: targetWeightBps,
      );
      updated = candidate.copyWith(sync: _syncFromStamp(stamp));
      for (var index = 0; index < rows.length; index++) {
        if (index == selectedIndex) {
          await (_db.update(_db.portfolioAllocationTargets)
                ..where((table) => table.id.equals(target.id)))
              .write(_portfolioTargetCompanion(updated));
          await _outbox.enqueue(table: portfolioTargetsTable, rowId: target.id);
        } else {
          await _writePortfolioTargetWeight(
            rows[index].id,
            weights[index],
            stamp,
          );
        }
      }
    });
    return updated;
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
        currentWeights: [for (final row in rows) row.targetWeightBps],
        selectedIndex: selectedIndex,
        selectedWeight: targetWeightBps,
      );
      for (var index = 0; index < rows.length; index++) {
        await _writeGroupWeight(rows[index].id, weights[index], stamp);
      }
    });
  }

  /// Updates one group and redistributes portfolio weights atomically.
  ///
  /// This is the UI-facing aggregate mutation: either the selected group's
  /// configuration and every affected target weight are committed together,
  /// or none of them are.
  Future<PortfolioRebalanceGroup> updateGroupConfiguration({
    required PortfolioRebalanceGroup group,
    required int targetWeightBps,
  }) async {
    final normalizedName = group.name.trim();
    final candidate = group.copyWith(
      name: normalizedName,
      targetWeightBps: targetWeightBps,
    );
    if (normalizedName.isEmpty ||
        !candidate.hasValidWeight ||
        !candidate.internalTarget.isValid) {
      throw ArgumentError.value(group, 'group', 'contains invalid values');
    }

    final stamp = await _stamper.stamp();
    late final PortfolioRebalanceGroup updated;
    await _db.transaction(() async {
      final rows = await _activeGroupRows(group.portfolioId);
      final selectedIndex = rows.indexWhere((row) => row.id == group.id);
      if (selectedIndex < 0) {
        throw StateError(
          'Group ${group.id} is not active in ${group.portfolioId}.',
        );
      }
      if (rows.length == 1 && targetWeightBps != 10000) {
        throw StateError('A single group must own 100% of portfolio capital.');
      }

      final weights = _redistributeWeights(
        currentWeights: [for (final row in rows) row.targetWeightBps],
        selectedIndex: selectedIndex,
        selectedWeight: targetWeightBps,
      );
      updated = candidate.copyWith(sync: _syncFromStamp(stamp));
      for (var index = 0; index < rows.length; index++) {
        if (index == selectedIndex) {
          await (_db.update(_db.portfolioRebalanceGroups)
                ..where((table) => table.id.equals(group.id)))
              .write(_groupCompanion(updated));
          await _outbox.enqueue(table: groupsTable, rowId: group.id);
        } else {
          await _writeGroupWeight(rows[index].id, weights[index], stamp);
        }
      }
    });
    return updated;
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
      final affectedUniverseIds = await _tombstonePortfolioTargets(
        portfolio.id,
        stamp,
      );
      await _tombstonePortfolioRow(portfolio.id, stamp);
      await _tombstoneStrategies(portfolio.id, stamp);
      await _tombstoneGroups(portfolio.id, stamp);
      await _tombstoneAssignments(portfolio.id, stamp);
      for (final universeId in affectedUniverseIds) {
        await _normalizePortfolioTargets(universeId, stamp);
      }
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

  Future<RebalanceUniverse> _ensureDefaultUniverse({
    required String ownerUserId,
    required String baseCurrency,
    required MutationStamp stamp,
  }) async {
    final id = defaultRebalanceUniverseId(ownerUserId);
    final existing =
        await (_db.select(
              _db.rebalanceUniverses,
            )..where((table) => table.id.equals(id) & table.deletedAt.isNull()))
            .getSingleOrNull();
    if (existing != null) return _universeFromRow(existing);

    final universe = RebalanceUniverse(
      id: id,
      name: 'Investment capital',
      baseCurrency: baseCurrency,
      createdAt: stamp.now,
      archived: false,
      sync: _syncFromStamp(stamp),
    );
    await _db.into(_db.rebalanceUniverses).insert(_universeCompanion(universe));
    await _outbox.enqueue(table: universesTable, rowId: universe.id);
    return universe;
  }

  Future<List<PortfolioAllocationTargetRow>> _activePortfolioTargetRows(
    String universeId,
  ) {
    return (_db.select(_db.portfolioAllocationTargets)
          ..where(
            (table) =>
                table.universeId.equals(universeId) & table.deletedAt.isNull(),
          )
          ..orderBy([(table) => OrderingTerm.asc(table.portfolioId)]))
        .get();
  }

  Future<void> _normalizePortfolioTargets(
    String universeId,
    MutationStamp stamp,
  ) async {
    final rows = await _activePortfolioTargetRows(universeId);
    if (rows.isEmpty) return;
    final total = rows.fold<int>(0, (sum, row) => sum + row.targetWeightBps);
    final weights = total == 0
        ? _equalWeights(rows.length)
        : _scaleWeightsToTotal([
            for (final row in rows) row.targetWeightBps,
          ], 10000);
    for (var index = 0; index < rows.length; index++) {
      await _writePortfolioTargetWeight(rows[index].id, weights[index], stamp);
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

  Future<void> _writePortfolioTargetWeight(
    String targetId,
    int targetWeightBps,
    MutationStamp stamp,
  ) async {
    await (_db.update(
      _db.portfolioAllocationTargets,
    )..where((table) => table.id.equals(targetId))).write(
      PortfolioAllocationTargetsCompanion(
        targetWeightBps: Value(targetWeightBps),
        updatedAt: Value(stamp.now),
        updatedByDevice: Value(stamp.deviceId),
        hlc: Value(stamp.hlc),
      ),
    );
    await _outbox.enqueue(table: portfolioTargetsTable, rowId: targetId);
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

  PortfolioStrategyTemplatesCompanion _strategyTemplateCompanion(
    PortfolioStrategyTemplate template,
  ) {
    final sync = template.sync;
    final createdAt = template.createdAt;
    if (sync == null || createdAt == null) {
      throw ArgumentError.value(
        template,
        'template',
        'built-in templates are not persisted',
      );
    }
    return PortfolioStrategyTemplatesCompanion.insert(
      id: template.kind.wire,
      localizedNamesJson: jsonEncode(template.localizedNames),
      iconToken: template.iconToken,
      schemaVersion: template.schemaVersion,
      capitalRole: template.defaultCapitalRole.name,
      defaultSettingsJson: jsonEncode(
        _strategyRegistry.encode(template.kind, template.defaultSettings),
      ),
      defaultInternalTargetJson: jsonEncode(
        template.defaultInternalTarget.toJson(),
      ),
      defaultDriftBandBps: template.defaultDriftBandBps,
      defaultTransferPolicy: template.defaultTransferPolicy.name,
      createdAt: createdAt,
      archived: Value(template.archived),
      ownerUserId: sync.ownerUserId,
      updatedAt: sync.updatedAt,
      updatedByDevice: sync.updatedByDevice,
      hlc: sync.hlc,
      deletedAt: Value(sync.deletedAt),
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

  PortfolioStrategyTemplate _strategyTemplateFromRow(
    PortfolioStrategyTemplateRow row,
  ) {
    final namesJson = jsonDecode(row.localizedNamesJson);
    final settingsJson = jsonDecode(row.defaultSettingsJson);
    final targetJson = jsonDecode(row.defaultInternalTargetJson);
    if (namesJson is! Map || settingsJson is! Map || targetJson is! Map) {
      throw FormatException('${row.id} template JSON must contain objects.');
    }
    final kind = portfolioStrategyKindFromWire(row.id);
    final template = PortfolioStrategyTemplate(
      kind: kind,
      localizedNames: Map<String, String>.from(namesJson),
      iconToken: row.iconToken,
      schemaVersion: row.schemaVersion,
      defaultCapitalRole: StrategyCapitalRole.values.byName(row.capitalRole),
      defaultSettings: _strategyRegistry.decode(
        kind: kind,
        schemaVersion: row.schemaVersion,
        payload: Map<String, Object?>.from(settingsJson),
      ),
      defaultInternalTarget: TargetAllocation.fromJson(
        Map<String, dynamic>.from(targetJson),
      ),
      defaultDriftBandBps: row.defaultDriftBandBps,
      defaultTransferPolicy: groupTransferPolicyFromWire(
        row.defaultTransferPolicy,
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
    template.validate();
    return template;
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
  required List<int> currentWeights,
  required int selectedIndex,
  required int selectedWeight,
}) {
  final result = List<int>.filled(currentWeights.length, 0);
  result[selectedIndex] = selectedWeight;
  final remainder = 10000 - selectedWeight;
  final otherIndexes = [
    for (var index = 0; index < currentWeights.length; index++)
      if (index != selectedIndex) index,
  ];
  if (otherIndexes.isEmpty) return result;
  final currentOtherTotal = otherIndexes.fold<int>(
    0,
    (sum, index) => sum + currentWeights[index],
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
        : (remainder * currentWeights[rowIndex] / currentOtherTotal).floor();
    result[rowIndex] = weight;
    assigned += weight;
  }
  return result;
}

List<int> _scaleWeightsToTotal(List<int> weights, int targetTotal) {
  if (weights.isEmpty) return const [];
  final currentTotal = weights.fold<int>(0, (sum, weight) => sum + weight);
  if (currentTotal <= 0) return _equalWeights(weights.length);
  final result = List<int>.filled(weights.length, 0);
  var assigned = 0;
  for (var index = 0; index < weights.length; index++) {
    final scaled = index == weights.length - 1
        ? targetTotal - assigned
        : (targetTotal * weights[index] / currentTotal).floor();
    result[index] = scaled;
    assigned += scaled;
  }
  return result;
}
