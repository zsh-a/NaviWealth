part of 'app_database.dart';

Future<void> _createFinancePlanningIndexes(AppDatabase db) async {
  for (final statement in financePlanningIndexStmts) {
    await db.customStatement(statement);
  }
}

Future<void> _createRunwayForecastSnapshots(AppDatabase db) async {
  for (final statement in runwayForecastDdl) {
    await db.customStatement(statement);
  }
}

Future<void> _addColumnIfMissing(
  AppDatabase db, {
  required String table,
  required String column,
  required String definition,
}) async {
  final columns = await db.customSelect('PRAGMA table_info($table)').get();
  final exists = columns.any((row) => row.read<String>('name') == column);
  if (exists) return;
  await db.customStatement('ALTER TABLE $table ADD COLUMN $column $definition');
}

Future<void> _createChatTables(AppDatabase db) async {
  await _createChatSessionsTable(db);
  const stmts = <String>[
    '''
CREATE TABLE IF NOT EXISTS chat_messages (
  id                  TEXT PRIMARY KEY,
  session_id          TEXT NOT NULL,
  owner_user_id       TEXT NOT NULL,
  role                TEXT NOT NULL,
  content             TEXT NOT NULL DEFAULT '',
  tool_calls_json     TEXT,
  text_segments_json  TEXT,
  reasoning_text      TEXT,
  usage_json          TEXT,
  progress_json       TEXT,
  status              TEXT NOT NULL,
  error_message       TEXT,
  stop_reason         TEXT,
  created_at          INTEGER NOT NULL,
  FOREIGN KEY (session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
)
''',
    'CREATE INDEX IF NOT EXISTS idx_chat_messages_session_created '
        'ON chat_messages(session_id, created_at)',
  ];
  for (final stmt in stmts) {
    await db.customStatement(stmt);
  }
}

Future<void> _createChatSessionsTable(AppDatabase db) async {
  await db.customStatement('''
CREATE TABLE IF NOT EXISTS chat_sessions (
  id              TEXT PRIMARY KEY,
  owner_user_id   TEXT NOT NULL,
  title           TEXT NOT NULL,
  model           TEXT,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  last_message_at INTEGER,
  pinned          INTEGER NOT NULL DEFAULT 0,
  archived        INTEGER NOT NULL DEFAULT 0
)
''');
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_chat_sessions_owner_last '
    'ON chat_sessions(owner_user_id, last_message_at)',
  );
}

Future<void> _createDataMaintenanceRuns(AppDatabase db) async {
  for (final stmt in dataMaintenanceRunDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createSyncTables(AppDatabase db) async {
  for (final stmt in syncTableDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createDomainEventLog(AppDatabase db) async {
  for (final stmt in domainEventLogDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createAgentRuns(AppDatabase db) async {
  for (final stmt in agentRunDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createAgentRuntimeCheckpoints(AppDatabase db) async {
  for (final stmt in agentRuntimeCheckpointDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createAgentRuntimeChatSnapshots(AppDatabase db) async {
  for (final stmt in agentRuntimeChatSnapshotDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createAgentArtifacts(AppDatabase db) async {
  for (final stmt in agentArtifactDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createAgentPreferences(AppDatabase db) async {
  for (final stmt in agentPreferenceDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createIndexes(AppDatabase db) async {
  const stmts = <String>[
    'CREATE INDEX IF NOT EXISTS idx_accounts_owner_hlc '
        'ON accounts(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_assets_owner_hlc '
        'ON assets(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_liabilities_owner_hlc '
        'ON liabilities(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_amort_owner_hlc '
        'ON amortization_entries(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_tags_owner_hlc '
        'ON tags(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_tag_links_owner_hlc '
        'ON tag_links(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_categories_owner_hlc '
        'ON categories(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_goals_owner_hlc '
        'ON goals(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_budgets_owner_hlc '
        'ON budgets(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_budgets_category_period '
        'ON budgets(category_id, period_month)',
    'CREATE INDEX IF NOT EXISTS idx_devices_owner_hlc '
        'ON devices(owner_user_id, hlc)',
    'CREATE INDEX IF NOT EXISTS idx_amort_liability_period '
        'ON amortization_entries(liability_id, period_index)',
    'CREATE INDEX IF NOT EXISTS idx_fx_rates_pair_as_of '
        'ON fx_rates(base_currency, quote_currency, as_of)',
    'CREATE INDEX IF NOT EXISTS idx_tag_links_entity '
        'ON tag_links(entity_table, entity_id)',
    'CREATE INDEX IF NOT EXISTS idx_op_logs_unsynced '
        'ON op_logs(synced_at, hlc) WHERE synced_at IS NULL',
    'CREATE INDEX IF NOT EXISTS idx_op_logs_owner_hlc '
        'ON op_logs(owner_user_id, hlc)',
    // HealthOS (D-2.1): typical reads are "give me the last N rows
    // of <kind> for this user" plus the standard owner+hlc sync scan.
    'CREATE INDEX IF NOT EXISTS idx_health_metrics_owner_kind_captured '
        'ON health_metrics(owner_user_id, kind, captured_at)',
    'CREATE INDEX IF NOT EXISTS idx_health_metrics_owner_hlc '
        'ON health_metrics(owner_user_id, hlc)',
    ..._securitiesAssetIndexStmts,
    ..._journalEntryIndexStmts,
    ...knowledgeIndexStmts,
    ...executionIndexStmts,
  ];
  for (final stmt in stmts) {
    await db.customStatement(stmt);
  }
}

const List<String> _journalEntryIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_journal_entries_owner_hlc '
      'ON journal_entries(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_journal_entries_owner_date '
      'ON journal_entries(owner_user_id, date)',
  'CREATE INDEX IF NOT EXISTS idx_postings_je '
      'ON postings(journal_entry_id)',
  'CREATE INDEX IF NOT EXISTS idx_postings_account_je '
      'ON postings(account_id, journal_entry_id)',
  'CREATE INDEX IF NOT EXISTS idx_postings_unit_je '
      'ON postings(unit, journal_entry_id)',
  'CREATE INDEX IF NOT EXISTS idx_postings_owner_hlc '
      'ON postings(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_prices_unit_quote_date '
      'ON prices(unit, quote_currency, observed_on)',
  'CREATE INDEX IF NOT EXISTS idx_prices_owner_hlc '
      'ON prices(owner_user_id, hlc)',
  ..._corporateActionIndexStmts,
  ..._watchlistIndexStmts,
  ..._recurringTransactionIndexStmts,
  ..._optionsIncomeIndexStmts,
  ..._optionsTradeJournalIndexStmts,
];

const List<String> _securitiesAssetIndexStmts = [
  'CREATE UNIQUE INDEX IF NOT EXISTS uq_assets_market_symbol_live '
      'ON assets(market, symbol) '
      'WHERE market IS NOT NULL AND deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_assets_market_symbol '
      'ON assets(market, symbol) WHERE market IS NOT NULL',
];

const List<String> _recurringTransactionIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_recurring_transactions_owner_hlc '
      'ON recurring_transactions(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_recurring_transactions_due '
      'ON recurring_transactions(owner_user_id, enabled, next_due_at) '
      'WHERE deleted_at IS NULL',
];

const List<String> _watchlistIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_watchlist_items_owner_hlc '
      'ON watchlist_items(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_items_owner_added '
      'ON watchlist_items(owner_user_id, added_at) '
      'WHERE deleted_at IS NULL',
];

const List<String> _corporateActionIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_corporate_actions_owner_hlc '
      'ON corporate_actions(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_corporate_actions_owner_asset_date '
      'ON corporate_actions(owner_user_id, asset_id, effective_date) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_corporate_actions_owner_date '
      'ON corporate_actions(owner_user_id, effective_date) '
      'WHERE deleted_at IS NULL',
];

Future<void> _createRecurringTransactionIndexes(AppDatabase db) async {
  for (final stmt in _recurringTransactionIndexStmts) {
    await db.customStatement(stmt);
  }
}

Future<void> _createCorporateActionIndexes(AppDatabase db) async {
  for (final stmt in _corporateActionIndexStmts) {
    await db.customStatement(stmt);
  }
}

Future<void> _createExecutionIndexes(AppDatabase db) async {
  for (final stmt in executionIndexStmts) {
    await db.customStatement(stmt);
  }
}

Future<void> _createWatchlistIndexes(AppDatabase db) async {
  for (final stmt in _watchlistIndexStmts) {
    await db.customStatement(stmt);
  }
}

const List<String> _optionsIncomeIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_options_strategy_profile_owner_hlc '
      'ON options_strategy_profile(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_approved_underlyings_owner_hlc '
      'ON approved_underlyings(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_approved_underlyings_owner_symbol '
      'ON approved_underlyings(owner_user_id, symbol) '
      'WHERE deleted_at IS NULL',
];

const List<String> _optionsTradeJournalIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_options_trade_journal_owner_hlc '
      'ON options_trade_journal(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_options_trade_journal_owner_opened '
      'ON options_trade_journal(owner_user_id, opened_at DESC) '
      'WHERE deleted_at IS NULL',
];

Future<void> _createOptionsIncomeIndexes(AppDatabase db) async {
  for (final stmt in _optionsIncomeIndexStmts) {
    await db.customStatement(stmt);
  }
}

Future<void> _createOptionsTradeJournalIndexes(AppDatabase db) async {
  for (final stmt in _optionsTradeJournalIndexStmts) {
    await db.customStatement(stmt);
  }
}

Future<void> _createOptionsOpportunityCache(AppDatabase db) async {
  for (final stmt in optionsOpportunityCacheDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createRecurringPatternObservations(AppDatabase db) async {
  for (final stmt in recurringPatternObservationDdl) {
    await db.customStatement(stmt);
  }
}

/// Legacy v16 DDL — kept only so the `if (from < 16)` step in
/// [AppDatabase.migration] still applies cleanly when a user jumps v15 → v17.
/// v17 immediately drops the table, so this is effectively a no-op
/// migration path in practice.
Future<void> _createMemoryDocuments(AppDatabase db) async {
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS memory_documents ('
    '  id TEXT PRIMARY KEY, source TEXT, source_id TEXT, owner_user_id TEXT,'
    '  title TEXT, body TEXT, fingerprint TEXT, dimension INTEGER,'
    '  vector_bytes BLOB, updated_at INTEGER)',
  );
}

Future<void> _createMemoryRuntime(AppDatabase db) async {
  for (final stmt in memoryRuntimeDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createKnowledgeInboxTriage(AppDatabase db) async {
  for (final stmt in knowledgeInboxTriageDdl) {
    await db.customStatement(stmt);
  }
}

const List<String> _securitiesCatalogFtsStmts = [
  '''
CREATE VIRTUAL TABLE IF NOT EXISTS securities_catalog_fts USING fts5(
  symbol,
  name_en,
  name_cn,
  pinyin,
  pinyin_initials,
  aliases,
  content='',
  tokenize='unicode61 remove_diacritics 2'
)
''',
];

Future<void> _createSecuritiesCatalogFts(AppDatabase db) async {
  for (final stmt in _securitiesCatalogFtsStmts) {
    await db.customStatement(stmt);
  }
}

const List<String> _securitiesCatalogIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_securities_catalog_symbol '
      'ON securities_catalog(symbol)',
  'CREATE INDEX IF NOT EXISTS idx_securities_catalog_name_en '
      'ON securities_catalog(name_en)',
  'CREATE INDEX IF NOT EXISTS idx_securities_catalog_name_cn '
      'ON securities_catalog(name_cn)',
  'CREATE INDEX IF NOT EXISTS idx_securities_catalog_pinyin '
      'ON securities_catalog(pinyin)',
  'CREATE INDEX IF NOT EXISTS idx_securities_catalog_pinyin_initials '
      'ON securities_catalog(pinyin_initials)',
  'CREATE INDEX IF NOT EXISTS idx_securities_catalog_market '
      'ON securities_catalog(market)',
];

Future<void> _createSecuritiesCatalogIndexes(AppDatabase db) async {
  for (final stmt in _securitiesCatalogIndexStmts) {
    await db.customStatement(stmt);
  }
}

// ---------------------------------------------------------------------------
// AI surfaces — local-only audit + undo stack.
// Both tables stay device-local (never sync). Per-user partitioning is the
// caller's responsibility; we store the owner alongside each row so a
// multi-user install can scope queries.
// ---------------------------------------------------------------------------

Future<void> _createAiTraceTable(AppDatabase db) async {
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS ai_traces ('
    '  request_id     TEXT PRIMARY KEY,'
    '  owner_user_id  TEXT NOT NULL,'
    '  started_at_iso TEXT NOT NULL,'
    '  payload_json   TEXT NOT NULL'
    ')',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_ai_traces_started_at '
    'ON ai_traces(started_at_iso DESC)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_ai_traces_owner '
    'ON ai_traces(owner_user_id, started_at_iso DESC)',
  );
}

Future<void> _createAiUndoStackTable(AppDatabase db) async {
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS ai_undo_stack ('
    '  token          TEXT PRIMARY KEY,'
    '  owner_user_id  TEXT NOT NULL,'
    '  created_at_iso TEXT NOT NULL,'
    '  expires_at_iso TEXT,'
    '  kind           TEXT NOT NULL,'
    '  payload_json   TEXT NOT NULL'
    ')',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_ai_undo_owner '
    'ON ai_undo_stack(owner_user_id, created_at_iso DESC)',
  );
}

Future<void> _createAiTouchedEntitiesTable(AppDatabase db) async {
  // Records "this entity was last touched by an AI
  // proposal apply at <touched_at>". Detail pages query this side
  // table to render `AiSourceMark` next to recently AI-modified
  // entities; storing the touch out-of-band keeps the underlying
  // entity schemas (journal_entries / accounts / liabilities /
  // assets) unaware of the AI write path.
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS ai_touched_entities ('
    '  owner_user_id TEXT NOT NULL,'
    '  entity_type   TEXT NOT NULL,'
    '  entity_id     TEXT NOT NULL,'
    '  touched_at    TEXT NOT NULL,'
    '  kind_label    TEXT,' // 'expense' / 'trade' / 'memo_edit' / ...
    '  trace_id      TEXT,' // AiTrace.requestId for jump-to-trace
    '  PRIMARY KEY (owner_user_id, entity_type, entity_id)'
    ')',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_ai_touched_owner '
    'ON ai_touched_entities(owner_user_id, touched_at DESC)',
  );
}

Future<void> _createIngestTables(AppDatabase db) async {
  // §5.10.10 / S5a — Layer 4 record-entry pipeline staging.
  //
  // `ingest_drafts` holds parsed-but-unconfirmed transactions. It is
  // deliberately a raw-SQL side table (same pattern as ai_undo_stack /
  // ai_touched_entities) and is **never added to the sync OpLog**: a
  // draft only becomes durable ledger truth after the user confirms it,
  // at which point it is written through the normal repository path.
  // This keeps "Raw Write-side Truth · AI 永远不能直接访问" intact and
  // makes §4.2's draft gate hold by construction rather than by policy.
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS ingest_drafts ('
    '  draft_id              TEXT PRIMARY KEY,'
    '  owner_user_id         TEXT NOT NULL,'
    '  created_at_iso        TEXT NOT NULL,'
    '  source_kind           TEXT NOT NULL,' // csv / pasteText / ...
    '  origin_label          TEXT,' //          filename or "粘贴文本"
    '  parsed_json           TEXT NOT NULL,' // ParsedTransaction payload
    '  confidence            REAL NOT NULL,'
    '  dedup_verdict         TEXT NOT NULL,' // newTxn/likelyDuplicate/duplicate
    '  dedup_target_entry_id TEXT,' //          matched journal_entries.id
    '  trace_id              TEXT,' //          AiTrace.requestId
    '  status                TEXT NOT NULL,' // pending/confirming/settled
    '  recovery_kind         TEXT,' // finalize_applied/confirm_ambiguous
    '  recovery_apply_state_json TEXT,' // ProposalApplyState continuation
    '  revision              INTEGER NOT NULL DEFAULT 0,'
    '  operation_token       TEXT,'
    '  invocation_started    INTEGER NOT NULL DEFAULT 0,'
    '  expires_at_iso        TEXT'
    ')',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_ingest_drafts_owner '
    'ON ingest_drafts(owner_user_id, status, created_at_iso DESC)',
  );
  // Forward-compat: the original capture artefact (receipt image / PDF)
  // for the S5b/S5c Vision path. Encrypted at rest by SQLCipher
  // like the rest of the DB; purged on confirm or after expiry. Unused
  // in S5a (text/CSV has no binary blob) but created here so S5b does
  // not need a second schema bump.
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS ingest_attachments ('
    '  draft_id       TEXT PRIMARY KEY,'
    '  owner_user_id  TEXT NOT NULL,'
    '  mime           TEXT NOT NULL,'
    '  blob           BLOB NOT NULL,'
    '  expires_at_iso TEXT'
    ')',
  );
}

Future<void> _createRebalanceExecutionTables(AppDatabase db) async {
  // Local-only workflow state. These rows are intentionally absent from the
  // Drift table list and sync registry; committed trades still flow through
  // assets/journal_entries/postings/prices and their normal outbox writes.
  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS rebalance_execution_sessions ('
    '  id TEXT PRIMARY KEY,'
    '  owner_user_id TEXT NOT NULL,'
    "  status TEXT NOT NULL CHECK (status IN ('active', 'archived')),"
    '  plan_json TEXT NOT NULL,'
    '  plan_fingerprint TEXT NOT NULL,'
    '  created_at_iso TEXT NOT NULL,'
    '  updated_at_iso TEXT NOT NULL,'
    '  archived_at_iso TEXT,'
    '  UNIQUE (id, owner_user_id),'
    "  CHECK ((status = 'active' AND archived_at_iso IS NULL) OR "
    "         (status = 'archived' AND archived_at_iso IS NOT NULL))"
    ')',
  );
  await db.customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS '
    'idx_rebalance_execution_one_active_owner '
    'ON rebalance_execution_sessions(owner_user_id) '
    "WHERE status = 'active'",
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_rebalance_execution_sessions_owner '
    'ON rebalance_execution_sessions(owner_user_id, updated_at_iso DESC)',
  );

  await db.customStatement(
    'CREATE TABLE IF NOT EXISTS rebalance_execution_items ('
    '  id TEXT PRIMARY KEY,'
    '  session_id TEXT NOT NULL,'
    '  owner_user_id TEXT NOT NULL,'
    '  position INTEGER NOT NULL CHECK (position >= 0),'
    '  suggestion_json TEXT NOT NULL,'
    '  request_json TEXT,'
    '  receipt_json TEXT,'
    "  state TEXT NOT NULL CHECK (state IN ('needsDetails', 'ready', "
    "    'applying', 'applied', 'applyFailed', 'undoing', 'undone', "
    "    'undoFailed', 'skipped', 'recoveryBlocked')),"
    '  failure_code TEXT,'
    '  error TEXT,'
    '  attempt_token TEXT,'
    '  lease_until_iso TEXT,'
    '  applied_sequence INTEGER CHECK (applied_sequence IS NULL OR '
    '    applied_sequence > 0),'
    '  recovery_was_applied INTEGER NOT NULL DEFAULT 0 '
    '    CHECK (recovery_was_applied IN (0, 1)),'
    '  created_at_iso TEXT NOT NULL,'
    '  updated_at_iso TEXT NOT NULL,'
    '  UNIQUE (session_id, position),'
    '  FOREIGN KEY (session_id, owner_user_id) '
    '    REFERENCES rebalance_execution_sessions(id, owner_user_id) '
    '    ON DELETE CASCADE,'
    '  CHECK ('
    "    (state = 'needsDetails' AND request_json IS NULL AND "
    '      receipt_json IS NULL AND applied_sequence IS NULL) OR '
    "    (state IN ('ready', 'applying', 'applyFailed') AND "
    '      request_json IS NOT NULL AND receipt_json IS NULL AND '
    '      applied_sequence IS NULL) OR '
    "    (state IN ('applied', 'undoing', 'undone', 'undoFailed') AND "
    '      request_json IS NOT NULL AND receipt_json IS NOT NULL AND '
    '      applied_sequence IS NOT NULL) OR '
    "    (state = 'skipped' AND receipt_json IS NULL AND "
    '      applied_sequence IS NULL) OR '
    "    state = 'recoveryBlocked'"
    '  ),'
    '  CHECK ('
    "    (state IN ('applying', 'undoing') AND attempt_token IS NOT NULL "
    '      AND lease_until_iso IS NOT NULL) OR '
    "    (state NOT IN ('applying', 'undoing') AND attempt_token IS NULL "
    '      AND lease_until_iso IS NULL)'
    '  ),'
    '  CHECK (recovery_was_applied = 0 OR '
    "    (state = 'recoveryBlocked' AND applied_sequence IS NOT NULL)),"
    '  CHECK ('
    "    (state IN ('applyFailed', 'undoFailed', 'recoveryBlocked') AND "
    '      failure_code IS NOT NULL) OR '
    "    (state NOT IN ('applyFailed', 'undoFailed', 'recoveryBlocked') AND "
    '      failure_code IS NULL AND error IS NULL)'
    '  )'
    ')',
  );
  await db.customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS '
    'idx_rebalance_execution_applied_sequence '
    'ON rebalance_execution_items(session_id, applied_sequence) '
    'WHERE applied_sequence IS NOT NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_rebalance_execution_items_session '
    'ON rebalance_execution_items(owner_user_id, session_id, position)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_rebalance_execution_items_state '
    'ON rebalance_execution_items(owner_user_id, session_id, state)',
  );
  await _createRebalanceExecutionIssueTriggers(db);
}

Future<void> _createRebalanceExecutionIssueTriggers(AppDatabase db) async {
  const invalidIssueState =
      "((NEW.state IN ('applyFailed', 'undoFailed', 'recoveryBlocked') "
      'AND NEW.failure_code IS NULL) OR '
      "(NEW.state NOT IN ('applyFailed', 'undoFailed', 'recoveryBlocked') "
      'AND (NEW.failure_code IS NOT NULL OR NEW.error IS NOT NULL)))';
  await db.customStatement(
    'CREATE TRIGGER IF NOT EXISTS '
    'trg_rebalance_execution_issue_insert '
    'BEFORE INSERT ON rebalance_execution_items '
    'WHEN $invalidIssueState '
    "BEGIN SELECT RAISE(ABORT, 'invalid rebalance execution issue'); END",
  );
  await db.customStatement(
    'CREATE TRIGGER IF NOT EXISTS '
    'trg_rebalance_execution_issue_update '
    'BEFORE UPDATE OF state, failure_code, error '
    'ON rebalance_execution_items '
    'WHEN $invalidIssueState '
    "BEGIN SELECT RAISE(ABORT, 'invalid rebalance execution issue'); END",
  );
}
