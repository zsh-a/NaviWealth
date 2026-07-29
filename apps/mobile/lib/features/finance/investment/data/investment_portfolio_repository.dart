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
import '../domain/models/portfolio_removal_failure.dart';
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
    final groupId = _uuid.v4();
    final strategyId = _uuid.v4();
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
      final portfolioTarget = PortfolioAllocationTarget(
        id: portfolioAllocationTargetId(universe.id, portfolioId),
        universeId: universe.id,
        portfolioId: portfolioId,
        targetWeightBps: existingTargets.isEmpty ? 10000 : 0,
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

  Future<PortfolioStrategyTemplate> updateCustomStrategyTemplate({
    required PortfolioStrategyTemplate template,
    required String name,
    required String languageCode,
    required TargetAllocation defaultInternalTarget,
    required int defaultDriftBandBps,
    required GroupTransferPolicy defaultTransferPolicy,
  }) async {
    if (template.isBuiltIn) {
      throw ArgumentError.value(template, 'template', 'must be custom');
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final stamp = await _stamper.stamp();
    final updated = template.copyWith(
      localizedNames: {
        ...template.localizedNames,
        (languageCode.trim().isEmpty ? 'en' : languageCode.trim()):
            normalizedName,
      },
      defaultInternalTarget: defaultInternalTarget,
      defaultDriftBandBps: defaultDriftBandBps,
      defaultTransferPolicy: defaultTransferPolicy,
      sync: _syncFromStamp(stamp),
    );
    updated.validate();
    await _db.transaction(() async {
      await (_db.update(_db.portfolioStrategyTemplates)
            ..where((table) => table.id.equals(template.kind.wire)))
          .write(_strategyTemplateCompanion(updated));
      await _outbox.enqueue(
        table: strategyTemplatesTable,
        rowId: updated.kind.wire,
      );
    });
    return updated;
  }

  Future<void> archiveCustomStrategyTemplate(
    PortfolioStrategyTemplate template,
  ) async {
    if (template.isBuiltIn) {
      throw ArgumentError.value(template, 'template', 'must be custom');
    }
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.portfolioStrategyTemplates,
      )..where((table) => table.id.equals(template.kind.wire))).write(
        PortfolioStrategyTemplatesCompanion(
          archived: const Value(true),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(
        table: strategyTemplatesTable,
        rowId: template.kind.wire,
      );
    });
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
  /// New groups start at 0% so adding one never silently changes the existing
  /// plan. The collection editor is the only place that redistributes capital.
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
    final groupId = _uuid.v4();
    final strategyId = _uuid.v4();
    late final PortfolioRebalanceGroup created;
    await _db.transaction(() async {
      final existing = await _activeGroupRows(portfolioId);
      created = PortfolioRebalanceGroup(
        id: groupId,
        portfolioId: portfolioId,
        name: _nullableTrimmed(groupName) ?? template.displayName('en'),
        strategyKind: kind,
        targetWeightBps: existing.isEmpty ? 10000 : 0,
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
      id: _uuid.v4(),
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

  /// Replaces every active portfolio target in one universe atomically.
  ///
  /// Callers must submit the complete sibling set. This keeps redistribution
  /// explicit in the UI instead of mutating hidden rows as a side effect of
  /// editing one percentage.
  Future<List<PortfolioAllocationTarget>> updatePortfolioPlan({
    required String universeId,
    required List<PortfolioAllocationTarget> targets,
  }) async {
    if (targets.isEmpty ||
        targets.any(
          (target) => target.universeId != universeId || !target.isValid,
        ) ||
        targets.fold<int>(0, (sum, target) => sum + target.targetWeightBps) !=
            10000) {
      throw ArgumentError.value(
        targets,
        'targets',
        'must be the complete valid 100% universe allocation',
      );
    }
    final stamp = await _stamper.stamp();
    final updated = [
      for (final target in targets)
        target.copyWith(sync: _syncFromStamp(stamp)),
    ];
    await _db.transaction(() async {
      final rows = await _activePortfolioTargetRows(universeId);
      final activeIds = {for (final row in rows) row.id};
      final submittedIds = {for (final target in targets) target.id};
      if (activeIds.length != submittedIds.length ||
          !activeIds.containsAll(submittedIds)) {
        throw StateError('Portfolio plan changed while it was being edited.');
      }
      for (final target in updated) {
        await (_db.update(_db.portfolioAllocationTargets)
              ..where((table) => table.id.equals(target.id)))
            .write(_portfolioTargetCompanion(target));
        await _outbox.enqueue(table: portfolioTargetsTable, rowId: target.id);
      }
    });
    return List.unmodifiable(updated);
  }

  /// Replaces every active capital-owning strategy in one portfolio
  /// atomically. The sibling weights must total exactly 100%.
  Future<List<PortfolioRebalanceGroup>> updateStrategyPlan({
    required String portfolioId,
    required List<PortfolioRebalanceGroup> groups,
  }) async {
    if (groups.isEmpty ||
        groups.any(
          (group) =>
              group.portfolioId != portfolioId ||
              group.name.trim().isEmpty ||
              !group.hasValidWeight ||
              !group.internalTarget.isValid,
        ) ||
        groups.fold<int>(0, (sum, group) => sum + group.targetWeightBps) !=
            10000) {
      throw ArgumentError.value(
        groups,
        'groups',
        'must be the complete valid 100% strategy allocation',
      );
    }
    final stamp = await _stamper.stamp();
    final updated = [
      for (final group in groups)
        group.copyWith(name: group.name.trim(), sync: _syncFromStamp(stamp)),
    ];
    await _db.transaction(() async {
      final rows = await _activeGroupRows(portfolioId);
      final activeIds = {for (final row in rows) row.id};
      final submittedIds = {for (final group in groups) group.id};
      if (activeIds.length != submittedIds.length ||
          !activeIds.containsAll(submittedIds)) {
        throw StateError('Strategy plan changed while it was being edited.');
      }
      for (final group in updated) {
        await (_db.update(_db.portfolioRebalanceGroups)
              ..where((table) => table.id.equals(group.id)))
            .write(_groupCompanion(group));
        await _outbox.enqueue(table: groupsTable, rowId: group.id);
      }
    });
    return List.unmodifiable(updated);
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
        'use updateStrategyPlan to save the complete 100% allocation',
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
          portfolioId: Value(destinationPortfolioId),
          rebalanceGroupId: Value(destinationGroupId),
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
