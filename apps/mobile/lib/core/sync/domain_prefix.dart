/// Sync v2 row-family namespace (`docs/lifeos-shell.md` §8, D-1.4).
///
/// Every row crossing the sync wire is tagged with a LifeOS domain
/// prefix so the active-domain set is observable in `sync_rows` and a
/// future `core/auth` opt-in (D-1.5) can scope pulls per domain.
/// Today `fin:` is the only active prefix; Phase D-2 adds `health:`.
///
/// Storage shape is the unprefixed Drift table name (`accounts`,
/// `journal_entries`, ...). The transform lives at the sync boundary
/// (`SyncEngine` push / `RowApplier` pull) so the local DB and every
/// repository stays unaware of namespaces.
library;

/// Domain prefix for FinanceOS rows. Trailing `:` is part of the
/// prefix so `'$prefix$table'` composes cleanly.
const String kFinanceDomainPrefix = 'fin:';

/// Reserved for Phase D-2 HealthOS rows.
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
