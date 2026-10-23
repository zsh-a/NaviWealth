import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_api_client.dart';
import 'package:naviwealth/core/auth/auth_errors.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/device_identity_store.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/auth/token_store.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';
import 'package:naviwealth/core/sync/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/auth/data/app_mode_store.dart';
import 'package:naviwealth/features/auth/data/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/owner_data_fixture.dart';
import '../../core/persistence/test_database.dart';

class _Api implements AuthApiClient {
  Completer<void>? logoutGate;
  final logoutStarted = Completer<void>();
  final refreshStarted = Completer<void>();
  final refreshResult = Completer<RefreshedToken>();
  final loginStarted = List.generate(2, (_) => Completer<void>());
  final loginResults = List.generate(2, (_) => Completer<AuthSession>());
  int loginCount = 0;

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
    required List<String> domains,
    String? deviceName,
    String? deviceId,
  }) {
    final index = loginCount++;
    loginStarted[index].complete();
    return loginResults[index].future;
  }

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
    required List<String> domains,
    String? deviceName,
    String? deviceId,
  }) => login(
    email: email,
    password: password,
    domains: domains,
    deviceName: deviceName,
    deviceId: deviceId,
  );

  @override
  Future<RefreshedToken> refresh(
    AuthSession current, {
    required List<String> domains,
  }) {
    refreshStarted.complete();
    return refreshResult.future;
  }

  @override
  Future<void> logoutDevice(AuthSession current, String deviceId) async {
    if (!logoutStarted.isCompleted) logoutStarted.complete();
    await logoutGate?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthSession _session(String user) => AuthSession(
  accessToken: '$user-token',
  expiresAt: DateTime.utc(2099),
  userId: user,
  deviceId: 'device',
);

class _BlockedTokenStore extends InMemoryKeyStore {
  _BlockedTokenStore()
    : super({TokenStore.storageKey: _session('old').encode()});
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    if (key == TokenStore.storageKey && value.contains('rotated-token')) {
      started.complete();
      await release.future;
    }
    await super.write(key, value);
  }
}

class _FailedModeStore implements AppModeStore {
  _FailedModeStore({this.afterWrite = false});
  final bool afterWrite;
  AppMode mode = AppMode.localOnly;
  bool failRead = false;

  @override
  AppMode read() {
    if (failRead) throw StateError('Mode read failed');
    return mode;
  }

  @override
  Future<void> write(AppMode value) async {
    if (value == AppMode.cloud) {
      if (afterWrite) mode = value;
      throw StateError('Mode write failed');
    }
    mode = value;
  }
}

Future<ProviderContainer> _container(
  _Api api, {
  bool loggedIn = true,
  InMemoryKeyStore? keys,
  AppModeStore? modes,
  AppDatabase? db,
}) async {
  SharedPreferences.setMockInitialValues({
    'app.mode.v1': loggedIn ? 'cloud' : 'local_only',
  });
  keys ??= InMemoryKeyStore(
    loggedIn ? {TokenStore.storageKey: _session('old').encode()} : null,
  );
  final container = ProviderContainer(
    overrides: [
      secureKeyStoreProvider.overrideWithValue(keys),
      deviceIdentityStoreProvider.overrideWithValue(DeviceIdentityStore(keys)),
      sharedPreferencesProvider.overrideWithValue(
        await SharedPreferences.getInstance(),
      ),
      authApiClientProvider.overrideWithValue(api),
      if (modes != null) appModeStoreProvider.overrideWithValue(modes),
      if (db != null) appDatabaseProvider.overrideWith((ref) async => db),
      syncSchedulerProvider.overrideWith((ref) async => null),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'rebuilding auth discards old network work and permits new transitions',
    () async {
      final api = _Api();
      final container = await _container(api);
      await container.read(authControllerProvider.future);
      final controller = container.read(authControllerProvider.notifier);
      final oldRefresh = controller.refreshIfPossible();
      await api.refreshStarted.future;
      container.invalidate(authControllerProvider);
      expect(
        await container.read(authControllerProvider.future),
        isA<AuthLoggedIn>(),
      );
      final rebuilt = container.read(authControllerProvider.notifier);
      final login = rebuilt.login(
        email: 'new@example.test',
        password: 'password',
      );
      await api.loginStarted[0].future;
      api.loginResults[0].complete(_session('new'));
      await login;
      api.refreshResult.complete(
        RefreshedToken(
          accessToken: 'late-token',
          expiresAt: DateTime.utc(2099),
        ),
      );
      expect(await oldRefresh, isFalse);
      expect(rebuilt.currentSession()?.userId, 'new');
      expect((await container.read(tokenStoreProvider).read())?.userId, 'new');
      await rebuilt.logoutCurrent();
      expect(await container.read(tokenStoreProvider).read(), isNull);
      expect(
        container.read(authControllerProvider).value,
        isA<AuthLoggedOut>(),
      );
    },
  );

  test(
    'new login waits for old device revocation before contacting server',
    () async {
      final api = _Api()..logoutGate = Completer<void>();
      final container = await _container(api);
      await container.read(authControllerProvider.future);
      final controller = container.read(authControllerProvider.notifier);
      final logout = controller.logoutCurrent();
      await api.logoutStarted.future;
      final login = controller.login(
        email: 'new@example.test',
        password: 'password',
      );
      await Future<void>.delayed(Duration.zero);
      expect(api.loginCount, 0);
      api.logoutGate!.complete();
      await logout;
      await api.loginStarted[0].future;
      api.loginResults[0].complete(_session('new'));
      await login;
      expect(controller.currentSession()?.userId, 'new');
    },
  );

  test('late refresh success cannot undo completed logout', () async {
    final api = _Api();
    final container = await _container(api);
    await container.read(authControllerProvider.future);
    final controller = container.read(authControllerProvider.notifier);
    final refresh = controller.refreshIfPossible();
    await api.refreshStarted.future;
    await controller.logoutCurrent();
    api.refreshResult.complete(
      RefreshedToken(accessToken: 'late-token', expiresAt: DateTime.utc(2099)),
    );
    expect(await refresh, isFalse);
    expect(container.read(authControllerProvider).value, isA<AuthLoggedOut>());
    expect(await container.read(tokenStoreProvider).read(), isNull);
  });

  test(
    'late refresh rejection cannot clear a newly connected account',
    () async {
      final api = _Api();
      final container = await _container(api);
      await container.read(authControllerProvider.future);
      final controller = container.read(authControllerProvider.notifier);
      final refresh = controller.refreshIfPossible();
      await api.refreshStarted.future;
      final login = controller.connectToCloud(
        email: 'new@example.test',
        password: 'password',
      );
      await api.loginStarted[0].future;
      api.loginResults[0].complete(_session('new'));
      await login;
      api.refreshResult.completeError(
        AuthException(AuthErrorKind.unauthorized),
      );
      expect(await refresh, isFalse);
      expect(controller.currentSession()?.userId, 'new');
      expect((await container.read(tokenStoreProvider).read())?.userId, 'new');
    },
  );

  test(
    'logout waits for a token write already in progress then clears it',
    () async {
      final api = _Api();
      final keys = _BlockedTokenStore();
      final container = await _container(api, keys: keys);
      await container.read(authControllerProvider.future);
      final controller = container.read(authControllerProvider.notifier);
      final refresh = controller.refreshIfPossible();
      await api.refreshStarted.future;
      api.refreshResult.complete(
        RefreshedToken(
          accessToken: 'rotated-token',
          expiresAt: DateTime.utc(2099),
        ),
      );
      await keys.started.future;
      final logout = controller.logoutCurrent();
      keys.release.complete();
      await logout;
      expect(await refresh, isFalse);
      expect(
        container.read(authControllerProvider).value,
        isA<AuthLoggedOut>(),
      );
      expect(await container.read(tokenStoreProvider).read(), isNull);
    },
  );

  test('logout supersedes a pending login response', () async {
    final api = _Api();
    final container = await _container(api);
    await container.read(authControllerProvider.future);
    final controller = container.read(authControllerProvider.notifier);
    final login = controller.login(
      email: 'new@example.test',
      password: 'password',
    );
    await api.loginStarted[0].future;
    await controller.logoutCurrent();
    api.loginResults[0].complete(_session('new'));
    await login;
    expect(container.read(authControllerProvider).value, isA<AuthLoggedOut>());
    expect(await container.read(tokenStoreProvider).read(), isNull);
  });

  test(
    'out-of-order login responses keep the latest requested account',
    () async {
      final api = _Api();
      final container = await _container(api);
      await container.read(authControllerProvider.future);
      final controller = container.read(authControllerProvider.notifier);
      final first = controller.login(
        email: 'first@example.test',
        password: 'password',
      );
      await api.loginStarted[0].future;
      final second = controller.login(
        email: 'second@example.test',
        password: 'password',
      );
      await api.loginStarted[1].future;
      api.loginResults[1].complete(_session('second'));
      await second;
      api.loginResults[0].complete(_session('first'));
      await first;
      expect(controller.currentSession()?.userId, 'second');
      expect(
        (await container.read(tokenStoreProvider).read())?.userId,
        'second',
      );
    },
  );

  test(
    'local owner transfer supersedes refresh without waiting for network',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      await seedOwnerData(db, 'old', 'data');
      final api = _Api();
      final container = await _container(api, db: db);
      await container.read(authControllerProvider.future);
      final controller = container.read(authControllerProvider.notifier);
      final refresh = controller.refreshIfPossible();
      await api.refreshStarted.future;
      await controller.switchToLocalOnly();
      api.refreshResult.complete(
        RefreshedToken(
          accessToken: 'late-token',
          expiresAt: DateTime.utc(2099),
        ),
      );
      expect(await refresh, isFalse);
      expect(
        container.read(authControllerProvider).value,
        isA<AuthLocalOnly>(),
      );
      expect(await container.read(tokenStoreProvider).read(), isNull);
      expect(await ownerOf(db, 'memories', 'data-memory'), kLocalOnlyUserId);
    },
  );

  for (final action in ['login', 'register', 'connect']) {
    for (final afterWrite in [false, true]) {
      test(
        '$action reports mode failure and compensates partial writes=$afterWrite',
        () async {
          final api = _Api();
          final modes = _FailedModeStore(afterWrite: afterWrite);
          final container = await _container(
            api,
            loggedIn: false,
            modes: modes,
          );
          await container.read(authControllerProvider.future);
          final controller = container.read(authControllerProvider.notifier);
          final method = switch (action) {
            'login' => controller.login,
            'register' => controller.register,
            _ => controller.connectToCloud,
          };
          final login = method(email: 'new@example.test', password: 'password');
          final failed = expectLater(login, throwsStateError);
          await api.loginStarted[0].future;
          api.loginResults[0].complete(_session('new'));
          await failed;
          expect(
            container.read(authControllerProvider).value,
            isA<AuthLocalOnly>(),
          );
          expect(await container.read(tokenStoreProvider).read(), isNull);
          expect(modes.mode, AppMode.localOnly);
        },
      );
    }
  }

  test(
    'mode read failure is exposed at startup rather than treated as unset',
    () async {
      final container = await _container(
        _Api(),
        modes: _FailedModeStore()..failRead = true,
      );
      await expectLater(
        container.read(authControllerProvider.future),
        throwsStateError,
      );
      expect(container.read(authControllerProvider).hasValue, isFalse);
      await expectLater(
        container.read(authControllerProvider.notifier).chooseCloud(),
        throwsStateError,
      );
    },
  );
}
