import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/data_management/data_management.dart';
import 'package:naviwealth/core/logging/app_logger.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/row_applier.dart';
import 'package:naviwealth/core/sync/sync_api_client.dart';
import 'package:naviwealth/core/sync/sync_engine.dart';
import 'package:naviwealth/core/sync/sync_payload_store.dart';
import 'package:naviwealth/core/sync/sync_status.dart';
import 'package:naviwealth/core/sync/sync_table_registry.dart';
import 'package:talker/talker.dart';

import '../persistence/test_database.dart';
import '_fake_api.dart';

const _owner = 'user-1';
String _version(int wall) =>
    Hlc(wallMillis: wall, counter: 0, nodeId: 'peer').toString();

RowChange _account(
  int wall, {
  Map<String, Object?> extra = const {},
  String owner = _owner,
}) => RowChange(
  table: 'fin:accounts',
  id: 'account',
  version: _version(wall),
  deleted: false,
  payload: {
    'id': 'account',
    'type': 'cash',
    'name': 'Cash',
    'currency': 'CNY',
    'owner_user_id': owner,
    'updated_at': 1700000000,
    'updated_by_device': 'peer',
    'hlc': _version(wall),
    ...extra,
  },
);

SyncEngine _engine(
  AppDatabase db,
  RowApplier applier,
  FakeSyncApiClient api,
  String device,
) => SyncEngine(
  api: api,
  pending: DriftPendingRows(db, ownerUserId: _owner),
  cursors: DriftCursorStore(db),
  applier: applier,
  deviceId: device,
  statusBus: SyncStatusBus(),
);

void main() {
  setUpAll(
    () => AppLogger.bootstrap(
      AppLogger(
        environment: AppEnvironment.dev,
        talker: Talker(settings: TalkerSettings(useConsoleLogs: false)),
      ),
    ),
  );
  test('a sync cycle preserves another owner\'s queued mutations', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final applier = RowApplier(db);
    await applier.applyAll([_account(1000)]);
    final foreign = _account(1000, owner: 'user-2');
    await applier.applyAll([
      RowChange(
        table: foreign.table,
        id: 'foreign',
        payload: {...foreign.payload!, 'id': 'foreign'},
        version: foreign.version,
        deleted: false,
      ),
    ]);
    for (final id in ['account', 'foreign', 'gone']) {
      await DriftOutboxStore(db).enqueue(table: 'accounts', rowId: id);
    }
    final pending = DriftPendingRows(db, ownerUserId: _owner);
    expect(
      (await pending.pointers()).map((p) => p.rowId),
      unorderedEquals(['account', 'gone']),
    );
    expect(await pending.depth(), 2);
    await applier.prepareCompatibility();
    final api = FakeSyncApiClient();
    final result = await _engine(
      db,
      RowApplier(db, ownerUserId: _owner),
      api,
      'device',
    ).run();
    expect(result.errors, isEmpty);
    expect(result.pushed, 1);
    expect(await pending.depth(), 0);
    expect((await DriftPendingRows(db).pointers()).single.rowId, 'foreign');
    expect(api.syncCalls.expand((call) => call.changes).map((row) => row.id), [
      'account',
    ]);
  });
  test(
    'mixed-version edits retain opaque fields and hydrate them after upgrade',
    () async {
      final oldDb = makeTestDatabase();
      final newDb = makeTestDatabase();
      addTearDown(oldDb.close);
      addTearDown(newDb.close);
      await oldDb.customStatement('ALTER TABLE accounts DROP COLUMN color');
      final old = RowApplier(oldDb, ownerUserId: _owner);
      await old.prepareCompatibility();
      final remote = _account(
        2000,
        extra: {
          'color': '#abcdef',
          'future_policy': {'mode': 'manual', 'limit': 12},
        },
      );
      await old.applyAll([remote]);
      await old.finishCompatibilityReplay();
      await DriftCursorStore(oldDb).writeSeq(42);
      await oldDb.customStatement(
        'UPDATE accounts SET name = ?, hlc = ? WHERE id = ?',
        ['Edited locally', _version(3000), 'account'],
      );
      await DriftOutboxStore(oldDb)
          .enqueue(table: 'accounts', rowId: 'account');
      final pushed = (await DriftPendingRows(
        oldDb,
        ownerUserId: _owner,
      ).readRow('accounts', 'account'))!;
      expect(pushed['name'], 'Edited locally');
      expect(pushed['color'], '#abcdef');
      expect(pushed['future_policy'], remote.payload!['future_policy']);
      await RowApplier(newDb, ownerUserId: _owner).applyAll([
        RowChange(
          table: remote.table,
          id: remote.id,
          payload: pushed,
          version: _version(3000),
          deleted: false,
        ),
      ]);
      expect((await newDb.select(newDb.accounts).getSingle()).color, '#abcdef');

      await oldDb.customStatement('ALTER TABLE accounts ADD COLUMN color TEXT');
      expect(await old.prepareCompatibility(), isTrue);
      expect(await DriftCursorStore(oldDb).readSeq(), 0);
      expect(
        (await oldDb
                .customSelect('SELECT color, name FROM accounts')
                .getSingle())
            .data,
        {'color': '#abcdef', 'name': 'Edited locally'},
      );
      expect(await DriftOutboxStore(oldDb).depth(), 1);
      expect(
        await old.applyAll([remote]),
        0,
      ); // Old remote state never rolls back a local edit.
      await old.finishCompatibilityReplay();
      await DriftCursorStore(oldDb).writeSeq(43);
      expect(await old.prepareCompatibility(), isFalse);
      expect(await DriftCursorStore(oldDb).readSeq(), 43);
      expect(
        await SyncPayloadStore(oldDb).extras('accounts', 'account', _owner),
        {'future_policy': remote.payload!['future_policy']},
      );
    },
  );

  test('schema replay hydrates equal versions from clients predating opaque-field preservation', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final applier = RowApplier(db, ownerUserId: _owner);
    await applier.applyAll([_account(1000)]);
    await applier.prepareCompatibility();
    final remote = _account(1000, extra: {'color': '#123456'});
    expect(await applier.applyAll([remote]), 1);
    expect((await db.select(db.accounts).getSingle()).color, '#123456');
    await applier.finishCompatibilityReplay();
    expect(await applier.applyAll([remote]), 0);
  });

  test('new table registration replays a previously skipped row after cursor advancement', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final api = FakeSyncApiClient();
    api.seedRemote(
      RowChange(
        table: 'fin:tags',
        id: 'new-tag',
        version: _version(1000),
        deleted: false,
        payload: {
          'id': 'new-tag',
          'name': 'New table',
          'kind': 'custom',
          'owner_user_id': _owner,
          'updated_at': 1700000000,
          'updated_by_device': 'peer',
          'hlc': _version(1000),
        },
      ),
      deviceId: 'peer',
    );
    final old = RowApplier(
      db,
      ownerUserId: _owner,
      registrations: [kSyncTableRegistry['accounts']!],
    );
    await old.prepareCompatibility();
    expect((await _engine(db, old, api, 'device').run()).errors, isEmpty);
    expect(await DriftCursorStore(db).readSeq(), 1);
    expect(await db.select(db.tags).get(), isEmpty);

    final upgraded = RowApplier(db, ownerUserId: _owner);
    expect(await upgraded.prepareCompatibility(), isTrue);
    final result = await _engine(db, upgraded, api, 'device').run();
    expect(result.errors, isEmpty);
    expect((await db.select(db.tags).getSingle()).id, 'new-tag');
    expect(api.syncCalls.last.since, 0);
    expect(await upgraded.prepareCompatibility(), isFalse);
  });

  test(
    'interrupted schema replay remains enabled until the final successful page',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final applier = RowApplier(db, ownerUserId: _owner);
      await applier.prepareCompatibility();
      final api = FakeSyncApiClient()..pageLimit = 1;
      api.seedRemote(_account(1000), deviceId: 'peer');
      final second = _account(2000);
      api.seedRemote(
        RowChange(
          table: second.table,
          id: 'account-2',
          payload: {...second.payload!, 'id': 'account-2'},
          version: second.version,
          deleted: false,
        ),
        deviceId: 'peer',
      );
      // A direct first-page application models a process ending before the
      // engine drains the pull. The persistent replay marker must survive it.
      final first = await api.sync(deviceId: 'device', since: 0, changes: []);
      expect(first.more, isTrue);
      await applier.applyAll(first.changes);
      await DriftCursorStore(db).writeSeq(first.seq);
      expect(
        await db
            .customSelect(
              "SELECT value FROM sync_meta WHERE key = 'sync.schema_replay'",
            )
            .getSingleOrNull(),
        isNotNull,
      );
      expect(await RowApplier(db).prepareCompatibility(), isFalse);
      await _engine(
        db,
        RowApplier(db, ownerUserId: _owner),
        api,
        'device',
      ).run();
      expect(
        await db
            .customSelect(
              "SELECT value FROM sync_meta WHERE key = 'sync.schema_replay'",
            )
            .getSingleOrNull(),
        isNull,
      );
    },
  );

  test(
    'opaque fields follow LWW, explicit nulls and owner isolation',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final applier = RowApplier(db, ownerUserId: _owner);
      await applier.applyAll([
        _account(2000, extra: {'future_field': 'latest'}),
      ]);
      await applier.applyAll([
        _account(1000, extra: {'future_field': 'stale'}),
      ]);
      expect(
        (await DriftPendingRows(db)
            .readRow('accounts', 'account'))!['future_field'],
        'latest',
      );
      await applier.applyAll([
        _account(3000, extra: {'future_field': null}),
      ]);
      expect(
        (await DriftPendingRows(db)
            .readRow('accounts', 'account'))!['future_field'],
        isNull,
      );
      expect(
        await DriftPendingRows(
          db,
          ownerUserId: 'user-2',
        ).readRow('accounts', 'account'),
        isNull,
      );
      await expectLater(
        applier.applyAll([_account(4000, owner: 'user-2')]),
        throwsStateError,
      );
    },
  );

  test('generation reset removes opaque state only for the current owner and domain', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = SyncPayloadStore(db);
    await store.writeExtras('accounts', 'a', _owner, {'future': 1});
    await store.writeExtras('accounts', 'b', 'user-2', {'future': 2});
    await store.writeExtras('knowledge_notes', 'n', _owner, {'future': 3});
    await DataManagementService(
      database: db,
      ownerUserId: _owner,
      specs: [
        DomainDataManagementSpec(
          scope: DomainScope.finance,
          label: 'Finance',
          sourceTables: syncDataTablesForPrefix(kFinanceDomainPrefix),
        ),
      ],
    ).resetLocalDomain(DomainScope.finance);
    expect(await store.extras('accounts', 'a', _owner), isEmpty);
    expect(await store.extras('accounts', 'b', 'user-2'), {'future': 2});
    expect(await store.extras('knowledge_notes', 'n', _owner), {'future': 3});
  });

  test('page rollback also rolls back opaque state and wire namespaces cannot cross domains', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final applier = RowApplier(db, ownerUserId: _owner);
    await expectLater(
      applier.applyAll([
        _account(1000, extra: {'future': 'must-roll-back'}),
        RowChange(
          table: 'fin:tags',
          id: 'invalid',
          version: _version(1000),
          deleted: false,
          payload: {'owner_user_id': _owner},
        ),
      ]),
      throwsA(anything),
    );
    expect(await db.select(db.accounts).get(), isEmpty);
    expect(
      await SyncPayloadStore(db).extras('accounts', 'account', _owner),
      isEmpty,
    );
    final wrong = _account(1000);
    final report = await applier.applyWithReport([
      RowChange(
        table: 'health:accounts',
        id: wrong.id,
        payload: wrong.payload,
        version: wrong.version,
        deleted: false,
      ),
    ]);
    expect(report.skippedUnsupportedTable, 1);
    expect(await db.select(db.accounts).get(), isEmpty);
  });
}
