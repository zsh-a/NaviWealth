import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

import 'test_database.dart';

void main() {
  test('transaction scope is active only for its bound transaction', () async {
    final db = makeTestDatabase();
    final other = makeTestDatabase();
    addTearDown(db.close);
    addTearDown(other.close);
    await db.customStatement('CREATE TABLE scope_probe (id TEXT PRIMARY KEY)');
    late AppDatabaseTransactionScope captured;

    await db.transactionWithScope((scope) async {
      captured = scope;
      expect(scope.requireDatabase(db), same(db));
      await db.customInsert("INSERT INTO scope_probe VALUES ('committed')");
    });
    expect(
      await db.customSelect('SELECT * FROM scope_probe').get(),
      hasLength(1),
    );
    expect(
      () => captured.requireDatabase(db),
      throwsA(
        isA<AppDatabaseTransactionScopeError>().having(
          (error) => error.code,
          'code',
          AppDatabaseTransactionScopeErrorCode.inactive,
        ),
      ),
    );

    await expectLater(
      db.transactionWithScope((scope) async {
        scope.requireDatabase(other);
        await db.customInsert("INSERT INTO scope_probe VALUES ('wrong-db')");
      }),
      throwsA(
        isA<AppDatabaseTransactionScopeError>().having(
          (error) => error.code,
          'code',
          AppDatabaseTransactionScopeErrorCode.databaseMismatch,
        ),
      ),
    );
    expect(
      await db.customSelect('SELECT * FROM scope_probe').get(),
      hasLength(1),
    );
  });

  test('opens with SQLite foreign keys enabled', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    final pragma = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(pragma.read<int>('foreign_keys'), 1);
  });

  test('memory_embeddings rejects missing memory rows', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    await expectLater(
      db.customStatement(
        '''
        INSERT INTO memory_embeddings (
          memory_id,
          fingerprint,
          dimension,
          vector_bytes
        ) VALUES (?, ?, ?, ?)
        ''',
        [
          'missing',
          'stub-v1',
          2,
          Uint8List.fromList([0, 0, 0, 0]),
        ],
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('deleting a memory cascades to its embedding vector', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    await db.customStatement(
      '''
      INSERT INTO memories (
        id,
        kind,
        scope,
        owner_user_id,
        title,
        summary,
        payload_json,
        entities_json,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        'mem-1',
        'semantic',
        '*',
        'user-1',
        'Preference',
        'User prefers concise answers.',
        '{}',
        '[]',
        1,
        1,
      ],
    );
    await db.customStatement(
      '''
      INSERT INTO memory_embeddings (
        memory_id,
        fingerprint,
        dimension,
        vector_bytes
      ) VALUES (?, ?, ?, ?)
      ''',
      [
        'mem-1',
        'stub-v1',
        2,
        Uint8List.fromList([0, 0, 0, 0]),
      ],
    );

    await db.customStatement('DELETE FROM memories WHERE id = ?', ['mem-1']);

    final rows = await db
        .customSelect('SELECT memory_id FROM memory_embeddings')
        .get();
    expect(rows, isEmpty);
  });

  test('postings reject partial cost and price annotations', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    Future<void> insertPosting({
      required String id,
      String? costPerUnit,
      String? costCurrency,
      String? pricePerUnit,
      String? priceCurrency,
    }) {
      return db.customStatement(
        '''
        INSERT INTO postings (
          id,
          journal_entry_id,
          position,
          account_id,
          units,
          unit,
          cost_per_unit,
          cost_currency,
          price_per_unit,
          price_currency,
          owner_user_id,
          updated_at,
          updated_by_device,
          hlc
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          id,
          'je-1',
          0,
          'cash',
          '1',
          'CNY',
          costPerUnit,
          costCurrency,
          pricePerUnit,
          priceCurrency,
          'user-1',
          1,
          'device-1',
          '1:device-1',
        ],
      );
    }

    await expectLater(
      insertPosting(id: 'partial-cost', costPerUnit: '10'),
      throwsA(isA<SqliteException>()),
    );
    await expectLater(
      insertPosting(id: 'partial-price', priceCurrency: 'USD'),
      throwsA(isA<SqliteException>()),
    );

    await insertPosting(
      id: 'complete-annotations',
      costPerUnit: '10',
      costCurrency: 'CNY',
      pricePerUnit: '1.4',
      priceCurrency: 'USD',
    );

    final saved = await db
        .customSelect(
          '''
          SELECT cost_per_unit, cost_currency, price_per_unit, price_currency
          FROM postings
          WHERE id = ?
          ''',
          variables: [Variable.withString('complete-annotations')],
        )
        .getSingle();
    expect(saved.read<String>('cost_per_unit'), '10');
    expect(saved.read<String>('cost_currency'), 'CNY');
    expect(saved.read<String>('price_per_unit'), '1.4');
    expect(saved.read<String>('price_currency'), 'USD');
  });

  test('assets keep one live security per market symbol pair', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    Future<void> insertAsset({required String id, int? deletedAt}) {
      return db.customStatement(
        '''
        INSERT INTO assets (
          id,
          type,
          symbol,
          currency,
          market,
          owner_user_id,
          updated_at,
          updated_by_device,
          hlc,
          deleted_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          id,
          'stock',
          'AAPL',
          'USD',
          'us_stock',
          'user-1',
          1,
          'device-1',
          '1:device-1',
          deletedAt,
        ],
      );
    }

    await insertAsset(id: 'us_stock:AAPL');

    await expectLater(
      insertAsset(id: 'duplicate-live'),
      throwsA(isA<SqliteException>()),
    );

    await db.customStatement('UPDATE assets SET deleted_at = ? WHERE id = ?', [
      2,
      'us_stock:AAPL',
    ]);
    await insertAsset(id: 'us_stock:AAPL:restored');

    final liveRows = await db
        .customSelect(
          '''
          SELECT id
          FROM assets
          WHERE market = ? AND symbol = ? AND deleted_at IS NULL
          ''',
          variables: [
            Variable.withString('us_stock'),
            Variable.withString('AAPL'),
          ],
        )
        .get();
    expect(liveRows.map((r) => r.read<String>('id')), [
      'us_stock:AAPL:restored',
    ]);
  });

  test('watchlist items are unique per owner market symbol pair', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    Future<void> insertWatchlistItem({
      required String id,
      required String ownerUserId,
      required String market,
      required String symbol,
    }) {
      return db.customStatement(
        '''
        INSERT INTO watchlist_items (
          id,
          symbol,
          market,
          added_at,
          owner_user_id,
          updated_at,
          updated_by_device,
          hlc
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [id, symbol, market, 1, ownerUserId, 1, 'device-1', '1:device-1'],
      );
    }

    await insertWatchlistItem(
      id: 'watch-aapl',
      ownerUserId: 'user-1',
      market: 'us_stock',
      symbol: 'AAPL',
    );

    await expectLater(
      insertWatchlistItem(
        id: 'watch-aapl-dup',
        ownerUserId: 'user-1',
        market: 'us_stock',
        symbol: 'AAPL',
      ),
      throwsA(isA<SqliteException>()),
    );

    await insertWatchlistItem(
      id: 'watch-aapl-other-owner',
      ownerUserId: 'user-2',
      market: 'us_stock',
      symbol: 'AAPL',
    );
    await insertWatchlistItem(
      id: 'watch-aapl-other-market',
      ownerUserId: 'user-1',
      market: 'hk_stock',
      symbol: 'AAPL',
    );

    final rows = await db.customSelect('''
          SELECT id
          FROM watchlist_items
          ORDER BY id
          ''').get();
    expect(rows.map((r) => r.read<String>('id')), [
      'watch-aapl',
      'watch-aapl-other-market',
      'watch-aapl-other-owner',
    ]);
  });

  test('settings remain a singleton per user', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    Future<void> insertSettings({
      required String userId,
      required String ownerUserId,
      required String baseCurrency,
    }) {
      return db.customStatement(
        '''
        INSERT INTO settings (
          user_id,
          base_currency,
          theme_mode,
          privacy_mode,
          cost_basis_method,
          owner_user_id,
          updated_at,
          updated_by_device,
          hlc
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          userId,
          baseCurrency,
          'system',
          'visible',
          'fifo',
          ownerUserId,
          1,
          'device-1',
          '1:device-1',
        ],
      );
    }

    await insertSettings(
      userId: 'user-1',
      ownerUserId: 'user-1',
      baseCurrency: 'USD',
    );
    await expectLater(
      insertSettings(
        userId: 'user-1',
        ownerUserId: 'user-1',
        baseCurrency: 'CNY',
      ),
      throwsA(isA<SqliteException>()),
    );
    await insertSettings(
      userId: 'user-2',
      ownerUserId: 'user-2',
      baseCurrency: 'HKD',
    );

    final rows = await db
        .customSelect('SELECT user_id FROM settings ORDER BY user_id')
        .get();
    expect(rows.map((r) => r.read<String>('user_id')), ['user-1', 'user-2']);
  });

  test('options strategy profile remains a singleton per user', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    Future<void> insertProfile({
      required String userId,
      required String ownerUserId,
      required String mode,
    }) {
      return db.customStatement(
        '''
        INSERT INTO options_strategy_profile (
          user_id,
          mode,
          min_dte,
          max_dte,
          delta_put_min,
          delta_put_max,
          delta_call_min,
          delta_call_max,
          max_capital_per_trade_pct,
          min_annualized_yield,
          min_open_interest,
          min_volume,
          max_bid_ask_spread_pct,
          owner_user_id,
          updated_at,
          updated_by_device,
          hlc
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          userId,
          mode,
          14,
          45,
          '-0.35',
          '-0.15',
          '0.15',
          '0.35',
          '0.05',
          '0.05',
          100,
          10,
          '0.10',
          ownerUserId,
          1,
          'device-1',
          '1:device-1',
        ],
      );
    }

    await insertProfile(
      userId: 'user-1',
      ownerUserId: 'user-1',
      mode: 'balanced',
    );
    await expectLater(
      insertProfile(
        userId: 'user-1',
        ownerUserId: 'user-1',
        mode: 'conservative',
      ),
      throwsA(isA<SqliteException>()),
    );
    await insertProfile(
      userId: 'user-2',
      ownerUserId: 'user-2',
      mode: 'conservative',
    );

    final rows = await db
        .customSelect(
          'SELECT user_id FROM options_strategy_profile ORDER BY user_id',
        )
        .get();
    expect(rows.map((r) => r.read<String>('user_id')), ['user-1', 'user-2']);
  });

  test(
    'income strategy plans are unique per owner and canonical asset',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);

      Future<void> insertPlan({
        required String id,
        required String ownerUserId,
      }) {
        return db.customStatement(
          '''
        INSERT INTO income_strategy_plans (
          id,
          asset_id,
          symbol,
          market,
          currency,
          sleeve_intents_json,
          owner_user_id,
          updated_at,
          updated_by_device,
          hlc
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
          [
            id,
            'nasdaq:AAPL',
            'AAPL',
            'nasdaq',
            'USD',
            '{"wheel":{"enabled":true,"settings":{}}}',
            ownerUserId,
            1,
            'device-1',
            '1:device-1',
          ],
        );
      }

      await insertPlan(id: 'plan-user-1', ownerUserId: 'user-1');
      await expectLater(
        insertPlan(id: 'duplicate', ownerUserId: 'user-1'),
        throwsA(isA<SqliteException>()),
      );
      await insertPlan(id: 'plan-user-2', ownerUserId: 'user-2');

      final rows = await db
          .customSelect('SELECT id FROM income_strategy_plans ORDER BY id')
          .get();
      expect(rows.map((r) => r.read<String>('id')), [
        'plan-user-1',
        'plan-user-2',
      ]);
    },
  );

  test('fresh schema creates sync and local-only support objects', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    final objects = await db.customSelect('''
          SELECT name, type
          FROM sqlite_master
          WHERE name IN (
            'op_outbox',
            'idx_op_outbox_created',
            'sync_meta',
            'domain_event_log',
            'idx_domain_event_log_entity',
            'events',
            'idx_events_owner_time',
            'memories',
            'idx_memories_source',
            'memory_embeddings',
            'idx_memory_embeddings_fingerprint',
            'options_opportunity_cache',
            'idx_options_opp_owner_scanned',
            'recurring_pattern_observations',
            'idx_recurring_pattern_obs_series',
            'knowledge_inbox_triage',
            'idx_knowledge_inbox_triage_owner_triaged',
            'agent_runs',
            'idx_agent_runs_agent_started',
            'agent_runtime_checkpoints',
            'idx_agent_runtime_checkpoints_pending',
            'agent_artifacts',
            'idx_agent_artifacts_domain_created',
            'agent_preferences',
            'idx_agent_preferences_owner',
            'data_maintenance_runs',
            'idx_data_maintenance_runs_owner_started',
            'securities_catalog_fts'
          )
          ''').get();

    final names = objects.map((row) => row.read<String>('name')).toSet();
    expect(
      names,
      containsAll([
        'op_outbox',
        'idx_op_outbox_created',
        'sync_meta',
        'domain_event_log',
        'idx_domain_event_log_entity',
        'events',
        'idx_events_owner_time',
        'memories',
        'idx_memories_source',
        'memory_embeddings',
        'idx_memory_embeddings_fingerprint',
        'options_opportunity_cache',
        'idx_options_opp_owner_scanned',
        'recurring_pattern_observations',
        'idx_recurring_pattern_obs_series',
        'knowledge_inbox_triage',
        'idx_knowledge_inbox_triage_owner_triaged',
        'agent_runs',
        'idx_agent_runs_agent_started',
        'agent_runtime_checkpoints',
        'idx_agent_runtime_checkpoints_pending',
        'agent_artifacts',
        'idx_agent_artifacts_domain_created',
        'agent_preferences',
        'idx_agent_preferences_owner',
        'data_maintenance_runs',
        'idx_data_maintenance_runs_owner_started',
        'securities_catalog_fts',
      ]),
    );
  });

  test('op_outbox enforces unique operation ids', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    Future<void> insertOutboxOp({required String opId, required String rowId}) {
      return db.customStatement(
        '''
        INSERT INTO op_outbox (
          op_id,
          table_name,
          row_id,
          created_at
        ) VALUES (?, ?, ?, ?)
        ''',
        [opId, 'assets', rowId, DateTime.utc(2026, 6, 20).toIso8601String()],
      );
    }

    await insertOutboxOp(opId: 'op-1', rowId: 'asset-1');
    await insertOutboxOp(opId: 'op-2', rowId: 'asset-1');
    await expectLater(
      insertOutboxOp(opId: 'op-1', rowId: 'asset-2'),
      throwsA(isA<SqliteException>()),
    );

    final rows = await db
        .customSelect('SELECT op_id, row_id FROM op_outbox ORDER BY op_id')
        .get();
    expect(rows.map((row) => row.read<String>('op_id')), ['op-1', 'op-2']);
    expect(rows.map((row) => row.read<String>('row_id')).toSet(), {'asset-1'});
  });

  test('deleting a chat session cascades to its messages', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    await db.customStatement(
      '''
      INSERT INTO chat_sessions (
        id,
        owner_user_id,
        title,
        created_at,
        updated_at,
        last_message_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      ['session-1', 'user-1', 'Review', 1, 1, 2],
    );
    for (final message in ['message-1', 'message-2']) {
      await db.customStatement(
        '''
        INSERT INTO chat_messages (
          id,
          session_id,
          owner_user_id,
          role,
          content,
          status,
          created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          message,
          'session-1',
          'user-1',
          message == 'message-1' ? 'user' : 'assistant',
          'content',
          'complete',
          2,
        ],
      );
    }

    await db.customStatement('DELETE FROM chat_sessions WHERE id = ?', [
      'session-1',
    ]);

    final remainingMessages = await db
        .customSelect(
          'SELECT id FROM chat_messages WHERE session_id = ?',
          variables: [Variable.withString('session-1')],
        )
        .get();
    expect(remainingMessages, isEmpty);
  });

  test('domain event log enforces known event kinds', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);

    Future<void> insertEvent({required String id, required String kind}) {
      return db.customStatement(
        '''
        INSERT INTO domain_event_log (
          id,
          entity_table,
          entity_id,
          event_kind,
          actor_user_id,
          actor_device_id,
          recorded_at,
          hlc,
          before_json,
          after_json,
          reason
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          id,
          'accounts',
          'account-1',
          kind,
          'user-1',
          'device-1',
          '2026-01-01T00:00:00.000Z',
          '1:device-1',
          null,
          '{}',
          null,
        ],
      );
    }

    await expectLater(
      insertEvent(id: 'invalid', kind: 'renamed'),
      throwsA(isA<SqliteException>()),
    );

    await insertEvent(id: 'created', kind: 'created');
    final row = await db
        .customSelect(
          'SELECT event_kind FROM domain_event_log WHERE id = ?',
          variables: [Variable.withString('created')],
        )
        .getSingle();
    expect(row.read<String>('event_kind'), 'created');
  });

  test('migrates v3 legacy account taxonomy to current enum labels', () async {
    final dir = await Directory.systemTemp.createTemp('naviwealth_migration_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');

    final legacy = sqlite3.open(file.path);
    try {
      legacy
        ..execute('''
          CREATE TABLE accounts (
            id                  TEXT PRIMARY KEY,
            name                TEXT NOT NULL,
            type                TEXT NOT NULL,
            category            TEXT NOT NULL,
            currency            TEXT NOT NULL,
            owner_user_id       TEXT NOT NULL,
            updated_at          INTEGER NOT NULL,
            updated_by_device   TEXT NOT NULL,
            hlc                 TEXT NOT NULL
          )
        ''')
        ..execute('''
          CREATE TABLE chat_sessions (
            id              TEXT PRIMARY KEY,
            owner_user_id   TEXT NOT NULL,
            title           TEXT NOT NULL,
            model           TEXT,
            created_at      INTEGER NOT NULL,
            updated_at      INTEGER NOT NULL,
            last_message_at INTEGER
          )
        ''')
        ..execute('''
          CREATE TABLE chat_messages (
            id                  TEXT PRIMARY KEY,
            session_id          TEXT NOT NULL,
            owner_user_id       TEXT NOT NULL,
            role                TEXT NOT NULL,
            content             TEXT NOT NULL DEFAULT '',
            tool_calls_json     TEXT,
            text_segments_json  TEXT,
            status              TEXT NOT NULL,
            error_message       TEXT,
            stop_reason         TEXT,
            created_at          INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES chat_sessions(id)
              ON DELETE CASCADE
          )
        ''');

      void insertLegacyAccount(String id, String type) {
        legacy.execute(
          '''
          INSERT INTO accounts (
            id,
            name,
            type,
            category,
            currency,
            owner_user_id,
            updated_at,
            updated_by_device,
            hlc
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [id, id, type, 'asset', 'CNY', 'u1', 1, 'dev1', '1:dev1'],
        );
      }

      insertLegacyAccount('brokerage-account', 'brokerage');
      insertLegacyAccount('crypto-wallet', 'cryptoWallet');
      insertLegacyAccount('real-estate', 'realEstate');
      insertLegacyAccount('vehicle', 'vehicle');
      insertLegacyAccount('other-asset', 'other');
      legacy.execute('PRAGMA user_version = 3');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final rows = await db.customSelect('''
          SELECT id, type, category
          FROM accounts
          ORDER BY id
          ''').get();
    expect(
      {
        for (final row in rows)
          row.read<String>('id'): (
            type: row.read<String>('type'),
            category: row.read<String>('category'),
          ),
      },
      <String, ({String type, String category})>{
        'brokerage-account': (type: 'broker', category: 'asset'),
        'crypto-wallet': (type: 'crypto', category: 'asset'),
        'other-asset': (type: 'asset', category: 'asset'),
        'real-estate': (type: 'asset', category: 'asset'),
        'vehicle': (type: 'asset', category: 'asset'),
      },
    );

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
  });

  test('migrates v21 with pre-existing dedupe columns idempotently', () async {
    final dir = await Directory.systemTemp.createTemp('naviwealth_migration_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');

    final legacy = sqlite3.open(file.path);
    try {
      for (final table in ['knowledge_notes', 'knowledge_concepts']) {
        legacy.execute('''
          CREATE TABLE $table (
            id TEXT PRIMARY KEY,
            merged_into_id TEXT
          )
        ''');
      }
      for (final table in [
        'knowledge_principles',
        'knowledge_assumptions',
        'knowledge_decisions',
        'knowledge_experiments',
      ]) {
        legacy.execute('''
          CREATE TABLE $table (
            id TEXT PRIMARY KEY
          )
        ''');
      }
      legacy
        ..execute('''
          CREATE TABLE options_trade_journal (
            id TEXT PRIMARY KEY
          )
        ''')
        ..execute('''
          CREATE TABLE chat_messages (
            id TEXT PRIMARY KEY
          )
        ''')
        ..execute('PRAGMA user_version = 21');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    Future<Set<String>> columnNames(String table) async {
      final rows = await db.customSelect('PRAGMA table_info($table)').get();
      return rows.map((row) => row.read<String>('name')).toSet();
    }

    expect(
      await columnNames('knowledge_notes'),
      containsAll(['id', 'merged_into_id']),
    );
    expect(
      await columnNames('knowledge_principles'),
      containsAll(['id', 'merged_into_id']),
    );
    expect(
      await columnNames('options_trade_journal'),
      containsAll([
        'id',
        'brokerage_account_id',
        'cash_account_id',
        'underlying_market',
        'strike_price',
        'contract_size',
        'expiration_at',
        'fees',
        'contract_quantity',
      ]),
    );
    expect(await columnNames('chat_messages'), contains('progress_json'));

    final observations = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name='recurring_pattern_observations'",
        )
        .get();
    expect(observations, hasLength(1));

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
  });

  test('migrates v25 chat messages to v26 progress descriptors', () async {
    final dir = await Directory.systemTemp.createTemp('naviwealth_migration_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');

    final legacy = sqlite3.open(file.path);
    try {
      legacy
        ..execute('''
          CREATE TABLE chat_sessions (
            id              TEXT PRIMARY KEY,
            owner_user_id   TEXT NOT NULL,
            title           TEXT NOT NULL,
            model           TEXT,
            created_at      INTEGER NOT NULL,
            updated_at      INTEGER NOT NULL,
            last_message_at INTEGER
          )
        ''')
        ..execute('''
          CREATE TABLE chat_messages (
            id                  TEXT PRIMARY KEY,
            session_id          TEXT NOT NULL,
            owner_user_id       TEXT NOT NULL,
            role                TEXT NOT NULL,
            content             TEXT NOT NULL DEFAULT '',
            tool_calls_json     TEXT,
            text_segments_json  TEXT,
            reasoning_text      TEXT,
            usage_json          TEXT,
            status              TEXT NOT NULL,
            error_message       TEXT,
            stop_reason         TEXT,
            created_at          INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES chat_sessions(id)
              ON DELETE CASCADE
          )
        ''')
        ..execute(
          '''
          INSERT INTO chat_sessions (
            id,
            owner_user_id,
            title,
            created_at,
            updated_at
          ) VALUES (?, ?, ?, ?, ?)
          ''',
          ['s1', 'u1', 'Session', 1, 1],
        )
        ..execute(
          '''
          INSERT INTO chat_messages (
            id,
            session_id,
            owner_user_id,
            role,
            content,
            status,
            created_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
          ['m1', 's1', 'u1', 'assistant', 'Working', 'streaming', 2],
        )
        ..execute('PRAGMA user_version = 25');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final columns = await db
        .customSelect('PRAGMA table_info(chat_messages)')
        .get();
    expect(
      columns.map((r) => r.read<String>('name')),
      contains('progress_json'),
    );

    final row = await db
        .customSelect(
          '''
          SELECT content, progress_json
          FROM chat_messages
          WHERE id = ?
          ''',
          variables: [Variable.withString('m1')],
        )
        .getSingle();
    expect(row.read<String>('content'), 'Working');
    expect(row.read<String?>('progress_json'), null);
  });

  test('migrates v31 agent tables through presentation additions', () async {
    final dir = await Directory.systemTemp.createTemp('naviwealth_migration_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');

    final legacy = sqlite3.open(file.path);
    try {
      legacy
        ..execute('''
          CREATE TABLE agent_runs (
            id            TEXT PRIMARY KEY,
            owner_user_id TEXT NOT NULL,
            agent_id      TEXT NOT NULL,
            agent_name    TEXT NOT NULL,
            status        TEXT NOT NULL,
            trigger       TEXT NOT NULL,
            started_at    INTEGER NOT NULL,
            finished_at   INTEGER,
            summary       TEXT,
            error         TEXT,
            memory_id     TEXT,
            artifact_id   TEXT
          )
        ''')
        ..execute('''
          CREATE TABLE agent_artifacts (
            id             TEXT PRIMARY KEY,
            owner_user_id  TEXT NOT NULL,
            agent_id       TEXT NOT NULL,
            domain         TEXT NOT NULL,
            kind           TEXT NOT NULL,
            severity       TEXT NOT NULL,
            title          TEXT NOT NULL,
            summary        TEXT NOT NULL,
            insights_json  TEXT NOT NULL,
            evidence_json  TEXT NOT NULL,
            actions_json   TEXT NOT NULL,
            memory_id      TEXT,
            trace_id       TEXT,
            created_at     INTEGER NOT NULL,
            expires_at     INTEGER
          )
        ''')
        ..execute(
          '''
          INSERT INTO agent_runs (
            id,
            owner_user_id,
            agent_id,
            agent_name,
            status,
            trigger,
            started_at,
            finished_at,
            summary,
            memory_id,
            artifact_id
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
          [
            'weekly_wealth_review:1',
            'u1',
            'weekly_wealth_review',
            'Weekly Wealth Review',
            'ready',
            'schedule',
            1,
            2,
            'Ready',
            'memory-1',
            'artifact-1',
          ],
        )
        ..execute(
          '''
          INSERT INTO agent_artifacts (
            id,
            owner_user_id,
            agent_id,
            domain,
            kind,
            severity,
            title,
            summary,
            insights_json,
            evidence_json,
            actions_json,
            memory_id,
            trace_id,
            created_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
          [
            'artifact-1',
            'u1',
            'weekly_wealth_review',
            'finance',
            'review',
            'info',
            'Weekly Wealth Review',
            'Ready',
            '[]',
            '[]',
            '[]',
            'memory-1',
            'trace-1',
            1,
          ],
        )
        ..execute('PRAGMA user_version = 31');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    Future<Set<String>> columns(String table) async {
      final rows = await db.customSelect('PRAGMA table_info($table)').get();
      return rows.map((row) => row.read<String>('name')).toSet();
    }

    expect(await columns('agent_runs'), contains('trace_id'));
    expect(
      await columns('agent_artifacts'),
      containsAll(['dismissed_at', 'snoozed_until', 'presentation_json']),
    );

    final run = await db
        .customSelect(
          '''
          SELECT summary, artifact_id, trace_id
          FROM agent_runs
          WHERE id = ?
          ''',
          variables: [Variable.withString('weekly_wealth_review:1')],
        )
        .getSingle();
    expect(run.read<String>('summary'), 'Ready');
    expect(run.read<String>('artifact_id'), 'artifact-1');
    expect(run.read<String?>('trace_id'), null);

    final artifact = await db
        .customSelect(
          '''
          SELECT trace_id, dismissed_at, snoozed_until, presentation_json
          FROM agent_artifacts
          WHERE id = ?
          ''',
          variables: [Variable.withString('artifact-1')],
        )
        .getSingle();
    expect(artifact.read<String>('trace_id'), 'trace-1');
    expect(artifact.read<int?>('dismissed_at'), null);
    expect(artifact.read<int?>('snoozed_until'), null);
    expect(artifact.read<String>('presentation_json'), '{}');

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
  });

  test('migrates v38 by creating agent runtime checkpoints', () async {
    final dir = await Directory.systemTemp.createTemp(
      'naviwealth_checkpoint_migration_',
    );
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');
    final legacy = sqlite3.open(file.path);
    try {
      legacy.execute('PRAGMA user_version = 38');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'agent_runtime_checkpoints'",
        )
        .get();
    expect(tables, hasLength(1));
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
  });

  test('migrates v41 by creating chat runtime snapshots', () async {
    final dir = await Directory.systemTemp.createTemp(
      'naviwealth_chat_snapshot_migration_',
    );
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');
    final legacy = sqlite3.open(file.path);
    try {
      legacy.execute('PRAGMA user_version = 41');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'agent_runtime_chat_snapshots'",
        )
        .get();
    expect(tables, hasLength(1));
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
  });

  test('migrates v55 chat snapshots to support pending interactions', () async {
    final dir = await Directory.systemTemp.createTemp(
      'naviwealth_chat_interaction_migration_',
    );
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');
    final legacy = sqlite3.open(file.path);
    try {
      legacy
        ..execute('''
            CREATE TABLE agent_runtime_chat_snapshots (
              owner_user_id    TEXT NOT NULL,
              turn_id          TEXT NOT NULL,
              snapshot_version INTEGER NOT NULL,
              revision         INTEGER NOT NULL DEFAULT 0,
              status           TEXT NOT NULL,
              snapshot_json    TEXT NOT NULL,
              created_at       INTEGER NOT NULL,
              updated_at       INTEGER NOT NULL,
              expires_at       INTEGER,
              PRIMARY KEY (owner_user_id, turn_id),
              CHECK (revision >= 0),
              CHECK (status IN (
                'ready_for_model',
                'requires_tool_results',
                'completed',
                'cancelled',
                'failed'
              ))
            )
          ''')
        ..execute('''
            CREATE INDEX idx_agent_runtime_chat_snapshots_pending
            ON agent_runtime_chat_snapshots(
              owner_user_id,
              status,
              updated_at DESC
            )
          ''')
        ..execute('''
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
            ) VALUES (
              'user-1',
              'turn-existing',
              1,
              2,
              'completed',
              '{}',
              1,
              2,
              NULL
            )
          ''')
        ..execute('PRAGMA user_version = 55');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

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
        ) VALUES (
          'user-1',
          'turn-interaction',
          1,
          0,
          'requires_interaction',
          '{}',
          3,
          3,
          NULL
        )
      ''');
    final rows = await db
        .customSelect(
          'SELECT turn_id, status, revision '
          'FROM agent_runtime_chat_snapshots ORDER BY turn_id',
        )
        .get();

    expect(rows, hasLength(2));
    expect(rows.first.read<String>('turn_id'), 'turn-existing');
    expect(rows.first.read<String>('status'), 'completed');
    expect(rows.first.read<int>('revision'), 2);
    expect(rows.last.read<String>('turn_id'), 'turn-interaction');
    expect(rows.last.read<String>('status'), 'requires_interaction');
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
  });

  test('rebuilds the pre-canonical options journal on upgrade', () async {
    final dir = await Directory.systemTemp.createTemp('naviwealth_migration_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');

    final legacy = sqlite3.open(file.path);
    try {
      legacy
        ..execute('''
          CREATE TABLE options_trade_journal (
            id                  TEXT PRIMARY KEY,
            strategy            TEXT NOT NULL,
            symbol              TEXT NOT NULL,
            option_symbol       TEXT NOT NULL,
            opened_at           INTEGER NOT NULL,
            closed_at           INTEGER,
            entry_credit        TEXT NOT NULL,
            exit_debit          TEXT,
            realized_pnl        TEXT,
            currency            TEXT NOT NULL,
            status              TEXT NOT NULL,
            notes               TEXT,
            owner_user_id       TEXT NOT NULL,
            updated_at          INTEGER NOT NULL,
            updated_by_device   TEXT NOT NULL,
            hlc                 TEXT NOT NULL,
            deleted_at          INTEGER
          )
        ''')
        ..execute('''
          CREATE TABLE chat_sessions (
            id              TEXT PRIMARY KEY,
            owner_user_id   TEXT NOT NULL,
            title           TEXT NOT NULL,
            model           TEXT,
            created_at      INTEGER NOT NULL,
            updated_at      INTEGER NOT NULL,
            last_message_at INTEGER
          )
        ''')
        ..execute('''
          CREATE TABLE chat_messages (
            id                  TEXT PRIMARY KEY,
            session_id          TEXT NOT NULL,
            owner_user_id       TEXT NOT NULL,
            role                TEXT NOT NULL,
            content             TEXT NOT NULL DEFAULT '',
            tool_calls_json     TEXT,
            text_segments_json  TEXT,
            reasoning_text      TEXT,
            usage_json          TEXT,
            status              TEXT NOT NULL,
            error_message       TEXT,
            stop_reason         TEXT,
            created_at          INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES chat_sessions(id)
              ON DELETE CASCADE
          )
        ''')
        ..execute(
          '''
          INSERT INTO options_trade_journal (
            id,
            strategy,
            symbol,
            option_symbol,
            opened_at,
            entry_credit,
            currency,
            status,
            notes,
            owner_user_id,
            updated_at,
            updated_by_device,
            hlc
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            'otj-1',
            'cash_secured_put',
            'AAPL',
            'AAPL260117P00150000',
            1,
            '2.50',
            'USD',
            'open',
            'legacy row',
            'u1',
            1,
            'dev1',
            '1:dev1',
          ],
        )
        ..execute(
          '''
          INSERT INTO chat_sessions (
            id,
            owner_user_id,
            title,
            created_at,
            updated_at
          ) VALUES (?, ?, ?, ?, ?)
          ''',
          ['s1', 'u1', 'Session', 1, 1],
        )
        ..execute(
          '''
          INSERT INTO chat_messages (
            id,
            session_id,
            owner_user_id,
            role,
            content,
            status,
            created_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
          ''',
          ['m1', 's1', 'u1', 'assistant', 'Working', 'streaming', 2],
        )
        ..execute('PRAGMA user_version = 23');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final optionsColumns = await db
        .customSelect('PRAGMA table_info(options_trade_journal)')
        .get();
    expect(
      optionsColumns.map((r) => r.read<String>('name')).toSet(),
      containsAll([
        'underlying_asset_id',
        'brokerage_account_id',
        'cash_account_id',
        'underlying_market',
        'strike_price',
        'contract_size',
        'expiration_at',
        'fees',
        'contract_quantity',
      ]),
    );

    final legacyRows = await db
        .customSelect('SELECT id FROM options_trade_journal')
        .get();
    expect(legacyRows, isEmpty);

    await db.customStatement(
      '''
      INSERT INTO options_trade_journal (
        id,
        underlying_asset_id,
        strategy,
        symbol,
        option_symbol,
        opened_at,
        entry_credit,
        currency,
        status,
        owner_user_id,
        updated_at,
        updated_by_device,
        hlc,
        brokerage_account_id,
        cash_account_id,
        underlying_market,
        strike_price,
        contract_size
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        'otj-2',
        'nasdaq:MSFT',
        'covered_call',
        'MSFT',
        'MSFT260117C00400000',
        2,
        '3.10',
        'USD',
        'open',
        'u1',
        2,
        'dev1',
        '2:dev1',
        'brokerage-1',
        'cash-1',
        'us_stock',
        '400',
        100,
      ],
    );

    final newJournalRow = await db
        .customSelect(
          '''
          SELECT
            symbol,
            brokerage_account_id,
            cash_account_id,
            underlying_market,
            strike_price,
            contract_size
          FROM options_trade_journal
          WHERE id = ?
          ''',
          variables: [Variable.withString('otj-2')],
        )
        .getSingle();
    expect(newJournalRow.read<String>('symbol'), 'MSFT');
    expect(newJournalRow.read<String?>('brokerage_account_id'), 'brokerage-1');
    expect(newJournalRow.read<String?>('cash_account_id'), 'cash-1');
    expect(newJournalRow.read<String?>('underlying_market'), 'us_stock');
    expect(newJournalRow.read<String?>('strike_price'), '400');
    expect(newJournalRow.read<int?>('contract_size'), 100);

    final observations = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name='recurring_pattern_observations'",
        )
        .get();
    expect(observations, hasLength(1));

    final chatColumns = await db
        .customSelect('PRAGMA table_info(chat_messages)')
        .get();
    expect(
      chatColumns.map((r) => r.read<String>('name')),
      contains('progress_json'),
    );
  });

  test('migrates v15 memory documents to the v26 memory runtime', () async {
    final dir = await Directory.systemTemp.createTemp('naviwealth_migration_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');

    final legacy = sqlite3.open(file.path);
    try {
      legacy
        ..execute('''
          CREATE TABLE options_trade_journal (
            id                  TEXT PRIMARY KEY,
            strategy            TEXT NOT NULL,
            symbol              TEXT NOT NULL,
            option_symbol       TEXT NOT NULL,
            opened_at           INTEGER NOT NULL,
            closed_at           INTEGER,
            entry_credit        TEXT NOT NULL,
            exit_debit          TEXT,
            realized_pnl        TEXT,
            currency            TEXT NOT NULL,
            status              TEXT NOT NULL,
            notes               TEXT,
            owner_user_id       TEXT NOT NULL,
            updated_at          INTEGER NOT NULL,
            updated_by_device   TEXT NOT NULL,
            hlc                 TEXT NOT NULL,
            deleted_at          INTEGER
          )
        ''')
        ..execute('''
          CREATE TABLE chat_sessions (
            id              TEXT PRIMARY KEY,
            owner_user_id   TEXT NOT NULL,
            title           TEXT NOT NULL,
            model           TEXT,
            created_at      INTEGER NOT NULL,
            updated_at      INTEGER NOT NULL,
            last_message_at INTEGER
          )
        ''')
        ..execute('''
          CREATE TABLE chat_messages (
            id                  TEXT PRIMARY KEY,
            session_id          TEXT NOT NULL,
            owner_user_id       TEXT NOT NULL,
            role                TEXT NOT NULL,
            content             TEXT NOT NULL DEFAULT '',
            tool_calls_json     TEXT,
            text_segments_json  TEXT,
            reasoning_text      TEXT,
            usage_json          TEXT,
            status              TEXT NOT NULL,
            error_message       TEXT,
            stop_reason         TEXT,
            created_at          INTEGER NOT NULL,
            FOREIGN KEY (session_id) REFERENCES chat_sessions(id)
              ON DELETE CASCADE
          )
        ''')
        ..execute('''
          CREATE TABLE memory_documents (
            id TEXT PRIMARY KEY,
            source TEXT,
            source_id TEXT,
            owner_user_id TEXT,
            title TEXT,
            body TEXT,
            fingerprint TEXT,
            dimension INTEGER,
            vector_bytes BLOB,
            updated_at INTEGER
          )
        ''')
        ..execute(
          '''
          INSERT INTO memory_documents (
            id,
            source,
            source_id,
            owner_user_id,
            title,
            body,
            fingerprint,
            dimension,
            vector_bytes,
            updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
          [
            'legacy-memory',
            'journal_entries',
            'je-1',
            'u1',
            'Legacy memory',
            'derived data',
            'stub-v0',
            2,
            Uint8List.fromList([0, 0, 0, 0]),
            1,
          ],
        )
        ..execute('PRAGMA user_version = 15');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final legacyTable = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name = 'memory_documents'",
        )
        .get();
    expect(legacyTable, isEmpty);

    final runtimeTables = await db.customSelect('''
          SELECT name
          FROM sqlite_master
          WHERE name IN ('memories', 'memory_embeddings', 'events')
          ''').get();
    expect(runtimeTables.map((row) => row.read<String>('name')).toSet(), {
      'memories',
      'memory_embeddings',
      'events',
    });

    final noteColumns = await db
        .customSelect('PRAGMA table_info(knowledge_notes)')
        .get();
    expect(
      noteColumns.map((row) => row.read<String>('name')),
      contains('merged_into_id'),
    );
  });

  test('migrates v34 ingest drafts with persisted recovery columns', () async {
    final dir = await Directory.systemTemp.createTemp('naviwealth_migration_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');

    final legacy = sqlite3.open(file.path);
    try {
      legacy
        ..execute('''
          CREATE TABLE ingest_drafts (
            draft_id TEXT PRIMARY KEY,
            owner_user_id TEXT NOT NULL,
            created_at_iso TEXT NOT NULL,
            source_kind TEXT NOT NULL,
            origin_label TEXT,
            parsed_json TEXT NOT NULL,
            confidence REAL NOT NULL,
            dedup_verdict TEXT NOT NULL,
            dedup_target_entry_id TEXT,
            trace_id TEXT,
            status TEXT NOT NULL,
            expires_at_iso TEXT
          )
        ''')
        ..execute('PRAGMA user_version = 34');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final columns = await db
        .customSelect('PRAGMA table_info(ingest_drafts)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      containsAll(['recovery_kind', 'recovery_apply_state_json']),
    );
  });

  test('migrates a partial v34 database with no ingest side table', () async {
    final dir = await Directory.systemTemp.createTemp('naviwealth_migration_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');

    final legacy = sqlite3.open(file.path);
    try {
      legacy.execute('PRAGMA user_version = 34');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final columns = await db
        .customSelect('PRAGMA table_info(ingest_drafts)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      containsAll(['draft_id', 'recovery_kind', 'recovery_apply_state_json']),
    );
  });

  test(
    'migrates v37 ingest lifecycle rows without losing recovery data',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'naviwealth_migration_',
      );
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final file = File('${dir.path}/naviwealth.db');
      const recoveryJson =
          '{"status":"applied","applied_entity_id":"entry-1",'
          '"applied_table":"journal_entries"}';

      final legacy = sqlite3.open(file.path);
      try {
        legacy
          ..execute('''
          CREATE TABLE ingest_drafts (
            draft_id TEXT PRIMARY KEY,
            owner_user_id TEXT NOT NULL,
            created_at_iso TEXT NOT NULL,
            source_kind TEXT NOT NULL,
            origin_label TEXT,
            parsed_json TEXT NOT NULL,
            confidence REAL NOT NULL,
            dedup_verdict TEXT NOT NULL,
            dedup_target_entry_id TEXT,
            trace_id TEXT,
            status TEXT NOT NULL,
            recovery_kind TEXT,
            recovery_apply_state_json TEXT,
            expires_at_iso TEXT
          )
        ''')
          ..execute(
            'INSERT INTO ingest_drafts ('
            'draft_id, owner_user_id, created_at_iso, source_kind, parsed_json, '
            'confidence, dedup_verdict, status, recovery_kind, '
            'recovery_apply_state_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              'draft-1',
              'owner-1',
              '2026-07-11T00:00:00.000Z',
              'csv',
              '{}',
              0.9,
              'newTxn',
              'pending',
              'finalize_applied',
              recoveryJson,
            ],
          )
          ..execute('PRAGMA user_version = 37');
      } finally {
        legacy.close();
      }

      final db = AppDatabase(
        DatabaseConnection(NativeDatabase(file, logStatements: false)),
      );
      addTearDown(db.close);

      final row = await db
          .customSelect(
            'SELECT status, recovery_kind, recovery_apply_state_json, revision, '
            'operation_token, invocation_started FROM ingest_drafts '
            "WHERE draft_id = 'draft-1'",
          )
          .getSingle();
      expect(row.read<String>('status'), 'pending');
      expect(row.read<String>('recovery_kind'), 'finalize_applied');
      expect(row.read<String>('recovery_apply_state_json'), recoveryJson);
      expect(row.read<int>('revision'), 0);
      expect(row.readNullable<String>('operation_token'), equals(null));
      expect(row.read<int>('invocation_started'), 0);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), db.schemaVersion);
    },
  );

  test('v47 upgrade creates dividend forecasts and portfolio tables', () async {
    final dir = await Directory.systemTemp.createTemp(
      'naviwealth-dividend-forecast-migration-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/naviwealth.db');
    final legacy = sqlite3.open(file.path);
    try {
      legacy.execute('PRAGMA user_version = 47');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final columns = await db
        .customSelect('PRAGMA table_info(dividend_forecast_snapshots)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      contains('predicted_net'),
    );
    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final tableNames = tables.map((row) => row.read<String>('name')).toSet();
    expect(tableNames, contains('investment_portfolios'));
    expect(tableNames, contains('portfolio_strategy_configs'));
    expect(tableNames, contains('portfolio_rebalance_groups'));
    expect(tableNames, contains('portfolio_capital_assignments'));
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
  });

  test('v53 upgrade creates local conversation checkpoints', () async {
    final dir = await Directory.systemTemp.createTemp(
      'naviwealth-conversation-checkpoint-migration-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/naviwealth.db');
    final legacy = sqlite3.open(file.path);
    try {
      legacy
        ..execute('''
          CREATE TABLE chat_sessions (
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
        ''')
        ..execute('PRAGMA user_version = 53');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final columns = await db
        .customSelect('PRAGMA table_info(conversation_checkpoints)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      containsAll([
        'session_id',
        'summary_through_message_id',
        'source_fingerprint',
        'payload_json',
      ]),
    );
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
  });

  test('v54 upgrade creates memory candidate staging', () async {
    final dir = await Directory.systemTemp.createTemp(
      'naviwealth-memory-candidate-migration-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/naviwealth.db');
    final legacy = sqlite3.open(file.path);
    try {
      legacy.execute('PRAGMA user_version = 54');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final columns = await db
        .customSelect('PRAGMA table_info(memory_candidates)')
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      containsAll(['id', 'proposal_id', 'operation', 'status', 'payload_json']),
    );
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
  });
}
