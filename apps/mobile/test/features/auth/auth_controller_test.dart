import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/routing/route_guard.dart';
import 'package:naviwealth/core/auth/auth_api_client.dart';
import 'package:naviwealth/core/auth/auth_errors.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/auth/current_user.dart' show kLocalOnlyUserId;
import 'package:naviwealth/core/auth/device_identity_store.dart';
import 'package:naviwealth/core/auth/owner_transfer_intent.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/auth/token_store.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';
import 'package:naviwealth/core/sync/providers.dart';
import 'package:naviwealth/core/sync/sync_scheduler.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/auth/data/app_mode_store.dart';
import 'package:naviwealth/features/auth/data/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/owner_data_fixture.dart';
import '../../core/persistence/test_database.dart';

class _RecordingScheduler implements SyncScheduler {
  final drain = Completer<void>();
  bool paused = false;
  bool resumed = false;
  bool stopped = false;

  @override
  Future<void> pauseAndDrain() {
    paused = true;
    return drain.future;
  }

  @override
  void resume() => resumed = true;

  @override
  void stop() => stopped = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingTransferStore extends InMemoryKeyStore {
  _FailingTransferStore(this.boundary);
  final String boundary;
  bool armed = false;

  @override
  Future<void> write(String key, String value) async {
    if (armed &&
        ((boundary == 'intent' && key == TokenStore.ownerTransferKey) ||
            (boundary == 'credentials' && key == TokenStore.storageKey))) {
      armed = false;
      throw StateError('Storage write failed');
    }
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (armed && boundary == 'cleanup' && key == TokenStore.ownerTransferKey) {
      armed = false;
      throw StateError('Storage cleanup failed');
    }
    await super.delete(key);
  }
}

class _FakeAuthApi implements AuthApiClient {
  AuthSession? loginResponse;
  Object? loginError;
  AuthSession? registerResponse;
  Object? registerError;
  RefreshedToken? refreshResponse;
  Object? refreshError;
  DevicesResponse? devicesResponse;
  Object? logoutError;

  final List<
    ({
      String email,
      String password,
      List<String> domains,
      String? deviceName,
      String? deviceId,
    })
  >
  loginCalls = [];
  final List<
    ({
      String email,
      String password,
      List<String> domains,
      String? deviceName,
      String? deviceId,
    })
  >
  registerCalls = [];
  final List<({AuthSession session, List<String> domains})> refreshCalls = [];
  final List<({AuthSession session, String deviceId})> logoutCalls = [];

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
    required List<String> domains,
    String? deviceName,
    String? deviceId,
  }) async {
    loginCalls.add((
      email: email,
      password: password,
      domains: domains,
      deviceName: deviceName,
      deviceId: deviceId,
    ));
    if (loginError != null) throw loginError!;
    return loginResponse!;
  }

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
    required List<String> domains,
    String? deviceName,
    String? deviceId,
  }) async {
    registerCalls.add((
      email: email,
      password: password,
      domains: domains,
      deviceName: deviceName,
      deviceId: deviceId,
    ));
    if (registerError != null) throw registerError!;
    return registerResponse!;
  }

  @override
  Future<RefreshedToken> refresh(
    AuthSession current, {
    required List<String> domains,
  }) async {
    refreshCalls.add((session: current, domains: domains));
    if (refreshError != null) throw refreshError!;
    return refreshResponse!;
  }

  @override
  Future<DevicesResponse> listDevices(AuthSession current) async {
    return devicesResponse ??
        const DevicesResponse(devices: [], currentDeviceId: '');
  }

  @override
  Future<void> logoutDevice(AuthSession current, String deviceId) async {
    logoutCalls.add((session: current, deviceId: deviceId));
    if (logoutError != null) throw logoutError!;
  }
}

AuthSession _session({
  String token = 'tok',
  DateTime? expiresAt,
  String userId = 'u-1',
  String deviceId = 'd-1',
}) => AuthSession(
  accessToken: token,
  expiresAt: expiresAt ?? DateTime.utc(2026, 12, 1),
  userId: userId,
  deviceId: deviceId,
);

ProviderContainer _container({
  Map<String, String>? seed,
  AuthApiClient? api,
  AppDatabase? database,
  SharedPreferences? preferences,
  SyncScheduler? scheduler,
  InMemoryKeyStore? keyStoreOverride,
}) {
  final keyStore = keyStoreOverride ?? InMemoryKeyStore(seed);
  return ProviderContainer(
    overrides: [
      secureKeyStoreProvider.overrideWithValue(keyStore),
      deviceIdentityStoreProvider.overrideWithValue(
        DeviceIdentityStore(keyStore),
      ),
      if (api != null) authApiClientProvider.overrideWithValue(api),
      if (database != null)
        appDatabaseProvider.overrideWith((ref) async => database),
      if (preferences != null)
        sharedPreferencesProvider.overrideWithValue(preferences),
      if (database != null)
        syncSchedulerProvider.overrideWith((ref) async => scheduler),
    ],
  );
}

void main() {
  group('AuthController owner transitions', () {
    for (final boundary in ['intent', 'credentials', 'cleanup']) {
      test('runtime failure at $boundary follows durable ownership', () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        await seedOwnerData(db, kLocalOnlyUserId, 'local');
        SharedPreferences.setMockInitialValues({'app.mode.v1': 'local_only'});
        final keys = _FailingTransferStore(boundary);
        final scheduler = _RecordingScheduler()..drain.complete();
        final container = _container(
          database: db,
          api: _FakeAuthApi()..registerResponse = _session(),
          preferences: await SharedPreferences.getInstance(),
          scheduler: scheduler,
          keyStoreOverride: keys,
        );
        addTearDown(container.dispose);
        await container.read(authControllerProvider.future);
        keys.armed = true;
        final operation = container
            .read(authControllerProvider.notifier)
            .upgradeToCloud(email: 'a@b.com', password: 'password');
        final committed = boundary == 'cleanup';
        if (committed) {
          await operation;
        } else {
          await expectLater(operation, throwsStateError);
        }
        expect(
          container.read(authControllerProvider).value,
          committed ? isA<AuthLoggedIn>() : isA<AuthLocalOnly>(),
        );
        expect(
          await ownerOf(db, 'personal_profile_facts', 'local-profile'),
          committed ? 'u-1' : kLocalOnlyUserId,
        );
        expect(
          (await container.read(tokenStoreProvider).read())?.userId,
          committed ? 'u-1' : null,
        );
        expect(
          await container.read(tokenStoreProvider).readOwnerTransfer(),
          isNull,
        );
        expect(scheduler.resumed, !committed);
      });
    }

    test(
      'a preexisting transfer intent is never overwritten or cleared',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        await seedOwnerData(db, kLocalOnlyUserId, 'local');
        SharedPreferences.setMockInitialValues({'app.mode.v1': 'local_only'});
        final container = _container(
          database: db,
          api: _FakeAuthApi()..registerResponse = _session(),
          preferences: await SharedPreferences.getInstance(),
        );
        addTearDown(container.dispose);
        await container.read(authControllerProvider.future);
        final store = container.read(tokenStoreProvider);
        final existing = OwnerTransferIntent(
          id: 'existing-transfer',
          from: kLocalOnlyUserId,
          to: 'different-cloud-user',
          previous: const OwnerIdentitySnapshot(
            mode: 'local_only',
            session: null,
            deviceId: 'device',
          ),
          target: OwnerIdentitySnapshot(
            mode: 'cloud',
            session: _session(userId: 'different-cloud-user'),
            deviceId: 'device',
          ),
        );
        await store.writeOwnerTransfer(existing);
        await expectLater(
          container
              .read(authControllerProvider.notifier)
              .upgradeToCloud(email: 'a@b.com', password: 'password'),
          throwsStateError,
        );
        expect((await store.readOwnerTransfer())?.id, existing.id);
        expect(await ownerOf(db, 'memories', 'local-memory'), kLocalOnlyUserId);
      },
    );

    test(
      'upgrade waits for sync and preserves confirmed data through downgrade',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        await seedOwnerData(db, kLocalOnlyUserId, 'local');
        SharedPreferences.setMockInitialValues({'app.mode.v1': 'local_only'});
        final preferences = await SharedPreferences.getInstance();
        final api = _FakeAuthApi()..registerResponse = _session();
        final scheduler = _RecordingScheduler();
        final container = _container(
          api: api,
          database: db,
          preferences: preferences,
          scheduler: scheduler,
        );
        addTearDown(container.dispose);
        expect(
          await container.read(authControllerProvider.future),
          isA<AuthLocalOnly>(),
        );

        final controller = container.read(authControllerProvider.notifier);
        final upgrade = controller.upgradeToCloud(
          email: 'new@user.com',
          password: 'password',
        );
        await Future<void>.delayed(Duration.zero);
        expect(scheduler.paused, isTrue);
        expect(await ownerOf(db, 'memories', 'local-memory'), kLocalOnlyUserId);
        expect(
          container.read(authControllerProvider).value,
          isA<AuthLocalOnly>(),
        );
        scheduler.drain.complete();
        await upgrade;

        expect(scheduler.stopped, isTrue);
        expect(scheduler.resumed, isFalse);
        expect(
          container.read(authControllerProvider).value,
          isA<AuthLoggedIn>(),
        );
        expect(container.read(appModeProvider), AppMode.cloud);
        expect(
          (await container.read(tokenStoreProvider).read())?.userId,
          'u-1',
        );
        for (final entry in {
          'memories': 'memory',
          'personal_profile_facts': 'profile',
          'chat_sessions': 'chat',
          'chat_messages': 'message',
          'recurring_transactions': 'recurring',
        }.entries) {
          expect(await ownerOf(db, entry.key, 'local-${entry.value}'), 'u-1');
        }

        await controller.switchToLocalOnly();
        expect(
          container.read(authControllerProvider).value,
          isA<AuthLocalOnly>(),
        );
        expect(container.read(appModeProvider), AppMode.localOnly);
        expect(await container.read(tokenStoreProvider).read(), isNull);
        expect(api.logoutCalls, hasLength(1));
        for (final entry in {
          'memories': 'memory',
          'personal_profile_facts': 'profile',
          'chat_sessions': 'chat',
          'chat_messages': 'message',
          'recurring_transactions': 'recurring',
        }.entries) {
          expect(
            await ownerOf(db, entry.key, 'local-${entry.value}'),
            kLocalOnlyUserId,
          );
        }
      },
    );

    test(
      'conflicting downgrade preserves cloud auth and resumes sync',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        await seedOwnerData(db, 'u-1', 'cloud');
        await seedProfileFact(db, kLocalOnlyUserId, 'local-profile');
        SharedPreferences.setMockInitialValues({'app.mode.v1': 'cloud'});
        final api = _FakeAuthApi();
        final scheduler = _RecordingScheduler()..drain.complete();
        final container = _container(
          api: api,
          database: db,
          seed: {TokenStore.storageKey: _session().encode()},
          preferences: await SharedPreferences.getInstance(),
          scheduler: scheduler,
        );
        addTearDown(container.dispose);
        await container.read(authControllerProvider.future);
        await expectLater(
          container.read(authControllerProvider.notifier).switchToLocalOnly(),
          throwsA(isA<Exception>()),
        );
        expect(scheduler.resumed, isTrue);
        expect(scheduler.stopped, isFalse);
        expect(api.logoutCalls, isEmpty);
        expect(
          container.read(authControllerProvider).value,
          isA<AuthLoggedIn>(),
        );
        expect(container.read(appModeProvider), AppMode.cloud);
        expect(
          (await container.read(tokenStoreProvider).read())?.userId,
          'u-1',
        );
        expect(
          await ownerOf(db, 'recurring_transactions', 'cloud-recurring'),
          'u-1',
        );
        expect(await ownerOf(db, 'memories', 'cloud-memory'), 'u-1');
        expect(
          await ownerOf(db, 'personal_profile_facts', 'local-profile'),
          kLocalOnlyUserId,
        );
      },
    );
  });

  group('AuthController.build', () {
    test('emits AuthLoggedOut when nothing is persisted', () async {
      final container = _container();
      addTearDown(container.dispose);

      final state = await container.read(authControllerProvider.future);
      expect(state, isA<AuthLoggedOut>());
      expect((state as AuthLoggedOut).reason, isNull);
    });

    test('emits AuthLoggedIn when a live session is persisted', () async {
      final container = _container(
        seed: {TokenStore.storageKey: _session().encode()},
      );
      addTearDown(container.dispose);

      final state = await container.read(authControllerProvider.future);
      expect(state, isA<AuthLoggedIn>());
      expect((state as AuthLoggedIn).session.userId, 'u-1');
      expect(
        await container.read(deviceIdentityStoreProvider).getOrCreate(),
        'd-1',
      );
    });

    test('emits AuthLoggedOut(sessionExpired) and clears storage when token expired', () async {
      final keyStore = InMemoryKeyStore({
        TokenStore.storageKey: _session(expiresAt: DateTime.utc(2020, 1, 1))
            .encode(),
      });
      final container = ProviderContainer(
        overrides: [secureKeyStoreProvider.overrideWithValue(keyStore)],
      );
      addTearDown(container.dispose);

      final state = await container.read(authControllerProvider.future);
      expect(state, isA<AuthLoggedOut>());
      expect((state as AuthLoggedOut).reason, LoggedOutReason.sessionExpired);
      expect(await keyStore.read(TokenStore.storageKey), isNull);
    });
  });

  group('AuthController.login', () {
    test(
      'persists session, emits AuthLoggedIn, bumps router version',
      () async {
        final api = _FakeAuthApi()..loginResponse = _session(token: 'fresh');
        final container = _container(api: api);
        addTearDown(container.dispose);

        // Force build to settle on AuthLoggedOut first; pump microtasks so
        // the deferred router-version bump from `listenSelf` lands.
        await container.read(authControllerProvider.future);
        await Future<void>.delayed(Duration.zero);
        final versionBefore = container.read(routeRedirectVersionProvider);

        await container
            .read(authControllerProvider.notifier)
            .login(email: 'a@b.com', password: 'hunter22', deviceName: 'iOS');
        await Future<void>.delayed(Duration.zero);

        final state = container.read(authControllerProvider).value;
        expect(state, isA<AuthLoggedIn>());
        expect((state as AuthLoggedIn).session.accessToken, 'fresh');
        expect(api.loginCalls, hasLength(1));
        expect(api.loginCalls.single.deviceName, 'iOS');
        expect(api.loginCalls.single.deviceId, isNotEmpty);

        final versionAfter = container.read(routeRedirectVersionProvider);
        expect(versionAfter, greaterThan(versionBefore));

        // Persisted to the secure store.
        final stored = await container.read(tokenStoreProvider).read();
        expect(stored?.accessToken, 'fresh');
      },
    );

    test('reuses persisted install device id on login', () async {
      const installDeviceId = '0711901b-f1a4-4090-b490-117a23d24652';
      final api = _FakeAuthApi()
        ..loginResponse = _session(token: 'fresh', deviceId: installDeviceId);
      final container = _container(
        api: api,
        seed: {'naviwealth.install_device_id': installDeviceId},
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      await container
          .read(authControllerProvider.notifier)
          .login(email: 'a@b.com', password: 'hunter22');

      expect(api.loginCalls.single.deviceId, installDeviceId);
    });

    test(
      'aligns install device id when server returns a different one',
      () async {
        const requestedDeviceId = '0711901b-f1a4-4090-b490-117a23d24652';
        const serverDeviceId = '98fa5788-438f-4fa7-b2b8-80cc76d3cd45';
        final api = _FakeAuthApi()
          ..loginResponse = _session(token: 'fresh', deviceId: serverDeviceId);
        final container = _container(
          api: api,
          seed: {'naviwealth.install_device_id': requestedDeviceId},
        );
        addTearDown(container.dispose);
        await container.read(authControllerProvider.future);

        await container
            .read(authControllerProvider.notifier)
            .login(email: 'a@b.com', password: 'hunter22');

        expect(api.loginCalls.single.deviceId, requestedDeviceId);
        expect(
          await container.read(deviceIdentityStoreProvider).getOrCreate(),
          serverDeviceId,
        );
      },
    );

    test('propagates AuthException without changing state', () async {
      final api = _FakeAuthApi()
        ..loginError = AuthException(AuthErrorKind.invalidCredentials);
      final container = _container(api: api);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      await expectLater(
        () => container
            .read(authControllerProvider.notifier)
            .login(email: 'a@b.com', password: 'wrong'),
        throwsA(isA<AuthException>()),
      );
      expect(
        container.read(authControllerProvider).value,
        isA<AuthLoggedOut>(),
      );
    });
  });

  group('AuthController.register', () {
    test(
      'creates first account session, persists it, and bumps router version',
      () async {
        final api = _FakeAuthApi()..registerResponse = _session(token: 'fresh');
        final container = _container(api: api);
        addTearDown(container.dispose);

        await container.read(authControllerProvider.future);
        await Future<void>.delayed(Duration.zero);
        final versionBefore = container.read(routeRedirectVersionProvider);

        await container
            .read(authControllerProvider.notifier)
            .register(email: 'new@user.com', password: 'hunter22');
        await Future<void>.delayed(Duration.zero);

        final state = container.read(authControllerProvider).value;
        expect(state, isA<AuthLoggedIn>());
        expect((state as AuthLoggedIn).session.accessToken, 'fresh');
        expect(api.registerCalls, hasLength(1));
        expect(api.registerCalls.single.deviceId, isNotEmpty);
        expect(
          container.read(routeRedirectVersionProvider),
          greaterThan(versionBefore),
        );

        final stored = await container.read(tokenStoreProvider).read();
        expect(stored?.accessToken, 'fresh');
      },
    );

    test('propagates registration failure without changing state', () async {
      final api = _FakeAuthApi()
        ..registerError = AuthException(AuthErrorKind.accountExists);
      final container = _container(api: api);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      await expectLater(
        () => container
            .read(authControllerProvider.notifier)
            .register(email: 'new@user.com', password: 'hunter22'),
        throwsA(isA<AuthException>()),
      );
      expect(
        container.read(authControllerProvider).value,
        isA<AuthLoggedOut>(),
      );
    });
  });

  group('AuthController.logoutCurrent', () {
    test('clears storage, emits manuallyLoggedOut, calls API', () async {
      final api = _FakeAuthApi();
      final container = _container(
        api: api,
        seed: {TokenStore.storageKey: _session().encode()},
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).logoutCurrent();

      expect(api.logoutCalls, hasLength(1));
      expect(api.logoutCalls.single.deviceId, 'd-1');

      final state = container.read(authControllerProvider).value;
      expect(state, isA<AuthLoggedOut>());
      expect(
        (state as AuthLoggedOut).reason,
        LoggedOutReason.manuallyLoggedOut,
      );
      expect(await container.read(tokenStoreProvider).read(), isNull);
    });

    test('still clears local state when remote logout fails', () async {
      final api = _FakeAuthApi()
        ..logoutError = AuthException(AuthErrorKind.network);
      final container = _container(
        api: api,
        seed: {TokenStore.storageKey: _session().encode()},
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).logoutCurrent();

      expect(
        container.read(authControllerProvider).value,
        isA<AuthLoggedOut>(),
      );
      expect(await container.read(tokenStoreProvider).read(), isNull);
    });
  });

  group('AuthController.refreshIfPossible', () {
    test('rotates token on success and persists', () async {
      final api = _FakeAuthApi()
        ..refreshResponse = RefreshedToken(
          accessToken: 'rotated',
          expiresAt: DateTime.utc(2027, 1, 1),
        );
      final container = _container(
        api: api,
        seed: {TokenStore.storageKey: _session().encode()},
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);

      final ok = await container
          .read(authControllerProvider.notifier)
          .refreshIfPossible();

      expect(ok, isTrue);
      final state = container.read(authControllerProvider).value;
      expect((state as AuthLoggedIn).session.accessToken, 'rotated');
      expect(
        (await container.read(tokenStoreProvider).read())!.accessToken,
        'rotated',
      );
      expect(api.refreshCalls, hasLength(1));
    });

    test(
      'returns false on refresh failure, clears session, emits sessionExpired',
      () async {
        final api = _FakeAuthApi()
          ..refreshError = AuthException(AuthErrorKind.unauthorized);
        final container = _container(
          api: api,
          seed: {TokenStore.storageKey: _session().encode()},
        );
        addTearDown(container.dispose);
        await container.read(authControllerProvider.future);

        final ok = await container
            .read(authControllerProvider.notifier)
            .refreshIfPossible();

        expect(ok, isFalse);
        final state = container.read(authControllerProvider).value;
        expect(state, isA<AuthLoggedOut>());
        expect((state as AuthLoggedOut).reason, LoggedOutReason.sessionExpired);
        expect(await container.read(tokenStoreProvider).read(), isNull);
      },
    );

    test(
      'concurrent refreshIfPossible calls collapse to a single API call',
      () async {
        final api = _FakeAuthApi()
          ..refreshResponse = RefreshedToken(
            accessToken: 'rotated',
            expiresAt: DateTime.utc(2027, 1, 1),
          );
        final container = _container(
          api: api,
          seed: {TokenStore.storageKey: _session().encode()},
        );
        addTearDown(container.dispose);
        await container.read(authControllerProvider.future);

        final controller = container.read(authControllerProvider.notifier);
        final results = await Future.wait([
          controller.refreshIfPossible(),
          controller.refreshIfPossible(),
          controller.refreshIfPossible(),
        ]);
        expect(results, [true, true, true]);
        expect(api.refreshCalls, hasLength(1));
      },
    );
  });
}
