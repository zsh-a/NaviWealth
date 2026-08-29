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

part 'investment_portfolio_repository_assignments.dart';
part 'investment_portfolio_repository_mappers.dart';
part 'investment_portfolio_repository_removals.dart';
part 'investment_portfolio_repository_watches.dart';
part 'investment_portfolio_repository_writes.dart';

const _uuid = Uuid();

/// Sync row families owned by the portfolio aggregate. Every mutation
/// writes the row and enqueues its outbox op inside one transaction.
const portfoliosTable = 'investment_portfolios';
const strategyTemplatesTable = 'portfolio_strategy_templates';
const universesTable = 'rebalance_universes';
const portfolioTargetsTable = 'portfolio_allocation_targets';
const strategiesTable = 'portfolio_strategy_configs';
const groupsTable = 'portfolio_rebalance_groups';
const assignmentsTable = 'portfolio_capital_assignments';

/// Read/write API for the investment portfolio aggregate: portfolios,
/// rebalance universes/groups/strategies, allocation targets, and capital
/// assignments (seven tables, one ownership model).
///
/// Structure follows the [JournalEntryRepository] split: mixins own the
/// watch streams, aggregate writes, removals, and capital assignments;
/// the mappers part holds the companion/row mapping layer as top-level
/// functions. The facade keeps the shared fields and the internal row
/// queries that several mixins need.
///
/// Every public mutation lives inside a single Drift transaction that
/// writes its rows and queues the corresponding outbox ops atomically.
class InvestmentPortfolioRepository
    with
        InvestmentPortfolioRepositoryWatchMixin,
        InvestmentPortfolioRepositoryWriteMixin,
        InvestmentPortfolioRepositoryRemovalMixin,
        InvestmentPortfolioRepositoryAssignmentMixin {
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

  @override
  final AppDatabase _db;
  @override
  final OutboxStore _outbox;
  @override
  final MutationStamper _stamper;
  @override
  final PortfolioStrategyRegistry _strategyRegistry;

  @override
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

  @override
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

  @override
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

  @override
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

  @override
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

  @override
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

  @override
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

  @override
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
}
