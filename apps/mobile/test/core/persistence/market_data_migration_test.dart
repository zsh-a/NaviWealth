import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test(
    'v94 creates envelope cache without changing existing quote rows',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'naviwealth-market-v95-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/cache.db');
      final legacy = sqlite3.sqlite3.open(file.path);
      legacy.execute(
        'CREATE TABLE market_quotes (symbol TEXT PRIMARY KEY, price TEXT)',
      );
      legacy.execute("INSERT INTO market_quotes VALUES ('600519', '1500.25')");
      legacy.execute('PRAGMA user_version = 94');
      legacy.close();
      final db = AppDatabase(DatabaseConnection(NativeDatabase(file)));
      addTearDown(db.close);
      expect(await db.select(db.marketDataSnapshots).get(), isEmpty);
      final quote = await db
          .customSelect('SELECT price FROM market_quotes')
          .getSingle();
      expect(quote.read<String>('price'), '1500.25');
      await db
          .into(db.marketDataSnapshots)
          .insert(
            MarketDataSnapshotsCompanion.insert(
              requestKey: 'native-cn:v1:raw:test',
              envelope: '{}',
              fetchedAt: DateTime.utc(2026),
            ),
          );
      expect(await db.select(db.marketDataSnapshots).get(), hasLength(1));
    },
  );

  test('v77 market caches migrate without losing rows', () async {
    final dir = await Directory.systemTemp.createTemp('naviwealth-market-v78-');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');
    final legacy = sqlite3.sqlite3.open(file.path);
    try {
      legacy
        ..execute('''
          CREATE TABLE fx_rates (
            id TEXT PRIMARY KEY,
            base_currency TEXT NOT NULL,
            quote_currency TEXT NOT NULL,
            rate TEXT NOT NULL,
            as_of INTEGER NOT NULL,
            source TEXT
          )
        ''')
        ..execute('''
          CREATE TABLE market_quotes (
            symbol TEXT NOT NULL,
            source TEXT NOT NULL,
            currency TEXT NOT NULL,
            price TEXT NOT NULL,
            previous_close TEXT,
            open_price TEXT,
            day_high TEXT,
            day_low TEXT,
            volume INTEGER,
            exchange TEXT,
            as_of INTEGER NOT NULL,
            fetched_at INTEGER NOT NULL,
            PRIMARY KEY (symbol, source)
          )
        ''')
        ..execute('''
          CREATE TABLE market_history_bars (
            symbol TEXT NOT NULL,
            interval TEXT NOT NULL,
            as_of INTEGER NOT NULL,
            source TEXT NOT NULL,
            open_price TEXT NOT NULL,
            high TEXT NOT NULL,
            low TEXT NOT NULL,
            close_price TEXT NOT NULL,
            volume INTEGER,
            adjusted_close TEXT,
            fetched_at INTEGER NOT NULL,
            PRIMARY KEY (symbol, interval, as_of, source)
          )
        ''')
        ..execute('''
          CREATE TABLE market_symbol_searches (
            query TEXT NOT NULL,
            source TEXT NOT NULL,
            results TEXT NOT NULL,
            fetched_at INTEGER NOT NULL,
            PRIMARY KEY (query, source)
          )
        ''');
      legacy.execute('''
        INSERT INTO fx_rates
          (id, base_currency, quote_currency, rate, as_of, source)
        VALUES ('fx-1', 'USD', 'CNY', '7.2', 100, 'yfinance')
        ''');
      legacy.execute('''
        INSERT INTO market_quotes
          (symbol, source, currency, price, as_of, fetched_at)
        VALUES ('AAPL', 'yfinance', 'USD', '200', 100, 200)
        ''');
      legacy.execute('''
        INSERT INTO market_history_bars
          (symbol, interval, as_of, source, open_price, high, low, close_price,
           fetched_at)
        VALUES ('AAPL', '1d', 100, 'yfinance', '199', '201', '198', '200', 200)
        ''');
      legacy.execute('''
        INSERT INTO market_symbol_searches (query, source, results, fetched_at)
        VALUES ('apple', 'yfinance', '[]', 200)
        ''');
      legacy.execute('PRAGMA user_version = 77');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final fx = await db.customSelect('SELECT * FROM fx_rates').getSingle();
    expect(fx.read<String>('rate'), '7.2');
    expect(fx.read<int>('fetched_at'), 100);

    final quote = await db
        .customSelect('SELECT * FROM market_quotes')
        .getSingle();
    expect(quote.read<String>('market'), 'unknown');
    final history = await db
        .customSelect('SELECT * FROM market_history_bars')
        .getSingle();
    expect(history.read<String>('market'), 'unknown');
    final search = await db
        .customSelect('SELECT * FROM market_symbol_searches')
        .getSingle();
    expect(search.read<String>('market'), 'unknown');

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
  });
}
