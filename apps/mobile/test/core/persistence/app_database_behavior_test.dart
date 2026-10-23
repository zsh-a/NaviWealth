import 'package:drift/drift.dart';
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
        role,
        authority,
        provenance_json,
        scope,
        owner_user_id,
        title,
        summary,
        payload_json,
        entities_json,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        'mem-1',
        'semantic',
        'legacy',
        'legacy_unknown',
        '{}',
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
}
