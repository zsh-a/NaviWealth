/// Sync v3 row-family namespace and table registry
/// (`docs/architecture/lifeos-shell.md` section 8, D-1.4).
///
/// Local Drift tables stay unprefixed. Rows are tagged only at the sync
/// boundary so repositories and the local database remain unaware of wire
/// namespaces.
library;

/// Domain prefix for FinanceOS rows. Trailing `:` is part of the prefix so
/// `'$prefix$table'` composes cleanly.
const String kFinanceDomainPrefix = 'fin:';

/// HealthOS row-family prefix.
const String kHealthDomainPrefix = 'health:';

/// KnowledgeOS rows (`docs/domains/knowledgeos-domain.md` section 2, 11).
const String kKnowledgeDomainPrefix = 'know:';

/// ExecutionOS rows: projects, personal actions, commitments, and progress.
const String kExecutionDomainPrefix = 'exec:';

/// All prefixes the applier is willing to accept inbound. Adding a prefix here
/// is a Phase D milestone, not a hotfix.
const Set<String> kSyncDomainPrefixes = <String>{
  kFinanceDomainPrefix,
  kHealthDomainPrefix,
  kKnowledgeDomainPrefix,
  kExecutionDomainPrefix,
};

class SyncTableRegistration {
  const SyncTableRegistration(
    this.table, {
    required this.domainPrefix,
    this.primaryKey = 'id',
    this.ownerScoped = true,
    this.backfillEligible = true,
    this.backupEligible = true,
  });

  final String table;
  final String domainPrefix;
  final String primaryKey;

  /// True when the local Drift table has the `owner_user_id` sync partition
  /// column and can participate in local-only/cloud owner migration.
  final bool ownerScoped;

  /// True when existing local rows should be queued during sync backfill.
  final bool backfillEligible;

  /// True when encrypted local backups should include this table.
  final bool backupEligible;
}

/// Single source of truth for the client-side sync table surface.
const List<SyncTableRegistration>
kSyncTableRegistrations = <SyncTableRegistration>[
  SyncTableRegistration('accounts', domainPrefix: kFinanceDomainPrefix),
  SyncTableRegistration('assets', domainPrefix: kFinanceDomainPrefix),
  SyncTableRegistration('liabilities', domainPrefix: kFinanceDomainPrefix),
  SyncTableRegistration(
    'fx_rates',
    domainPrefix: kFinanceDomainPrefix,
    ownerScoped: false,
    backfillEligible: false,
  ),
  SyncTableRegistration('tags', domainPrefix: kFinanceDomainPrefix),
  SyncTableRegistration('budgets', domainPrefix: kFinanceDomainPrefix),
  SyncTableRegistration('goals', domainPrefix: kFinanceDomainPrefix),
  SyncTableRegistration(
    'investment_portfolios',
    domainPrefix: kFinanceDomainPrefix,
  ),
  SyncTableRegistration(
    'portfolio_lot_memberships',
    domainPrefix: kFinanceDomainPrefix,
  ),
  SyncTableRegistration(
    'financial_decisions',
    domainPrefix: kFinanceDomainPrefix,
  ),
  SyncTableRegistration(
    'financial_signals',
    domainPrefix: kFinanceDomainPrefix,
  ),
  SyncTableRegistration(
    'financial_monthly_closes',
    domainPrefix: kFinanceDomainPrefix,
  ),
  SyncTableRegistration(
    'financial_reconciliations',
    domainPrefix: kFinanceDomainPrefix,
  ),
  SyncTableRegistration('devices', domainPrefix: kFinanceDomainPrefix),
  SyncTableRegistration(
    'amortization_entries',
    domainPrefix: kFinanceDomainPrefix,
  ),
  SyncTableRegistration('tag_links', domainPrefix: kFinanceDomainPrefix),
  SyncTableRegistration('categories', domainPrefix: kFinanceDomainPrefix),
  SyncTableRegistration(
    'settings',
    domainPrefix: kFinanceDomainPrefix,
    primaryKey: 'user_id',
  ),
  SyncTableRegistration('users', domainPrefix: kFinanceDomainPrefix),
  SyncTableRegistration('journal_entries', domainPrefix: kFinanceDomainPrefix),
  SyncTableRegistration('postings', domainPrefix: kFinanceDomainPrefix),
  SyncTableRegistration('prices', domainPrefix: kFinanceDomainPrefix),
  SyncTableRegistration(
    'corporate_actions',
    domainPrefix: kFinanceDomainPrefix,
  ),
  SyncTableRegistration('watchlist_items', domainPrefix: kFinanceDomainPrefix),
  SyncTableRegistration(
    'options_strategy_profile',
    domainPrefix: kFinanceDomainPrefix,
    primaryKey: 'user_id',
  ),
  SyncTableRegistration(
    'approved_underlyings',
    domainPrefix: kFinanceDomainPrefix,
  ),
  SyncTableRegistration(
    'options_trade_journal',
    domainPrefix: kFinanceDomainPrefix,
  ),
  SyncTableRegistration('health_metrics', domainPrefix: kHealthDomainPrefix),
  SyncTableRegistration(
    'knowledge_notes',
    domainPrefix: kKnowledgeDomainPrefix,
  ),
  SyncTableRegistration(
    'knowledge_principles',
    domainPrefix: kKnowledgeDomainPrefix,
  ),
  SyncTableRegistration(
    'knowledge_assumptions',
    domainPrefix: kKnowledgeDomainPrefix,
  ),
  SyncTableRegistration(
    'knowledge_decisions',
    domainPrefix: kKnowledgeDomainPrefix,
  ),
  SyncTableRegistration(
    'knowledge_concepts',
    domainPrefix: kKnowledgeDomainPrefix,
  ),
  SyncTableRegistration(
    'knowledge_experiments',
    domainPrefix: kKnowledgeDomainPrefix,
  ),
  SyncTableRegistration(
    'knowledge_routines',
    domainPrefix: kKnowledgeDomainPrefix,
  ),
  SyncTableRegistration(
    'knowledge_relations',
    domainPrefix: kKnowledgeDomainPrefix,
  ),
  SyncTableRegistration(
    'execution_projects',
    domainPrefix: kExecutionDomainPrefix,
  ),
  SyncTableRegistration(
    'execution_actions',
    domainPrefix: kExecutionDomainPrefix,
  ),
  SyncTableRegistration(
    'execution_commitments',
    domainPrefix: kExecutionDomainPrefix,
  ),
  SyncTableRegistration(
    'execution_progress_entries',
    domainPrefix: kExecutionDomainPrefix,
  ),
];

final Map<String, SyncTableRegistration> kSyncTableRegistry =
    Map<String, SyncTableRegistration>.unmodifiable(
      <String, SyncTableRegistration>{
        for (final registration in kSyncTableRegistrations)
          registration.table: registration,
      },
    );

Set<String> _tablesForDomain(String domainPrefix) {
  return Set<String>.unmodifiable(
    kSyncTableRegistrations
        .where(
          (SyncTableRegistration registration) =>
              registration.domainPrefix == domainPrefix,
        )
        .map((SyncTableRegistration registration) => registration.table),
  );
}

/// FinanceOS local table names that participate in row-state sync.
final Set<String> kFinanceTables = _tablesForDomain(kFinanceDomainPrefix);

/// HealthOS rows that sync through the generic row-state store.
final Set<String> kHealthTables = _tablesForDomain(kHealthDomainPrefix);

/// KnowledgeOS local table names (`docs/domains/knowledgeos-domain.md`
/// section 9). Kept explicit rather than sniffing the `knowledge_` name prefix
/// so adding a table is a deliberate sync-surface edit.
final Set<String> kKnowledgeTables = _tablesForDomain(kKnowledgeDomainPrefix);

/// ExecutionOS local table names.
final Set<String> kExecutionTables = _tablesForDomain(kExecutionDomainPrefix);

/// Syncable local tables grouped by row-family prefix.
final Map<String, Set<String>> kSyncTablesByDomainPrefix =
    Map<String, Set<String>>.unmodifiable(<String, Set<String>>{
      kFinanceDomainPrefix: kFinanceTables,
      kHealthDomainPrefix: kHealthTables,
      kKnowledgeDomainPrefix: kKnowledgeTables,
      kExecutionDomainPrefix: kExecutionTables,
    });

/// The closed set of Drift tables that participate in sync
/// (`docs/sync/sync-v3.md`).
///
/// Adding a value is a data-model change only. The server's row store remains
/// schema-agnostic.
final Set<String> kSyncableTables = Set<String>.unmodifiable(
  kSyncTableRegistry.keys,
);

/// Primary-key column for tables whose PK is not `id`.
final Map<String, String> kSyncPkOverrides =
    Map<String, String>.unmodifiable(<String, String>{
      for (final registration in kSyncTableRegistrations)
        if (registration.primaryKey != 'id')
          registration.table: registration.primaryKey,
    });

/// Owner-scoped sync tables that should be scanned when enabling sync for
/// historical local data.
final List<String> kSyncBackfillTables = List<String>.unmodifiable(
  kSyncTableRegistrations
      .where(
        (SyncTableRegistration registration) =>
            registration.ownerScoped && registration.backfillEligible,
      )
      .map((SyncTableRegistration registration) => registration.table),
);

String syncPrimaryKeyForTable(String table) => kSyncPkOverrides[table] ?? 'id';

/// Add the FinanceOS prefix to a Drift table name.
String prefixFinanceTable(String localTable) =>
    '$kFinanceDomainPrefix$localTable';

/// The LifeOS domain prefix an outbound row should carry, by local table name.
String domainPrefixForTable(String localTable) {
  return kSyncTableRegistry[localTable]?.domainPrefix ?? kFinanceDomainPrefix;
}

/// Add the correct LifeOS domain prefix to an outbound Drift table name.
String prefixTable(String localTable) =>
    '${domainPrefixForTable(localTable)}$localTable';

/// Strip a known LifeOS domain prefix. Returns `null` when the input has no
/// recognised prefix so callers can skip rows instead of guessing.
String? stripDomainPrefix(String wireTable) {
  for (final prefix in kSyncDomainPrefixes) {
    if (wireTable.startsWith(prefix)) {
      return wireTable.substring(prefix.length);
    }
  }
  return null;
}

/// True when [wireTable] carries a recognised domain prefix.
bool hasDomainPrefix(String wireTable) =>
    kSyncDomainPrefixes.any(wireTable.startsWith);
