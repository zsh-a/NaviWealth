import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/device_identity_store.dart';
import 'package:naviwealth/core/auth/owner_transfer_intent.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/auth/token_store.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/owner_data_migration.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/auth/data/app_mode_store.dart';
import 'package:naviwealth/features/auth/data/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/owner_data_fixture.dart';
import '../../core/persistence/test_database.dart';

class _InterruptedProcess implements Exception {}

class _FaultKeyStore extends InMemoryKeyStore {
  bool failSessionWrite = false;
  bool failJournalClear = false;

  @override
  Future<void> write(String key, String value) async {
    if (failSessionWrite && key == TokenStore.storageKey) {
      throw StateError('Storage temporarily unavailable');
    }
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (failJournalClear && key == TokenStore.ownerTransferKey) {
      throw StateError('Storage temporarily unavailable');
    }
    await super.delete(key);
  }
}

final _cloudSession = AuthSession(
  accessToken: 'private-journal-token',
  expiresAt: DateTime.utc(2099),
  userId: 'cloud-owner',
  deviceId: 'cloud-device',
);

final _cloud = OwnerIdentitySnapshot(
  mode: 'cloud',
  session: _cloudSession,
  deviceId: 'cloud-device',
);
const _local = OwnerIdentitySnapshot(
  mode: 'local_only',
  session: null,
  deviceId: 'local-device',
);

ProviderContainer _bootstrap(
  AppDatabase db,
  InMemoryKeyStore keys,
  SharedPreferences preferences,
) => ProviderContainer(
  overrides: [
    appDatabaseProvider.overrideWith((ref) async => db),
    secureKeyStoreProvider.overrideWithValue(keys),
    deviceIdentityStoreProvider.overrideWithValue(DeviceIdentityStore(keys)),
    sharedPreferencesProvider.overrideWithValue(preferences),
  ],
);

Future<void> _persistSnapshot(
  TokenStore store,
  SharedPreferences preferences,
  OwnerIdentitySnapshot snapshot, {
  bool includeMode = true,
}) async {
  if (snapshot.session == null) {
    await store.clear();
  } else {
    await store.write(snapshot.session!);
  }
  if (includeMode) await preferences.setString('app.mode.v1', snapshot.mode);
}

void main() {
  test(
    'failed recovery after rebuild cannot reuse the previous ready identity',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      SharedPreferences.setMockInitialValues({'app.mode.v1': 'local_only'});
      final keys = InMemoryKeyStore();
      final container = _bootstrap(
        db,
        keys,
        await SharedPreferences.getInstance(),
      );
      addTearDown(container.dispose);
      expect(
        await container.read(authControllerProvider.future),
        isA<AuthLocalOnly>(),
      );
      await keys.write(TokenStore.ownerTransferKey, 'invalid-journal');
      container.invalidate(authControllerProvider);
      await expectLater(
        container.read(authControllerProvider.future),
        throwsStateError,
      );
      final controller = container.read(authControllerProvider.notifier);
      expect(controller.currentSession(), isNull);
      expect(await controller.refreshIfPossible(), isFalse);
      await expectLater(controller.chooseCloud(), throwsStateError);
      expect(await keys.read(TokenStore.ownerTransferKey), 'invalid-journal');
    },
  );

  test(
    'explicit database reset retries pending journal recovery without restart',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      SharedPreferences.setMockInitialValues({'app.mode.v1': 'local_only'});
      final preferences = await SharedPreferences.getInstance();
      final keys = InMemoryKeyStore();
      final tokens = TokenStore(keys);
      await tokens.writeOwnerTransfer(
        OwnerTransferIntent(
          id: 'interrupted-before-schema-change',
          from: kLocalOnlyUserId,
          to: 'cloud-owner',
          previous: _local,
          target: _cloud,
        ),
      );
      var available = false;
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          secureKeyStoreProvider.overrideWithValue(keys),
          deviceIdentityStoreProvider.overrideWithValue(
            DeviceIdentityStore(keys),
          ),
          sharedPreferencesProvider.overrideWithValue(preferences),
          appDatabaseProvider.overrideWith((ref) async {
            if (!available) {
              throw const UnsupportedDatabaseSchema(
                foundVersion: 97,
                requiredVersion: 99,
              );
            }
            return db;
          }),
        ],
      );
      addTearDown(container.dispose);
      await expectLater(
        container.read(authControllerProvider.future),
        throwsA(isA<UnsupportedDatabaseSchema>()),
      );
      final recovery = DatabaseRecoveryController(
        resetDatabase: () async {
          available = true;
        },
        invalidateDatabase: () => container.invalidate(appDatabaseProvider),
      );
      await recovery.resetLocalData();
      expect(
        await container.read(authControllerProvider.future),
        isA<AuthLocalOnly>(),
      );
      expect(await tokens.readOwnerTransfer(), isNull);
      expect(await tokens.read(), isNull);
      await container.read(authControllerProvider.notifier).chooseCloud();
      expect(
        container.read(authControllerProvider).value,
        isA<AuthLoggedOut>(),
      );
    },
  );

  test(
    'committed ownership and recovery marker survive database reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'owner-recovery-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/data.sqlite');
      var db = AppDatabase(DatabaseConnection(NativeDatabase(file)));
      await seedOwnerData(db, kLocalOnlyUserId, 'data');
      SharedPreferences.setMockInitialValues({'app.mode.v1': 'local_only'});
      final preferences = await SharedPreferences.getInstance();
      final keys = InMemoryKeyStore();
      final store = TokenStore(keys);
      final intent = OwnerTransferIntent(
        id: 'durable-transfer',
        from: kLocalOnlyUserId,
        to: 'cloud-owner',
        previous: _local,
        target: _cloud,
      );
      await store.writeOwnerTransfer(intent);
      await OwnerDataMigration(db).transfer(
        from: intent.from,
        to: intent.to,
        transferId: intent.id,
        commitIdentity: () => _persistSnapshot(store, preferences, _cloud),
      );
      await db.close();
      db = AppDatabase(DatabaseConnection(NativeDatabase(file)));
      addTearDown(db.close);
      final restarted = _bootstrap(db, keys, preferences);
      addTearDown(restarted.dispose);
      expect(
        await restarted.read(authControllerProvider.future),
        isA<AuthLoggedIn>(),
      );
      expect(await ownerOf(db, 'memories', 'data-memory'), 'cloud-owner');
      expect(
        await ownerOf(db, 'personal_profile_facts', 'data-profile'),
        'cloud-owner',
      );
      expect(await store.readOwnerTransfer(), isNull);
      expect(await OwnerDataMigration(db).didCommit(intent.id), isFalse);
    },
  );

  for (final upgrade in [true, false]) {
    for (final boundary in ['intent', 'session', 'mode', 'commit']) {
      test(
        '${upgrade ? 'upgrade' : 'downgrade'} recovers termination after $boundary',
        () async {
          final db = makeTestDatabase();
          addTearDown(db.close);
          final previous = upgrade ? _local : _cloud;
          final target = upgrade ? _cloud : _local;
          final from = upgrade ? kLocalOnlyUserId : 'cloud-owner';
          final to = upgrade ? 'cloud-owner' : kLocalOnlyUserId;
          await seedOwnerData(db, from, 'data');
          SharedPreferences.setMockInitialValues({
            'app.mode.v1': previous.mode,
          });
          final preferences = await SharedPreferences.getInstance();
          final keys = InMemoryKeyStore();
          final store = TokenStore(keys);
          await _persistSnapshot(store, preferences, previous);
          final intent = OwnerTransferIntent(
            id: 'transfer-$upgrade-$boundary',
            from: from,
            to: to,
            previous: previous,
            target: target,
          );
          await store.writeOwnerTransfer(intent);
          final migration = OwnerDataMigration(db);
          if (boundary != 'intent') {
            final transfer = migration.transfer(
              from: from,
              to: to,
              transferId: intent.id,
              commitIdentity: () async {
                await _persistSnapshot(
                  store,
                  preferences,
                  target,
                  includeMode: boundary != 'session',
                );
                if (boundary != 'commit') throw _InterruptedProcess();
              },
            );
            if (boundary == 'commit') {
              await transfer;
            } else {
              await expectLater(transfer, throwsA(isA<_InterruptedProcess>()));
            }
          }

          // Recreate the application state after losing all in-memory auth state.
          final container = _bootstrap(db, keys, preferences);
          addTearDown(container.dispose);
          final state = await container.read(authControllerProvider.future);
          final committed = boundary == 'commit';
          final expected = committed ? target : previous;
          expect(
            state,
            expected.session == null
                ? isA<AuthLocalOnly>()
                : isA<AuthLoggedIn>(),
          );
          expect((await store.read())?.encode(), expected.session?.encode());
          expect(container.read(appModeProvider).wire, expected.mode);
          expect(
            await container.read(deviceIdentityStoreProvider).getOrCreate(),
            expected.deviceId,
          );
          for (final entry in {
            'memories': 'memory',
            'personal_profile_facts': 'profile',
            'chat_messages': 'message',
            'recurring_transactions': 'recurring',
          }.entries) {
            expect(
              await ownerOf(db, entry.key, 'data-${entry.value}'),
              committed ? to : from,
            );
          }
          expect(await store.readOwnerTransfer(), isNull);
          expect(await migration.didCommit(intent.id), isFalse);
          final metadata = await db
              .customSelect('SELECT * FROM sync_meta')
              .get();
          expect(
            metadata.map((row) => row.data).toString(),
            isNot(contains('private-journal-token')),
          );

          // Repeating startup after journal cleanup never reverses ownership.
          final again = _bootstrap(db, keys, preferences);
          addTearDown(again.dispose);
          expect(
            await again.read(authControllerProvider.future),
            expected.session == null
                ? isA<AuthLocalOnly>()
                : isA<AuthLoggedIn>(),
          );
          expect(
            await ownerOf(db, 'memories', 'data-memory'),
            committed ? to : from,
          );
        },
      );
    }
  }

  for (final failure in ['credentials', 'journal_cleanup']) {
    test(
      'interrupted recovery at $failure retains intent and retries idempotently',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        await seedOwnerData(db, kLocalOnlyUserId, 'data');
        SharedPreferences.setMockInitialValues({'app.mode.v1': 'local_only'});
        final preferences = await SharedPreferences.getInstance();
        final keys = _FaultKeyStore();
        final store = TokenStore(keys);
        const id = 'recoverable-transfer';
        final intent = OwnerTransferIntent(
          id: id,
          from: kLocalOnlyUserId,
          to: 'cloud-owner',
          previous: _local,
          target: _cloud,
        );
        await store.writeOwnerTransfer(intent);
        final migration = OwnerDataMigration(db);
        await migration.transfer(
          from: intent.from,
          to: intent.to,
          transferId: id,
        );
        keys.failSessionWrite = failure == 'credentials';
        keys.failJournalClear = failure == 'journal_cleanup';
        final interrupted = _bootstrap(db, keys, preferences);
        addTearDown(interrupted.dispose);
        await expectLater(
          interrupted.read(authControllerProvider.future),
          throwsStateError,
        );
        expect(await store.readOwnerTransfer(), isNotNull);
        expect(await migration.didCommit(id), isTrue);
        await expectLater(
          interrupted
              .read(authControllerProvider.notifier)
              .enterLocalOnlyMode(),
          throwsStateError,
        );

        keys.failSessionWrite = false;
        keys.failJournalClear = false;
        final retry = _bootstrap(db, keys, preferences);
        addTearDown(retry.dispose);
        expect(
          await retry.read(authControllerProvider.future),
          isA<AuthLoggedIn>(),
        );
        expect((await store.read())?.userId, 'cloud-owner');
        expect(await ownerOf(db, 'memories', 'data-memory'), 'cloud-owner');
        expect(await store.readOwnerTransfer(), isNull);
        expect(await migration.didCommit(id), isFalse);
      },
    );
  }

  test(
    'corrupt recovery journal fails closed without exposing credentials',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      SharedPreferences.setMockInitialValues({'app.mode.v1': 'local_only'});
      final keys = InMemoryKeyStore({
        TokenStore.ownerTransferKey: 'private-broken-token',
      });
      final container = _bootstrap(
        db,
        keys,
        await SharedPreferences.getInstance(),
      );
      addTearDown(container.dispose);
      await expectLater(
        container.read(authControllerProvider.future),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'safe error',
            isNot(contains('private-broken-token')),
          ),
        ),
      );
      expect(
        await keys.read(TokenStore.ownerTransferKey),
        'private-broken-token',
      );
    },
  );
}
