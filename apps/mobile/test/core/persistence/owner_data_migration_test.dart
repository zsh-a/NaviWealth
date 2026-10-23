import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/owner_data_migration.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_payload_store.dart';
import 'package:naviwealth/core/sync/sync_scope.dart';

import 'owner_data_fixture.dart';
import 'test_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = makeTestDatabase());
  tearDown(() => db.close());

  test('every owner-bearing table has one explicit lifecycle policy', () async {
    final rows = await db
        .customSelect(
          'SELECT m.name FROM sqlite_master m JOIN pragma_table_info(m.name) p '
          "WHERE m.type = 'table' AND p.name = 'owner_user_id'",
        )
        .get();
    final tables = kOwnerDataTables.map((entry) => entry.table).toList();
    expect(tables.toSet(), hasLength(tables.length));
    expect(
      tables,
      unorderedEquals(rows.map((row) => row.read<String>('name'))),
    );
  });

  test(
    'transfer preserves source, confirmed data, vectors and chat links',
    () async {
      await seedOwnerData(db, 'source', 's');
      await seedOwnerData(db, 'unrelated', 'u');
      await OwnerDataMigration(db).transfer(from: 'source', to: 'destination');

      for (final entry in {
        'recurring_transactions': 'recurring',
        'personal_profile_facts': 'profile',
        'events': 'event',
        'memories': 'memory',
        'chat_sessions': 'chat',
        'chat_messages': 'message',
      }.entries) {
        expect(await ownerOf(db, entry.key, 's-${entry.value}'), 'destination');
        expect(await ownerOf(db, entry.key, 'u-${entry.value}'), 'unrelated');
      }
      final memory = await db
          .customSelect(
            'SELECT m.authority, m.source_id, m.source_event_id, e.dimension '
            'FROM memories m JOIN memory_embeddings e ON e.memory_id = m.id '
            "WHERE m.id = 's-memory'",
          )
          .getSingle();
      expect(memory.data, {
        'authority': 'user_confirmed',
        'source_id': 's-profile',
        'source_event_id': 's-event',
        'dimension': 1,
      });
      final chat = await db
          .customSelect(
            'SELECT s.owner_user_id AS session_owner, m.owner_user_id AS message_owner, m.content '
            'FROM chat_sessions s JOIN chat_messages m ON m.session_id = s.id '
            "WHERE s.id = 's-chat'",
          )
          .getSingle();
      expect(chat.data, {
        'session_owner': 'destination',
        'message_owner': 'destination',
        'content': 'keep me',
      });
      final checkpoints = await db
          .customSelect('SELECT session_id FROM conversation_checkpoints')
          .get();
      expect(checkpoints.map((r) => r.read<String>('session_id')), ['u-chat']);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );

  test(
    'singleton identity keys, dirty pointers and opaque fields move together',
    () async {
      await db.customStatement(
        'INSERT INTO settings (user_id, owner_user_id, base_currency, theme_mode, '
        'privacy_mode, cost_basis_method, updated_at, updated_by_device, hlc) '
        "VALUES ('source', 'source', 'CNY', 'system', 'normal', 'fifo', 1, 'device', '1.0000-device')",
      );
      await DriftOutboxStore(db).enqueue(table: 'settings', rowId: 'source');
      await SyncPayloadStore(db)
          .writeExtras('settings', 'source', 'source', {'future_field': 42});
      final owners = ['source', 'destination', 'unrelated'];
      final cursors = {
        for (final owner in owners)
          owner: DriftCursorStore(
            db,
            scope: SyncScope(ownerUserId: owner, domains: ['fin']),
          ),
      };
      for (final owner in owners) {
        await cursors[owner]!.writeSeq(100);
        await db.customStatement('INSERT INTO sync_meta VALUES (?, ?)', [
          'sync.backfill.6.$owner.device',
          'done',
        ]);
      }
      const clock = Hlc(wallMillis: 10, counter: 2, nodeId: 'device');
      await DriftLocalClockStore(db).write(clock);
      await OwnerDataMigration(db).transfer(from: 'source', to: 'destination');
      final settings = await db
          .customSelect('SELECT user_id, owner_user_id FROM settings')
          .getSingle();
      expect(settings.data, {
        'user_id': 'destination',
        'owner_user_id': 'destination',
      });
      final pending = await DriftPendingRows(
        db,
        ownerUserId: 'destination',
      ).pointers();
      expect(pending.single.rowId, 'destination');
      expect(
        await SyncPayloadStore(db)
            .extras('settings', 'destination', 'destination'),
        {'future_field': 42},
      );
      expect(await cursors['source']!.readSeq(), 0);
      expect(await cursors['destination']!.readSeq(), 0);
      expect(await cursors['unrelated']!.readSeq(), 100);
      expect(await DriftLocalClockStore(db).read(), clock);
      final markers = await db
          .customSelect(
            "SELECT key FROM sync_meta WHERE key LIKE 'sync.backfill.%'",
          )
          .get();
      expect(markers.map((r) => r.read<String>('key')), [
        'sync.backfill.6.unrelated.device',
      ]);
    },
  );

  test(
    'destination profile collision rolls back all data and preserves identity',
    () async {
      await seedOwnerData(db, 'source', 's');
      await seedProfileFact(db, 'destination', 'destination-profile');
      var committed = false;
      await expectLater(
        OwnerDataMigration(db).transfer(
          from: 'source',
          to: 'destination',
          commitIdentity: () async => committed = true,
        ),
        throwsA(isA<Exception>()),
      );
      expect(committed, isFalse);
      expect(
        await ownerOf(db, 'recurring_transactions', 's-recurring'),
        'source',
      );
      expect(
        await ownerOf(db, 'personal_profile_facts', 's-profile'),
        'source',
      );
      expect(
        await db.customSelect('SELECT * FROM conversation_checkpoints').get(),
        hasLength(1),
      );
    },
  );

  test(
    'failed identity persistence rolls back transfers and invalidations',
    () async {
      await seedOwnerData(db, 'source', 's');
      await expectLater(
        OwnerDataMigration(db).transfer(
          from: 'source',
          to: 'destination',
          commitIdentity: () async =>
              throw StateError('secure storage unavailable'),
        ),
        throwsStateError,
      );
      expect(
        await ownerOf(db, 'recurring_transactions', 's-recurring'),
        'source',
      );
      expect(await ownerOf(db, 'memories', 's-memory'), 'source');
      expect(
        await db.customSelect('SELECT * FROM conversation_checkpoints').get(),
        hasLength(1),
      );
    },
  );
}
