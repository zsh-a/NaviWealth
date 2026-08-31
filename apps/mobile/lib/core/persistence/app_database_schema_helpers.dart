part of 'app_database.dart';

Future<void> _createFinancePlanningIndexes(AppDatabase db) async {
  for (final statement in financePlanningIndexStmts) {
    final tableMatch = RegExp(
      r'\bON\s+([a-z_][a-z0-9_]*)',
      caseSensitive: false,
    ).firstMatch(statement);
    final table = tableMatch?.group(1);
    if (table != null &&
        (await db.customSelect('PRAGMA table_info($table)').get()).isEmpty) {
      // Focused migration fixtures may intentionally omit unrelated planning
      // tables. Their indexes are created when those tables are introduced.
      continue;
    }
    await db.customStatement(statement);
  }
}

Future<void> _createForecastSnapshots(AppDatabase db) async {
  for (final statement in forecastEvaluationDdl) {
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
  // Some focused migration tests intentionally construct only the table under
  // test. A missing unrelated table has nothing to migrate here.
  if (columns.isEmpty) return;
  final exists = columns.any((row) => row.read<String>('name') == column);
  if (exists) return;
  await db.customStatement('ALTER TABLE $table ADD COLUMN $column $definition');
}

Future<void> _migrateFxRates(AppDatabase db) async {
  final columns = await db.customSelect('PRAGMA table_info(fx_rates)').get();
  if (columns.isEmpty) return;

  await _addColumnIfMissing(
    db,
    table: 'fx_rates',
    column: 'fetched_at',
    definition: 'INTEGER NOT NULL DEFAULT 0',
  );
  // Rows created before v78 only know the provider observation day. Keeping
  // that day as the fallback is honest and avoids inventing a newer fetch
  // timestamp during migration.
  await db.customStatement(
    'UPDATE fx_rates SET fetched_at = as_of WHERE fetched_at = 0',
  );

  // The repository already treated this as a natural key. Make that
  // invariant database-backed as well, while retaining the last inserted row
  // if an older development database happened to contain duplicates.
  await db.customStatement('DROP INDEX IF EXISTS idx_fx_rates_pair_as_of');
  await db.customStatement('''
DELETE FROM fx_rates
WHERE rowid NOT IN (
  SELECT MAX(rowid)
  FROM fx_rates
  GROUP BY base_currency, quote_currency, as_of
)
''');
  await db.customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_fx_rates_pair_as_of '
    'ON fx_rates(base_currency, quote_currency, as_of)',
  );
}

Future<void> _migrateMarketDataCaches(AppDatabase db, Migrator migrator) async {
  await _rebuildMarketQuotes(db, migrator);
  await _rebuildMarketHistoryBars(db, migrator);
  await _rebuildMarketSymbolSearches(db, migrator);
}

Future<void> _rebuildMarketQuotes(AppDatabase db, Migrator migrator) async {
  if (!await _needsMarketColumn(db, 'market_quotes')) return;
  await db.customStatement(
    'ALTER TABLE market_quotes RENAME TO market_quotes_v77',
  );
  await migrator.createTable(db.marketQuotes);
  await db.customStatement('''
INSERT INTO market_quotes (
  market, symbol, source, currency, price, previous_close, open_price,
  day_high, day_low, volume, exchange, as_of, fetched_at
)
SELECT
  'unknown', symbol, source, currency, price, previous_close, open_price,
  day_high, day_low, volume, exchange, as_of, fetched_at
FROM market_quotes_v77
''');
  await db.customStatement('DROP TABLE market_quotes_v77');
}

Future<void> _rebuildMarketHistoryBars(
  AppDatabase db,
  Migrator migrator,
) async {
  if (!await _needsMarketColumn(db, 'market_history_bars')) return;
  await db.customStatement(
    'ALTER TABLE market_history_bars RENAME TO market_history_bars_v77',
  );
  await migrator.createTable(db.marketHistoryBars);
  await db.customStatement('''
INSERT INTO market_history_bars (
  market, symbol, interval, as_of, source, open_price, high, low,
  close_price, volume, adjusted_close, fetched_at
)
SELECT
  'unknown', symbol, interval, as_of, source, open_price, high, low,
  close_price, volume, adjusted_close, fetched_at
FROM market_history_bars_v77
''');
  await db.customStatement('DROP TABLE market_history_bars_v77');
}

Future<void> _rebuildMarketSymbolSearches(
  AppDatabase db,
  Migrator migrator,
) async {
  if (!await _needsMarketColumn(db, 'market_symbol_searches')) return;
  await db.customStatement(
    'ALTER TABLE market_symbol_searches '
    'RENAME TO market_symbol_searches_v77',
  );
  await migrator.createTable(db.marketSymbolSearches);
  await db.customStatement('''
INSERT INTO market_symbol_searches (market, query, source, results, fetched_at)
SELECT 'unknown', query, source, results, fetched_at
FROM market_symbol_searches_v77
''');
  await db.customStatement('DROP TABLE market_symbol_searches_v77');
}

Future<bool> _needsMarketColumn(AppDatabase db, String table) async {
  final columns = await db.customSelect('PRAGMA table_info($table)').get();
  if (columns.isEmpty) return false;
  return !columns.any((row) => row.read<String>('name') == 'market');
}

const List<String> _marketDataCacheIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_market_quotes_market_symbol_fetched '
      'ON market_quotes(market, symbol, fetched_at)',
  'CREATE INDEX IF NOT EXISTS idx_market_history_market_symbol_interval_date '
      'ON market_history_bars(market, symbol, interval, as_of)',
  'CREATE INDEX IF NOT EXISTS idx_market_search_market_query_fetched '
      'ON market_symbol_searches(market, query, fetched_at)',
];

Future<void> _createMarketDataCacheIndexes(AppDatabase db) async {
  for (final statement in _marketDataCacheIndexStmts) {
    final table = RegExp(
      r'\bON\s+([a-z_][a-z0-9_]*)',
      caseSensitive: false,
    ).firstMatch(statement)?.group(1);
    if (table != null &&
        (await db.customSelect('PRAGMA table_info($table)').get()).isEmpty) {
      // Focused migration fixtures may intentionally omit unrelated cache
      // tables. They are created with their indexes on the next full schema
      // creation / applicable migration.
      continue;
    }
    await db.customStatement(statement);
  }
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

Future<void> _createConversationCheckpoints(AppDatabase db) async {
  for (final stmt in conversationCheckpointDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createMemoryCandidates(AppDatabase db) async {
  for (final stmt in memoryCandidateDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createPersonalProfile(AppDatabase db) async {
  for (final stmt in personalProfileDdl) {
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

Future<void> _upgradeAgentRuntimeChatSnapshotsForInteractions(
  AppDatabase db,
) async {
  final columns = await db
      .customSelect('PRAGMA table_info(agent_runtime_chat_snapshots)')
      .get();
  if (columns.isEmpty) {
    await _createAgentRuntimeChatSnapshots(db);
    return;
  }

  await db.customStatement(
    'DROP INDEX IF EXISTS idx_agent_runtime_chat_snapshots_pending',
  );
  await db.customStatement(
    'ALTER TABLE agent_runtime_chat_snapshots '
    'RENAME TO agent_runtime_chat_snapshots_v55',
  );
  await _createAgentRuntimeChatSnapshots(db);
  await db.customStatement('''
    INSERT INTO agent_runtime_chat_snapshots (
      owner_user_id,
      turn_id,
      snapshot_version,
      revision,
      status,
      snapshot_json,
      created_at,
      updated_at,
      expires_at
    )
    SELECT
      owner_user_id,
      turn_id,
      snapshot_version,
      revision,
      status,
      snapshot_json,
      created_at,
      updated_at,
      expires_at
    FROM agent_runtime_chat_snapshots_v55
  ''');
  await db.customStatement('DROP TABLE agent_runtime_chat_snapshots_v55');
}

Future<void> _createAgentArtifacts(AppDatabase db) async {
  for (final stmt in agentArtifactDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createAttentionDecisions(AppDatabase db) async {
  for (final stmt in attentionDecisionDdl) {
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
    'CREATE INDEX IF NOT EXISTS idx_categories_owner_active '
        'ON categories(owner_user_id, archived, sort_order)',
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
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_fx_rates_pair_as_of '
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
    ..._marketDataCacheIndexStmts,
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
  'CREATE INDEX IF NOT EXISTS idx_watchlist_collections_owner_hlc '
      'ON watchlist_collections(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_collections_owner_created '
      'ON watchlist_collections(owner_user_id, created_at) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_collections_owner_sort '
      'ON watchlist_collections(owner_user_id, sort_rank, created_at) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_collection_members_owner_hlc '
      'ON watchlist_collection_members(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_collection_members_collection '
      'ON watchlist_collection_members(owner_user_id, collection_id, added_at) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_collection_members_collection_sort '
      'ON watchlist_collection_members('
      'owner_user_id, collection_id, sort_rank, added_at) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_collection_members_item '
      'ON watchlist_collection_members(owner_user_id, watchlist_item_id) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_simulations_owner_hlc '
      'ON watchlist_simulations(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_simulations_collection '
      'ON watchlist_simulations(owner_user_id, collection_id, created_at) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_simulation_positions_owner_hlc '
      'ON watchlist_simulation_positions(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_simulation_positions_simulation '
      'ON watchlist_simulation_positions('
      'owner_user_id, simulation_id, created_at) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_simulation_positions_item '
      'ON watchlist_simulation_positions(owner_user_id, watchlist_item_id) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_sim_allocation_versions_hlc '
      'ON watchlist_simulation_allocation_versions(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_sim_allocation_versions_time '
      'ON watchlist_simulation_allocation_versions('
      'owner_user_id, simulation_id, effective_at) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_sim_holding_versions_hlc '
      'ON watchlist_simulation_holding_versions(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_sim_holding_versions_entitlement '
      'ON watchlist_simulation_holding_versions('
      'owner_user_id, simulation_id, watchlist_item_id, effective_at) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_simulation_action_entries_hlc '
      'ON watchlist_simulation_action_entries(owner_user_id, hlc)',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_simulation_action_entries_sim '
      'ON watchlist_simulation_action_entries('
      'owner_user_id, simulation_id, ex_date) '
      'WHERE deleted_at IS NULL',
  'CREATE INDEX IF NOT EXISTS idx_watchlist_simulation_observations_history '
      'ON watchlist_simulation_observations('
      'owner_user_id, simulation_id, observation_day)',
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

Future<void> _createMarketCorporateActionIndexes(AppDatabase db) async {
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_market_corporate_actions_symbol '
    'ON market_corporate_action_candidates(market, symbol, fetched_at)',
  );
}

Future<void> _createWatchlistIndexes(AppDatabase db) async {
  for (final stmt in _watchlistIndexStmts) {
    final tableMatch = RegExp(
      r'\bON\s+([a-z_][a-z0-9_]*)',
      caseSensitive: false,
    ).firstMatch(stmt);
    final table = tableMatch?.group(1);
    if (table != null &&
        (await db.customSelect('PRAGMA table_info($table)').get()).isEmpty) {
      // Watchlist tables arrived in v10/v82/v84/v85. Focused migration fixtures
      // may omit tables from earlier phases entirely.
      continue;
    }
    await db.customStatement(stmt);
  }
}

const List<String> _optionsIncomeIndexStmts = [
  'CREATE INDEX IF NOT EXISTS idx_options_strategy_profile_owner_hlc '
      'ON options_strategy_profile(owner_user_id, hlc)',
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

Future<void> _createMemoryStorage(AppDatabase db) async {
  for (final stmt in memoryStorageDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createAgentFindings(AppDatabase db) async {
  for (final stmt in agentFindingDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createAgentFeedback(AppDatabase db) async {
  for (final stmt in agentFeedbackDdl) {
    await db.customStatement(stmt);
  }
}

Future<void> _createDeveloperIssues(AppDatabase db) async {
  for (final stmt in developerIssueDdl) {
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
