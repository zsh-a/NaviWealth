import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  test('v86 adds local-only corporate-action cache tables', () async {
    final dir = await Directory.systemTemp.createTemp(
      'naviwealth-corporate-action-cache-v86-',
    );
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final file = File('${dir.path}/naviwealth.db');
    final legacy = sqlite3.sqlite3.open(file.path);
    try {
      legacy.execute('PRAGMA user_version = 85');
    } finally {
      legacy.close();
    }

    final db = AppDatabase(
      DatabaseConnection(NativeDatabase(file, logStatements: false)),
    );
    addTearDown(db.close);

    final candidates = await db
        .customSelect('PRAGMA table_info(market_corporate_action_candidates)')
        .get();
    final candidateColumns = candidates
        .map((row) => row.read<String>('name'))
        .toSet();
    expect(
      candidateColumns,
      containsAll([
        'id',
        'source',
        'dataset',
        'source_key',
        'revision_hash',
        'identity_strength',
        'symbol',
        'market',
        'kind',
        'status',
        'record_date',
        'ex_date',
        'pay_date',
        'cash_per_share',
        'fetched_at',
      ]),
    );
    expect(
      candidateColumns.intersection({
        'owner_user_id',
        'hlc',
        'updated_by_device',
        'deleted_at',
      }),
      isEmpty,
    );

    final states = await db
        .customSelect('PRAGMA table_info(market_corporate_action_fetch_states)')
        .get();
    expect(
      states.map((row) => row.read<String>('name')),
      containsAll([
        'market',
        'symbol',
        'provider',
        'disposition',
        'fetched_at',
      ]),
    );

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 86);
  });
}
