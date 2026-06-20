import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

import 'test_database.dart';

void main() {
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
          max_underlying_exposure_pct,
          min_annualized_yield,
          min_open_interest,
          min_volume,
          max_bid_ask_spread_pct,
          owner_user_id,
          updated_at,
          updated_by_device,
          hlc
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
          '0.20',
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
    'approved underlyings are unique per owner market symbol pair',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);

      Future<void> insertUnderlying({
        required String id,
        required String ownerUserId,
        required String market,
        required String symbol,
      }) {
        return db.customStatement(
          '''
        INSERT INTO approved_underlyings (
          id,
          symbol,
          market,
          owner_user_id,
          updated_at,
          updated_by_device,
          hlc
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
          [id, symbol, market, ownerUserId, 1, 'device-1', '1:device-1'],
        );
      }

      await insertUnderlying(
        id: 'us_stock:AAPL',
        ownerUserId: 'user-1',
        market: 'us_stock',
        symbol: 'AAPL',
      );
      await expectLater(
        insertUnderlying(
          id: 'duplicate',
          ownerUserId: 'user-1',
          market: 'us_stock',
          symbol: 'AAPL',
        ),
        throwsA(isA<SqliteException>()),
      );
      await insertUnderlying(
        id: 'user2:us_stock:AAPL',
        ownerUserId: 'user-2',
        market: 'us_stock',
        symbol: 'AAPL',
      );
      await insertUnderlying(
        id: 'user1:hk_stock:AAPL',
        ownerUserId: 'user-1',
        market: 'hk_stock',
        symbol: 'AAPL',
      );

      final rows = await db
          .customSelect('SELECT id FROM approved_underlyings ORDER BY id')
          .get();
      expect(rows.map((r) => r.read<String>('id')), [
        'us_stock:AAPL',
        'user1:hk_stock:AAPL',
        'user2:us_stock:AAPL',
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

  test('migrates v23 options journal rows through v26 additions', () async {
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
        'brokerage_account_id',
        'cash_account_id',
        'underlying_market',
        'strike_price',
        'contract_size',
      ]),
    );

    final journalRow = await db
        .customSelect(
          '''
          SELECT symbol, notes, brokerage_account_id, strike_price
          FROM options_trade_journal
          WHERE id = ?
          ''',
          variables: [Variable.withString('otj-1')],
        )
        .getSingle();
    expect(journalRow.read<String>('symbol'), 'AAPL');
    expect(journalRow.read<String?>('notes'), 'legacy row');
    expect(journalRow.read<String?>('brokerage_account_id'), null);
    expect(journalRow.read<String?>('strike_price'), null);

    await db.customStatement(
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
        owner_user_id,
        updated_at,
        updated_by_device,
        hlc,
        brokerage_account_id,
        cash_account_id,
        underlying_market,
        strike_price,
        contract_size
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        'otj-2',
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
}
