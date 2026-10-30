import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/data_management/data_management.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';
import 'package:naviwealth/features/knowledge/data/bcr_github_client.dart';
import 'package:naviwealth/features/knowledge/data/bcr_github_credentials.dart';
import 'package:naviwealth/features/knowledge/data/bcr_knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/bcr_knowledge_sync_service.dart';
import 'package:naviwealth/features/knowledge/data_management/knowledge_data_management.dart';
import 'package:naviwealth/features/knowledge/domain/bcr_knowledge_connection.dart';

import '../../../core/persistence/test_database.dart';
import '../bcr_sync_test_fixture.dart';
import '../bcr_test_fixture.dart';

void main() {
  late AppDatabase db;
  late BcrKnowledgeRepository repository;
  late BcrGithubCredentials credentials;
  late FakeBcrGithubClient client;
  late BcrKnowledgeSyncService service;
  late String currentOwner;
  late DateTime now;
  final url = Uri.parse('https://notes.example.com/notes/knowledge');

  setUp(() {
    db = makeTestDatabase();
    repository = BcrKnowledgeRepository(db);
    credentials = BcrGithubCredentials(InMemoryKeyStore());
    client = FakeBcrGithubClient();
    currentOwner = 'owner';
    now = DateTime.utc(2026, 10, 28);
    service = BcrKnowledgeSyncService(
      owner: 'owner',
      repository: repository,
      credentials: credentials,
      client: client,
      currentOwner: () async => currentOwner,
      now: () => now,
    );
  });
  tearDown(() async {
    service.dispose();
    await db.close();
  });

  Future<BcrKnowledgeConnection> connect({
    String token = 'old-token',
    Uri? libraryUrl,
  }) async {
    await service.connect(
      label: 'Research',
      repositoryAddress: 'account/research',
      branch: '',
      libraryUrl: libraryUrl,
      token: token,
    );
    return (await repository.listConnections('owner')).single;
  }

  DataManagementService manager({
    Future<void> Function(DomainScope)? clearDrafts,
  }) => DataManagementService(
    database: db,
    ownerUserId: 'owner',
    specs: [knowledgeDataManagementSpec],
    clearLocalDrafts: clearDrafts,
    resetCleanups: {DomainScope.knowledge: credentials.clearOwner},
  );

  test('connect without a page URL persists a target and keeps PAT out of the database', () async {
    final connection = await connect();
    expect(connection.libraryUrl, isNull);
    expect(connection.target.branch, 'main');
    expect(connection.remoteHead, client.head);
    expect(
      await credentials.read('owner', connection.credentialId),
      'old-token',
    );
    final source = (await repository.listSources('owner')).single;
    expect(source.id, connection.id);
    expect(source.libraryUrl, isNull);
    expect(source.noteUrl(source.notes.single.id), isNull);
    expect(source.notes.single.body, contains('60%'));
    expect(
      (await db.select(db.knowledgeSourceConnections).get()).single
          .toJson()
          .toString(),
      isNot(contains('old-token')),
    );
    expect(
      (await db.select(db.knowledgeSourceCache).get()).single.contentJson,
      isNot(contains('old-token')),
    );
    expect(await db.customSelect('SELECT * FROM op_outbox').get(), isEmpty);
    expect(await db.select(db.knowledgeSourceImportLeases).get(), isEmpty);
  });

  test(
    'reconnecting without a page URL preserves existing source links',
    () async {
      await connect(libraryUrl: url);
      final connection = await connect(token: 'new-token');
      expect(connection.libraryUrl, url);
      final source = (await repository.listSources('owner')).single;
      expect(source.libraryUrl, url);
      expect(
        source.noteUrl('note-0'),
        url.replace(queryParameters: {'note': 'note-0'}),
      );
    },
  );

  test(
    'unchanged HEAD retains reader revision and clearing cache rebuilds it',
    () async {
      var connection = await connect();
      final before = (await repository.listSources('owner')).single;
      await service.sync(connection);
      expect(client.calls.last.hasCachedSnapshot, isTrue);
      expect(
        (await repository.listSources('owner')).single.cacheRevision,
        before.cacheRevision,
      );
      await manager().clearCache(DomainScope.knowledge);
      connection = (await repository.listConnections('owner')).single;
      await service.sync(connection);
      expect(client.calls.last.hasCachedSnapshot, isFalse);
      expect((await repository.listSources('owner')).single.libraryUrl, isNull);
      expect(
        (await repository.listSources('owner')).single.notes.single.body,
        before.notes.single.body,
      );
    },
  );

  test(
    'a failed connection check preserves the working connection and snapshot',
    () async {
      final connection = await connect();
      client.onRead = (_) async =>
          throw const BcrGithubFailure(BcrGithubFailureCode.unauthorized);
      await expectLater(
        connect(token: 'bad-token'),
        throwsA(isA<BcrGithubFailure>()),
      );
      expect(
        (await repository.listConnections('owner')).single.revision,
        connection.revision,
      );
      expect(
        await credentials.read('owner', connection.credentialId),
        'old-token',
      );
      expect(
        (await repository.listSources('owner')).single.notes.single.body,
        contains('60%'),
      );
    },
  );

  test('failed connection persistence rolls back cached content and removes the new PAT', () async {
    final connection = await connect();
    await db.customStatement(
      "CREATE TRIGGER reject_connection BEFORE UPDATE ON knowledge_source_connections BEGIN SELECT RAISE(ABORT, 'storage error'); END",
    );
    client.snapshot = makeBcrArchive(body: 'Uncommitted 90%.');
    await expectLater(connect(token: 'new-token'), throwsA(anything));
    expect(
      (await repository.listConnections('owner')).single.revision,
      connection.revision,
    );
    expect(
      (await repository.listSources('owner')).single.notes.single.body,
      contains('60%'),
    );
    expect(
      await credentials.read('owner', connection.credentialId),
      'old-token',
    );
    expect(await db.select(db.knowledgeSourceImportLeases).get(), isEmpty);
  });

  for (final operation in ['reset', 'disconnect', 'owner']) {
    test(
      '$operation fences an in-flight response before it can replace data',
      () async {
        final connection = await connect();
        final started = Completer<BcrTestRequest>();
        final reply = Completer<BcrGithubRead>();
        client.onRead = (request) {
          started.complete(request);
          return reply.future;
        };
        final pending = service.sync(connection);
        final failure = expectLater(pending, throwsA(anything));
        final request = await started.future;
        if (operation == 'reset') {
          await manager().resetLocalDomain(DomainScope.knowledge);
        } else if (operation == 'disconnect') {
          await service.disconnect(connection);
        } else {
          currentOwner = 'other';
        }
        client.snapshot = makeBcrArchive(body: 'Late response');
        reply.complete(client.reply(request));
        await failure;
        if (operation == 'owner') {
          expect(
            (await repository.listSources('owner')).single.notes.single.body,
            contains('60%'),
          );
          expect(await repository.listSources('other'), isEmpty);
        } else {
          expect(await repository.listSources('owner'), isEmpty);
          expect(await repository.listConnections('owner'), isEmpty);
          expect(
            await credentials.read('owner', connection.credentialId),
            isNull,
          );
        }
      },
    );
  }

  test(
    'a first connection cannot resurrect itself after domain reset',
    () async {
      final started = Completer<BcrTestRequest>();
      final reply = Completer<BcrGithubRead>();
      client.onRead = (request) {
        started.complete(request);
        return reply.future;
      };
      final pending = connect();
      final failure = expectLater(pending, throwsA(anything));
      final request = await started.future;
      await manager().resetLocalDomain(DomainScope.knowledge);
      reply.complete(client.reply(request));
      await failure;
      expect(await repository.listConnections('owner'), isEmpty);
      expect(await repository.listSources('owner'), isEmpty);
    },
  );

  test('an old sync cannot overwrite successful reconnect status or pause its retries', () async {
    final connection = await connect();
    final statuses = <Map<String, BcrSyncStatus>>[];
    final subscription = service.statuses.listen(statuses.add);
    addTearDown(subscription.cancel);
    final started = Completer<BcrTestRequest>();
    final reply = Completer<BcrGithubRead>();
    client.onRead = (request) {
      if (request.token == 'old-token') {
        started.complete(request);
        return reply.future;
      }
      return Future.value(client.reply(request));
    };
    final oldSync = service.sync(connection);
    final failure = expectLater(oldSync, throwsA(anything));
    final oldRequest = await started.future;
    final replacement = await connect(token: 'new-token');
    reply.complete(client.reply(oldRequest));
    await failure;
    final count = client.calls.length;
    await service.sync(replacement);
    expect(client.calls.length, count + 1);
    await Future<void>.delayed(Duration.zero);
    expect(statuses.last[replacement.id]?.error, isNull);
    expect(await credentials.read('owner', connection.credentialId), isNull);
  });

  test('rate-limit retry deadlines cannot be bypassed by foreground or manual checks', () async {
    var connection = await connect();
    client.onRead = (_) async => throw const BcrGithubFailure(
      BcrGithubFailureCode.rateLimited,
      retryAfter: Duration(minutes: 2),
    );
    await expectLater(
      service.sync(connection),
      throwsA(isA<BcrGithubFailure>()),
    );
    final count = client.calls.length;
    await service.sync(connection);
    await service.sync(connection, manual: true);
    expect(client.calls.length, count);
    now = now.add(const Duration(minutes: 2));
    client.onRead = null;
    connection = (await repository.listConnections('owner')).single;
    await service.sync(connection);
    expect(client.calls.length, count + 1);
  });

  test('reset still removes credentials when clearing drafts fails', () async {
    final connection = await connect();
    await expectLater(
      manager(clearDrafts: (_) async => throw StateError('preferences failed'))
          .resetLocalDomain(DomainScope.knowledge),
      throwsStateError,
    );
    expect(await credentials.read('owner', connection.credentialId), isNull);
    expect(await repository.listConnections('owner'), isEmpty);
  });

  test(
    'foreground cancellation stops queued sources after the current request',
    () async {
      await connect();
      await service.connect(
        label: 'Second',
        repositoryAddress: 'account/second',
        branch: 'main',
        libraryUrl: Uri.parse('https://second.example.com/knowledge'),
        token: 'second-token',
      );
      final started = Completer<BcrTestRequest>();
      final reply = Completer<BcrGithubRead>();
      client.onRead = (request) {
        started.complete(request);
        return reply.future;
      };
      final pending = service.syncAll();
      final request = await started.future;
      final count = client.calls.length;
      service.cancelAll();
      reply.complete(client.reply(request));
      await pending;
      expect(client.calls.length, count);
    },
  );

  test(
    'disposing while owner lookup is pending never starts a connection request',
    () async {
      final owner = Completer<String>();
      final isolated = BcrKnowledgeSyncService(
        owner: 'owner',
        repository: repository,
        credentials: credentials,
        client: client,
        currentOwner: () => owner.future,
      );
      final pending = isolated.connect(
        label: 'Research',
        repositoryAddress: 'account/research',
        branch: '',
        libraryUrl: url,
        token: 'token',
      );
      final failure = expectLater(
        pending,
        throwsA(BcrSyncLocalFailure.cancelled),
      );
      isolated.dispose();
      owner.complete('owner');
      await failure;
      expect(client.calls, isEmpty);
      expect(await repository.listConnections('owner'), isEmpty);
    },
  );
}
