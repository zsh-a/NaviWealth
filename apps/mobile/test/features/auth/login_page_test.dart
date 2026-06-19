import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_api_client.dart';
import 'package:naviwealth/core/auth/auth_errors.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';
import 'package:naviwealth/features/auth/data/auth_controller.dart';
import 'package:naviwealth/features/auth/presentation/login_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

class _StubAuthApi implements AuthApiClient {
  AuthSession? loginResponse;
  Object? loginError;
  AuthSession? registerResponse;
  Object? registerError;
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
  }) => throw UnimplementedError();

  @override
  Future<DevicesResponse> listDevices(AuthSession current) =>
      throw UnimplementedError();

  @override
  Future<void> logoutDevice(AuthSession current, String deviceId) =>
      throw UnimplementedError();
}

AuthSession _session() => AuthSession(
  accessToken: 'tok',
  expiresAt: DateTime.utc(2026, 12, 1),
  userId: 'u-1',
  deviceId: 'd-1',
);

ProviderContainer _container({AuthApiClient? api, Map<String, String>? seed}) {
  return ProviderContainer(
    overrides: [
      secureKeyStoreProvider.overrideWithValue(InMemoryKeyStore(seed)),
      if (api != null) authApiClientProvider.overrideWithValue(api),
    ],
  );
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: LoginPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<AppLocalizations> _l10n(WidgetTester tester) async {
  // Find the rendered LoginPage's BuildContext to resolve localizations.
  return AppLocalizations.of(tester.element(find.byType(LoginPage)));
}

void main() {
  // Localizations require flutter_localizations delegates.
  setUpAll(() {
    GlobalMaterialLocalizations.delegate;
    GlobalWidgetsLocalizations.delegate;
    GlobalCupertinoLocalizations.delegate;
  });

  testWidgets('renders email + password fields and submit button', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await _pump(tester, container);
    final l10n = await _l10n(tester);

    expect(find.byKey(const ValueKey('login.email')), findsOneWidget);
    expect(find.byKey(const ValueKey('login.password')), findsOneWidget);
    expect(find.byKey(const ValueKey('login.submit')), findsOneWidget);
    expect(find.byKey(const ValueKey('login.toggleMode')), findsOneWidget);
    expect(find.text(l10n.authLoginSubmit), findsOneWidget);
  });

  testWidgets(
    'submitting empty form surfaces both validators and does NOT call API',
    (tester) async {
      final api = _StubAuthApi();
      final container = _container(api: api);
      addTearDown(container.dispose);
      await _pump(tester, container);
      final l10n = await _l10n(tester);

      await tester.tap(find.byKey(const ValueKey('login.submit')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.authEmailErrorEmpty), findsOneWidget);
      expect(find.text(l10n.authPasswordErrorEmpty), findsOneWidget);
      expect(api.loginCalls, isEmpty);
    },
  );

  testWidgets('rejects email without "@" client-side', (tester) async {
    final api = _StubAuthApi();
    final container = _container(api: api);
    addTearDown(container.dispose);
    await _pump(tester, container);
    final l10n = await _l10n(tester);

    await tester.enterText(
      find.byKey(const ValueKey('login.email')),
      'not-an-email',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login.password')),
      'password123',
    );
    await tester.tap(find.byKey(const ValueKey('login.submit')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.authEmailErrorInvalid), findsOneWidget);
    expect(api.loginCalls, isEmpty);
  });

  testWidgets('rejects passwords shorter than 8 characters', (tester) async {
    final container = _container(api: _StubAuthApi());
    addTearDown(container.dispose);
    await _pump(tester, container);
    final l10n = await _l10n(tester);

    await tester.enterText(
      find.byKey(const ValueKey('login.email')),
      'a@b.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login.password')),
      'short',
    );
    await tester.tap(find.byKey(const ValueKey('login.submit')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.authPasswordErrorTooShort), findsOneWidget);
  });

  testWidgets('successful login persists session and toggles AuthLoggedIn', (
    tester,
  ) async {
    final api = _StubAuthApi()..loginResponse = _session();
    final container = _container(api: api);
    addTearDown(container.dispose);
    // Make sure AuthController has settled on AuthLoggedOut.
    await container.read(authControllerProvider.future);
    await _pump(tester, container);

    await tester.enterText(
      find.byKey(const ValueKey('login.email')),
      'a@b.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login.password')),
      'hunter22',
    );
    await tester.tap(find.byKey(const ValueKey('login.submit')));
    await tester.pumpAndSettle();

    expect(api.loginCalls, hasLength(1));
    expect(api.loginCalls.single.email, 'a@b.com');
    expect(api.loginCalls.single.password, 'hunter22');
    expect(container.read(authControllerProvider).value, isA<AuthLoggedIn>());
    expect((await container.read(tokenStoreProvider).read())!.userId, 'u-1');
  });

  testWidgets('registration mode creates account and persists session', (
    tester,
  ) async {
    final api = _StubAuthApi()..registerResponse = _session();
    final container = _container(api: api);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await _pump(tester, container);
    final l10n = await _l10n(tester);

    await tester.tap(find.byKey(const ValueKey('login.toggleMode')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('login.submit')),
        matching: find.text(l10n.authRegisterSubmit),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('login.email')),
      'new@user.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login.password')),
      'hunter22',
    );
    await tester.tap(find.byKey(const ValueKey('login.submit')));
    await tester.pumpAndSettle();

    expect(api.registerCalls, hasLength(1));
    expect(api.registerCalls.single.email, 'new@user.com');
    expect(api.loginCalls, isEmpty);
    expect(container.read(authControllerProvider).value, isA<AuthLoggedIn>());
  });

  testWidgets('registration closed error uses account-exists banner', (
    tester,
  ) async {
    final api = _StubAuthApi()
      ..registerError = AuthException(AuthErrorKind.accountExists);
    final container = _container(api: api);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await _pump(tester, container);
    final l10n = await _l10n(tester);

    await tester.tap(find.byKey(const ValueKey('login.toggleMode')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('login.email')),
      'new@user.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login.password')),
      'hunter22',
    );
    await tester.tap(find.byKey(const ValueKey('login.submit')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.authRegisterErrorAccountExists), findsOneWidget);
    expect(container.read(authControllerProvider).value, isA<AuthLoggedOut>());
  });

  testWidgets('invalid credentials → inline error banner', (tester) async {
    final api = _StubAuthApi()
      ..loginError = AuthException(AuthErrorKind.invalidCredentials);
    final container = _container(api: api);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await _pump(tester, container);
    final l10n = await _l10n(tester);

    await tester.enterText(
      find.byKey(const ValueKey('login.email')),
      'a@b.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login.password')),
      'badpassword',
    );
    await tester.tap(find.byKey(const ValueKey('login.submit')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.authLoginErrorInvalidCredentials), findsOneWidget);
    expect(container.read(authControllerProvider).value, isA<AuthLoggedOut>());
  });

  testWidgets('network failure → "couldn\'t reach server" banner', (
    tester,
  ) async {
    final api = _StubAuthApi()
      ..loginError = AuthException(AuthErrorKind.network);
    final container = _container(api: api);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await _pump(tester, container);
    final l10n = await _l10n(tester);

    await tester.enterText(
      find.byKey(const ValueKey('login.email')),
      'a@b.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login.password')),
      'password123',
    );
    await tester.tap(find.byKey(const ValueKey('login.submit')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.authLoginErrorNetwork), findsOneWidget);
  });

  testWidgets('expired-session banner appears when controller emits expired', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    // Manually set the controller's state to AuthLoggedOut(expired).
    await container.read(authControllerProvider.future);
    container
        .read(authControllerProvider.notifier)
        .state = const AsyncData<AuthState>(
      AuthLoggedOut(reason: LoggedOutReason.sessionExpired),
    );

    await _pump(tester, container);
    final l10n = await _l10n(tester);

    expect(find.text(l10n.authLoginNoticeSessionExpired), findsOneWidget);
  });
}
