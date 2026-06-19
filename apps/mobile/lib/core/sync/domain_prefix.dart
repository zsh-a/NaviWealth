/// Sync v2 row-family namespace (`docs/lifeos-shell.md` §8, D-1.4).
///
/// Every row crossing the sync wire is tagged with a LifeOS domain
/// prefix so the active-domain set is observable in `sync_rows` and
/// `core/auth` can scope pulls per domain.
///
/// Storage shape is the unprefixed Drift table name (`accounts`,
/// `journal_entries`, ...). The transform lives at the sync boundary
/// (`SyncEngine` push / `RowApplier` pull) so the local DB and every
/// repository stays unaware of namespaces.
library;

/// Domain prefix for FinanceOS rows. Trailing `:` is part of the
/// prefix so `'$prefix$table'` composes cleanly.
const String kFinanceDomainPrefix = 'fin:';

/// HealthOS row-family prefix. Whether a concrete Health table syncs is
/// controlled by `kSyncableTables` and the outbound table-prefix router.
const String kHealthDomainPrefix = 'health:';

/// KnowledgeOS rows (`docs/knowledgeos-domain.md` §2, §11).
const String kKnowledgeDomainPrefix = 'know:';

/// All prefixes the applier is willing to accept inbound. Adding a
/// prefix here is a Phase D milestone, not a hotfix.
const Set<String> kSyncDomainPrefixes = <String>{
  kFinanceDomainPrefix,
  kHealthDomainPrefix,
  kKnowledgeDomainPrefix,
};

/// Add the FinanceOS prefix to a Drift table name. Every Finance
/// row currently crosses the wire as `fin:<table>`.
String prefixFinanceTable(String localTable) =>
    '$kFinanceDomainPrefix$localTable';

/// KnowledgeOS local table names (`docs/knowledgeos-domain.md` §9). Kept
/// explicit rather than sniffing the `knowledge_` name prefix so adding a
/// table is a deliberate edit that lands next to the prefix decision.
const Set<String> kKnowledgeTables = <String>{
  'knowledge_notes',
  'knowledge_principles',
  'knowledge_assumptions',
  'knowledge_decisions',
  'knowledge_concepts',
  'knowledge_experiments',
  'knowledge_routines',
};

/// HealthOS rows that sync through the generic row-state store.
const Set<String> kHealthTables = <String>{'health_metrics'};

/// The LifeOS domain prefix an outbound row should carry, by local table
/// name.
String domainPrefixForTable(String localTable) {
  if (kKnowledgeTables.contains(localTable)) return kKnowledgeDomainPrefix;
  if (kHealthTables.contains(localTable)) return kHealthDomainPrefix;
  return kFinanceDomainPrefix;
}

/// Add the correct LifeOS domain prefix to an outbound Drift table name
/// (see [domainPrefixForTable]).
String prefixTable(String localTable) =>
    '${domainPrefixForTable(localTable)}$localTable';

/// Strip a known LifeOS domain prefix. Returns `null` when the input
/// has no recognised prefix — the applier should skip those rows
/// rather than guess.
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
