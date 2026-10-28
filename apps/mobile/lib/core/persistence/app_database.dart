import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:naviwealth/core/sync/hlc.dart';

import '../../core/sync/sync_tables.dart';
import 'connection.dart';
import 'converters.dart';
import 'domain_enums.dart';
import 'event_log_tables.dart';
import 'execution_tables.dart';
import 'health_tables.dart';
import 'knowledge_tables.dart';
import 'local_only_tables.dart';
import 'tables.dart';

part 'app_database_schema_helpers.dart';
part 'app_database.g.dart';

const String defaultDbFileName = 'naviwealth.db';

/// A database from another schema baseline needs an explicit user reset.
final class UnsupportedDatabaseSchema implements Exception {
  const UnsupportedDatabaseSchema({
    required this.foundVersion,
    required this.requiredVersion,
  });

  final int foundVersion;
  final int requiredVersion;

  @override
  String toString() =>
      'UnsupportedDatabaseSchema: schema $foundVersion cannot be opened by '
      'schema $requiredVersion. Reset local data to create a new database.';
}

enum AppDatabaseTransactionScopeErrorCode { inactive, databaseMismatch }

final class AppDatabaseTransactionScopeError implements Exception {
  const AppDatabaseTransactionScopeError(this.code, this.message);

  final AppDatabaseTransactionScopeErrorCode code;
  final String message;

  @override
  String toString() => 'AppDatabaseTransactionScopeError($code): $message';
}

/// Capability proving that code is running inside one active DB transaction.
///
/// Only [AppDatabase.transactionWithScope] can construct this value. It is
/// invalidated as soon as that transaction callback completes.
final class AppDatabaseTransactionScope {
  AppDatabaseTransactionScope._(this._database);

  final AppDatabase _database;
  bool _active = true;

  AppDatabase requireDatabase(AppDatabase database) {
    if (!_active) {
      throw const AppDatabaseTransactionScopeError(
        AppDatabaseTransactionScopeErrorCode.inactive,
        'Transaction scope is no longer active.',
      );
    }
    if (!identical(_database, database)) {
      throw const AppDatabaseTransactionScopeError(
        AppDatabaseTransactionScopeErrorCode.databaseMismatch,
        'Transaction scope belongs to a different AppDatabase.',
      );
    }
    return database;
  }

  void _deactivate() => _active = false;
}

/// Local NaviWealth database.
///
/// Schema 101 supports multiple device-local views per meal. Upgrades from
/// 99 and 100 preserve existing records and photos; other baselines and
/// downgrades are rejected without modifying data.
@DriftDatabase(
  tables: [
    Users,
    SettingsTable,
    Accounts,
    Assets,
    JournalEntries,
    Postings,
    Prices,
    CorporateActions,
    WatchlistItems,
    OptionsStrategyProfileTable,
    OptionsTradeJournal,
    OptionsLeapsCallPositions,
    IncomeStrategyPlans,
    RecurringTransactions,
    Liabilities,
    AmortizationEntries,
    Currencies,
    FxRates,
    Tags,
    TagLinks,
    Categories,
    Budgets,
    Goals,
    InvestmentPortfolios,
    PortfolioStrategyTemplates,
    RebalanceUniverses,
    PortfolioAllocationTargets,
    PortfolioStrategyConfigs,
    PortfolioRebalanceGroups,
    PortfolioCapitalAssignments,
    FirePlans,
    FinancialDecisions,
    DcaPlans,
    FinancialSignals,
    FinancialMonthlyCloses,
    FinancialReconciliations,
    Devices,
    OpLogs,
    MarketDataSnapshots,
    MarketQuotes,
    MarketHistoryBars,
    MarketSymbolSearches,
    MarketCorporateActionCandidates,
    MarketCorporateActionFetchStates,
    SecuritiesCatalog,
    SecuritiesCatalogMeta,
    // HealthOS (D-2.1): single wide-flat table keyed by `kind`.
    HealthMetrics,
    HealthCheckIns,
    HealthMeals,
    HealthMealPhotos,
    // KnowledgeOS: notes, decisions, and explicit relations.
    KnowledgeNotes,
    KnowledgeDecisions,
    KnowledgeRelations,
    // ExecutionOS Action Kernel: plans, personal actions, and updates.
    ExecutionPlans,
    ExecutionActions,
    ExecutionProgressEntries,
    WatchlistCollections,
    WatchlistCollectionMembers,
    WatchlistSimulations,
    WatchlistSimulationAllocationHeads,
    WatchlistSimulationAllocationVersions,
    WatchlistSimulationHoldingVersions,
    WatchlistSimulationActionEntries,
    WatchlistSimulationObservations,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.open({String? dbFileName, String? encryptionKey})
    : super(
        openAppConnection(
          dbFileName: dbFileName ?? defaultDbFileName,
          encryptionKey: encryptionKey,
        ),
      );

  Future<T> transactionWithScope<T>(
    Future<T> Function(AppDatabaseTransactionScope scope) action,
  ) {
    return transaction(() async {
      final scope = AppDatabaseTransactionScope._(this);
      try {
        return await action(scope);
      } finally {
        scope._deactivate();
      }
    });
  }

  @override
  int get schemaVersion => 101;

  UnsupportedDatabaseSchema? _schemaMismatch;

  /// Opens the connection before exposing it to consumers. Drift serializes
  /// migration errors across native isolates and Web workers; retain the typed
  /// rejection from our opening callback for the recovery UI.
  Future<void> ensureReady() async {
    try {
      await customSelect('SELECT 1').getSingle();
    } catch (error, stack) {
      final mismatch = _schemaMismatch;
      if (mismatch != null) Error.throwWithStackTrace(mismatch, stack);
      rethrow;
    }
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes(this);
      await _createMarketCorporateActionIndexes(this);
      await _createWatchlistSimulationLocalInvariants(this);
      await _createPortfolioIndexes(this);
      await _createSyncTables(this);
      await _createChatTables(this);
      await _createConversationCheckpoints(this);
      await _createMemoryCandidates(this);
      await _createPersonalProfile(this);
      await _createSecuritiesCatalogFts(this);
      await _createSecuritiesCatalogIndexes(this);
      await _createDomainEventLog(this);
      await _createAiTraceTable(this);
      await _createAiUndoStackTable(this);
      await _createAiTouchedEntitiesTable(this);
      await _createIngestTables(this);
      await _createOptionsOpportunityCache(this);
      await _createRecurringPatternObservations(this);
      await _createMemoryRuntime(this);
      await _createAgentRuns(this);
      await _createAgentRuntimeCheckpoints(this);
      await _createAgentRuntimeChatSnapshots(this);
      await _createAgentArtifacts(this);
      await _createAgentFindings(this);
      await _createAgentFeedback(this);
      await _createAttentionDecisions(this);
      await _createDeveloperIssues(this);
      await _createDataMaintenanceRuns(this);
      await _createAgentPreferences(this);
      await customStatement(createScheduledAgentTasks);
      await _createRebalanceExecutionTables(this);
      await _createFinancePlanningIndexes(this);
      await _createForecastSnapshots(this);
      await _createHealthCheckInIndexes(this);
      await _createHealthMealIndexes(this);
    },
    onUpgrade: (m, from, to) async {
      if ((from == 99 || from == 100) && to == 101) {
        await transaction(() async {
          if (from == 99) {
            await m.createTable(healthMeals);
            await m.createTable(healthMealPhotos);
          } else {
            await customStatement(
              'DROP TRIGGER IF EXISTS trg_health_meal_deleted_photo',
            );
            await m.alterTable(
              TableMigration(
                healthMealPhotos,
                newColumns: [
                  healthMealPhotos.mealId,
                  healthMealPhotos.viewRole,
                  healthMealPhotos.position,
                  healthMealPhotos.timestampMs,
                ],
                columnTransformer: {
                  healthMealPhotos.mealId: healthMealPhotos.id,
                },
              ),
            );
          }
          await _createHealthMealIndexes(this);
        });
        return;
      }
      final mismatch = UnsupportedDatabaseSchema(
        foundVersion: from,
        requiredVersion: to,
      );
      _schemaMismatch = mismatch;
      throw mismatch;
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

Future<void> _createHealthCheckInIndexes(AppDatabase db) => db.customStatement(
  'CREATE INDEX IF NOT EXISTS idx_health_check_ins_owner_day '
  'ON health_check_ins(owner_user_id, day)',
);

Future<void> _createHealthMealIndexes(AppDatabase db) async {
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_health_meals_owner_day '
    'ON health_meals(owner_user_id, day)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_health_meal_photos_meal '
    'ON health_meal_photos(owner_user_id, meal_id, position)',
  );
  // A Sync-applied tombstone must remove device-local bytes too. Keep this
  // invariant at the storage boundary without adding a Health callback to the
  // domain-neutral row applier.
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS trg_health_meal_deleted_photo
    AFTER UPDATE OF deleted_at ON health_meals
    WHEN NEW.deleted_at IS NOT NULL
    BEGIN
      DELETE FROM health_meal_photos WHERE meal_id = NEW.id;
    END
  ''');
}

Future<void> _createWatchlistSimulationLocalInvariants(AppDatabase db) async {
  await db.customStatement('''
      CREATE TRIGGER IF NOT EXISTS trg_watchlist_sim_action_balances_insert
      BEFORE INSERT ON watchlist_simulation_action_entries
      WHEN NEW.receivable_gross_amount IS NOT NULL
       AND NEW.paper_cash_gross_amount IS NOT NULL
      BEGIN
        SELECT RAISE(ABORT, 'paper dividend balances are mutually exclusive');
      END
    ''');
  await db.customStatement('''
      CREATE TRIGGER IF NOT EXISTS trg_watchlist_sim_action_balances_update
      BEFORE UPDATE OF receivable_gross_amount, paper_cash_gross_amount
      ON watchlist_simulation_action_entries
      WHEN NEW.receivable_gross_amount IS NOT NULL
       AND NEW.paper_cash_gross_amount IS NOT NULL
      BEGIN
        SELECT RAISE(ABORT, 'paper dividend balances are mutually exclusive');
      END
    ''');

  // Tombstones keep their device-local observation rows: the delete path is
  // an undoable tombstone, and purging here would silently reset a
  // months-long observed curve the moment the user taps undo. Rows are still
  // cleaned up when the definition row is really removed.
  await db.customStatement('''
      CREATE TRIGGER IF NOT EXISTS trg_watchlist_simulation_delete_cleanup
      AFTER DELETE ON watchlist_simulations
      BEGIN
        DELETE FROM watchlist_simulation_observations
        WHERE owner_user_id = OLD.owner_user_id
          AND simulation_id = OLD.id;
      END
    ''');
}

Future<void> _createPortfolioIndexes(AppDatabase db) async {
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_investment_portfolios_owner_hlc '
    'ON investment_portfolios(owner_user_id, hlc)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_portfolio_strategy_templates_owner '
    'ON portfolio_strategy_templates(owner_user_id, created_at) '
    'WHERE deleted_at IS NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_rebalance_universes_owner '
    'ON rebalance_universes(owner_user_id, created_at) '
    'WHERE deleted_at IS NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_portfolio_allocation_targets_universe '
    'ON portfolio_allocation_targets(owner_user_id, universe_id) '
    'WHERE deleted_at IS NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_portfolio_strategy_configs_owner '
    'ON portfolio_strategy_configs(owner_user_id, portfolio_id) '
    'WHERE deleted_at IS NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_portfolio_rebalance_groups_owner '
    'ON portfolio_rebalance_groups(owner_user_id, portfolio_id) '
    'WHERE deleted_at IS NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_portfolio_capital_assignments_group '
    'ON portfolio_capital_assignments(owner_user_id, rebalance_group_id) '
    'WHERE deleted_at IS NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_portfolio_capital_assignments_history '
    'ON portfolio_capital_assignments('
    'owner_user_id, portfolio_id, assigned_at, unassigned_at'
    ') WHERE deleted_at IS NULL',
  );
}
