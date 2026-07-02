/// Sync v2 row-family namespace and table registry
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

/// FinanceOS local table names that participate in row-state sync.
const Set<String> kFinanceTables = <String>{
  'accounts',
  'assets',
  'liabilities',
  'fx_rates',
  'tags',
  'budgets',
  'goals',
  'devices',
  'amortization_entries',
  'tag_links',
  'categories',
  'settings',
  'users',
  'journal_entries',
  'postings',
  'prices',
  'corporate_actions',
  'watchlist_items',
  'options_strategy_profile',
  'approved_underlyings',
  'options_trade_journal',
};

/// HealthOS rows that sync through the generic row-state store.
const Set<String> kHealthTables = <String>{'health_metrics'};

/// KnowledgeOS local table names (`docs/domains/knowledgeos-domain.md`
/// section 9). Kept explicit rather than sniffing the `knowledge_` name prefix
/// so adding a table is a deliberate sync-surface edit.
const Set<String> kKnowledgeTables = <String>{
  'knowledge_notes',
  'knowledge_principles',
  'knowledge_assumptions',
  'knowledge_decisions',
  'knowledge_concepts',
  'knowledge_experiments',
  'knowledge_routines',
};

/// ExecutionOS local table names.
const Set<String> kExecutionTables = <String>{
  'execution_projects',
  'execution_actions',
  'execution_commitments',
  'execution_progress_entries',
};

/// Syncable local tables grouped by row-family prefix.
const Map<String, Set<String>> kSyncTablesByDomainPrefix =
    <String, Set<String>>{
      kFinanceDomainPrefix: kFinanceTables,
      kHealthDomainPrefix: kHealthTables,
      kKnowledgeDomainPrefix: kKnowledgeTables,
      kExecutionDomainPrefix: kExecutionTables,
    };

/// The closed set of Drift tables that participate in sync
/// (`docs/sync/sync-v2.md` section 7.1).
///
/// Adding a value is a data-model change only. The server's row store remains
/// schema-agnostic.
const Set<String> kSyncableTables = <String>{
  ...kFinanceTables,
  ...kHealthTables,
  ...kKnowledgeTables,
  ...kExecutionTables,
};

/// Primary-key column for tables whose PK is not `id`.
const Map<String, String> kSyncPkOverrides = <String, String>{
  'settings': 'user_id',
  'options_strategy_profile': 'user_id',
};

String syncPrimaryKeyForTable(String table) => kSyncPkOverrides[table] ?? 'id';

/// Add the FinanceOS prefix to a Drift table name.
String prefixFinanceTable(String localTable) =>
    '$kFinanceDomainPrefix$localTable';

/// The LifeOS domain prefix an outbound row should carry, by local table name.
String domainPrefixForTable(String localTable) {
  for (final entry in kSyncTablesByDomainPrefix.entries) {
    if (entry.value.contains(localTable)) return entry.key;
  }
  return kFinanceDomainPrefix;
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
