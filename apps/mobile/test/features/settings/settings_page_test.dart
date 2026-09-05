import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/security/biometric_auth_service.dart';
import 'package:naviwealth/core/security/biometric_lock_preferences.dart';
import 'package:naviwealth/core/shell/settings_route_paths.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/settings/ui/advanced_settings_page.dart';
import 'package:naviwealth/features/settings/ui/ai/ai_settings_hub_page.dart';
import 'package:naviwealth/features/settings/ui/data_management/data_management_page.dart';
import 'package:naviwealth/features/settings/ui/domains_settings_page.dart';
import 'package:naviwealth/features/settings/ui/settings_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/test_database.dart';

void _testWidgets(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      // Riverpod closes the Drift stream store asynchronously when the
      // ProviderScope is unmounted. Flush that cleanup before flutter_test
      // checks for leaked timers.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 600));
    }
  });
}

GoRouter _router({
  String initialLocation = AppRoutes.settingsDomains,
  List<DomainPack>? packs,
}) {
  final resolvedPacks = packs ?? kAllDomainPacks;
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsPage(),
        routes: [
          GoRoute(
            path: 'domains',
            name: AppRouteNames.domains,
            builder: (_, _) => const DomainsSettingsPage(),
          ),
          GoRoute(
            path: 'data-management',
            name: AppRouteNames.dataManagement,
            builder: (_, _) => const DataManagementPage(),
          ),
          GoRoute(
            path: 'ai',
            name: SettingsRouteNames.ai,
            builder: (_, _) => const AiSettingsHubPage(),
          ),
          GoRoute(
            path: 'advanced',
            name: SettingsRouteNames.advanced,
            builder: (_, _) => const AdvancedSettingsPage(),
            routes: [
              GoRoute(
                path: 'data-maintenance',
                name: SettingsRouteNames.dataMaintenance,
                builder: (_, _) => const DataManagementPage.maintenance(),
              ),
            ],
          ),
          for (final pack in resolvedPacks)
            if (pack.settingsSpec?.routeBuilder != null)
              pack.settingsSpec!.routeBuilder!((child) => child),
        ],
      ),
    ],
  );
}

Future<Widget> _wrap(
  SharedPreferences prefs, {
  String initialLocation = AppRoutes.settingsDomains,
  Locale? locale,
  TextScaler? textScaler,
  bool aiSupported = true,
}) async {
  final db = makeTestDatabase();
  addTearDown(db.close);
  return ProviderScope(
    overrides: [
      deviceLlmPlatformSupportedProvider.overrideWithValue(aiSupported),
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWith((_) async => db),
      currentUserIdProvider.overrideWithValue(() async => kLocalOnlyUserId),
      domainPackRegistryProvider.overrideWithValue(kAllDomainPacks),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: _router(initialLocation: initialLocation),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      builder: (context, child) => FTheme(
        data: buildAppForuiTheme(brightness: Brightness.light, touch: true),
        child: textScaler == null
            ? child!
            : MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              ),
      ),
    ),
  );
}

void main() {
  group('Settings → Data & storage', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    _testWidgets('shows all domains including disabled optional domains', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        await _wrap(prefs, initialLocation: AppRoutes.settingsDataManagement),
      );
      await tester.pumpAndSettle();

      expect(find.text('Data & storage'), findsOneWidget);
      expect(find.text('FinanceOS'), findsOneWidget);
      expect(find.text('HealthOS'), findsOneWidget);
      expect(find.text('KnowledgeOS'), findsOneWidget);
      expect(find.text('ExecutionOS'), findsOneWidget);
      expect(find.text('Disabled'), findsNWidgets(3));
      expect(find.text('Automatic maintenance'), findsNothing);
      expect(find.text('Compact database'), findsNothing);
      expect(find.text('All OS data'), findsOneWidget);
    });

    _testWidgets('keeps storage internals in advanced maintenance', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        await _wrap(prefs, initialLocation: AppRoutes.settingsDataMaintenance),
      );
      await tester.pumpAndSettle();

      expect(find.text('Storage maintenance'), findsOneWidget);
      expect(find.text('Automatic maintenance'), findsOneWidget);
      expect(find.text('Compact database'), findsOneWidget);
      expect(find.text('Clear local history'), findsNothing);
      expect(find.text('All OS data'), findsNothing);
    });
  });

  group('Settings → Base currency', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    _testWidgets('shows the current base currency in the trailing label', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(await _wrap(prefs));
      await tester.pumpAndSettle();

      // Wave 41 — the row renders the full `currencyDisplayLabel`
      // ("CNY · Chinese Yuan") rather than a bare code, so match by
      // substring. The pre-Wave-36 trailing chip used bare codes; the
      // test wasn't updated when the row migrated to InlineSettingRow.
      expect(find.textContaining('CNY'), findsWidgets);
    });

    _testWidgets(
      'tapping the row opens the picker and persists the new selection',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        final db = makeTestDatabase();
        addTearDown(db.close);
        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              appDatabaseProvider.overrideWith((_) async => db),
              currentUserIdProvider.overrideWithValue(
                () async => kLocalOnlyUserId,
              ),
              domainPackRegistryProvider.overrideWithValue(kAllDomainPacks),
            ],
            child: MaterialApp.router(
              theme: AppTheme.light(),
              routerConfig: _router(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => FTheme(
                data: buildAppForuiTheme(
                  brightness: Brightness.light,
                  touch: true,
                ),
                child: Consumer(
                  builder: (context, ref, _) {
                    container = ProviderScope.containerOf(
                      context,
                      listen: false,
                    );
                    return child!;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the Base currency row's tile (titled by its localized label).
        await tester.tap(find.text('Base currency'));
        await tester.pumpAndSettle();

        // Picker sheet lists the common currencies — pick USD.
        await tester.tap(find.text('USD · US Dollar'));
        await tester.pumpAndSettle();

        expect(container.read(baseCurrencyProvider), 'USD');
        // Trailing label updates to reflect the new selection — match
        // by substring (full label is "USD · US Dollar").
        expect(find.textContaining('USD'), findsWidgets);
      },
    );
  });

  group('Settings → Appearance', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    _testWidgets(
      'keeps the localized market color choice readable on a phone',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          await _wrap(prefs, initialLocation: AppRoutes.settings),
        );
        await tester.pumpAndSettle();

        final label = find.text('Up / down colors');
        final selected = find.text('Red up / green down (CN)');
        await tester.ensureVisible(label);
        await tester.pumpAndSettle();

        expect(label, findsOneWidget);
        expect(selected, findsOneWidget);
        expect(
          tester.getTopLeft(selected).dy,
          greaterThan(tester.getTopLeft(label).dy),
        );
        expect(tester.widget<Text>(label).maxLines, 2);
        expect(tester.widget<Text>(selected).maxLines, 2);

        await tester.tap(label);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Green up / red down (Intl)'));
        await tester.pumpAndSettle();

        expect(find.text('Green up / red down (Intl)'), findsOneWidget);
      },
    );
  });

  group('Settings → Progressive disclosure', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    _testWidgets('keeps AI and diagnostics details off the root page', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        await _wrap(prefs, initialLocation: AppRoutes.settings),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI assistant'), findsOneWidget);
      expect(find.text('AI privacy'), findsNothing);
      expect(find.text('AI Models'), findsNothing);
      expect(find.text('App Logs'), findsNothing);

      await tester.ensureVisible(find.text('AI assistant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI assistant'));
      await tester.pumpAndSettle();

      expect(find.text('AI privacy'), findsOneWidget);
      expect(find.text('AI Models'), findsOneWidget);
      expect(find.text('Agents'), findsNothing);
      expect(find.text('AI transparency'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('app.back')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      expect(find.text('App Logs'), findsOneWidget);
      expect(find.text('Performance'), findsOneWidget);
      expect(find.text('Agents'), findsOneWidget);
      expect(find.text('AI transparency'), findsOneWidget);
    });
  });

  group('Settings → Domains', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    _testWidgets('renders optional domain toggles from the shared spec list', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(await _wrap(prefs));
      await tester.pumpAndSettle();

      expect(find.text('HealthOS'), findsOneWidget);
      expect(find.text('KnowledgeOS'), findsOneWidget);
      expect(find.text('ExecutionOS'), findsOneWidget);
      expect(find.text('Turn on AI tools and Memory indexing'), findsOneWidget);
      expect(
        find.text('A personal memory for notes and decisions'),
        findsOneWidget,
      );
      expect(
        find.text('Turn decisions and plans into trackable actions.'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('HealthOS'));
      await tester.pumpAndSettle();
      final healthSwitch = find.descendant(
        of: find.ancestor(
          of: find.text('HealthOS'),
          matching: find.byType(Row),
        ),
        matching: find.byType(FSwitch),
      );
      await tester.tap(healthSwitch.first);
      await tester.pumpAndSettle();

      expect(
        find.text('AI tools and Memory indexing are enabled'),
        findsOneWidget,
      );
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      expect(find.text('Configure HealthOS'), findsOneWidget);
      expect(find.text('Configure KnowledgeOS'), findsNothing);
      expect(find.text('Configure ExecutionOS'), findsNothing);

      await tester.tap(find.text('Configure HealthOS'));
      await tester.pumpAndSettle();
      expect(find.text('Connected data sources'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('app.back')));
      await tester.pumpAndSettle();
      expect(find.text('Configure HealthOS'), findsOneWidget);
      expect(find.text('Domain management'), findsOneWidget);
    });
  });

  group('Settings → hierarchy', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    _testWidgets('shows the new grouped labels in Chinese', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        await _wrap(
          prefs,
          initialLocation: AppRoutes.settings,
          locale: const Locale('zh'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('数据与同步'), findsOneWidget);
      expect(find.text('通知与隐私'), findsOneWidget);
      expect(find.text('关于与诊断'), findsOneWidget);
    });

    _testWidgets('shows one standalone AI entry on a wide surface', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        await _wrap(prefs, initialLocation: AppRoutes.settings),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI assistant'), findsOneWidget);
      expect(find.text('AI'), findsNothing);
      expect(find.text('Data & sync'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _testWidgets('exposes conversations from the AI hub', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        await _wrap(prefs, initialLocation: AppRoutes.settingsAi),
      );
      await tester.pumpAndSettle();

      expect(find.text('Conversations'), findsOneWidget);
      expect(
        find.text('Continue or review your AI conversations'),
        findsOneWidget,
      );
    });

    _testWidgets('unsupported platforms keep history but hide native setup', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        await _wrap(
          prefs,
          initialLocation: AppRoutes.settingsAi,
          aiSupported: false,
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(AiSettingsHubPage)),
      );
      expect(find.text(l10n.settingsAiNativeOnly), findsOneWidget);
      expect(find.text(l10n.settingsAiLlmTitle), findsNothing);
      expect(find.text(l10n.settingsAiModelsTitle), findsNothing);
      expect(find.text(l10n.settingsAiHistoryTitle), findsOneWidget);
      expect(find.text(l10n.personalMemoryTitle), findsOneWidget);
    });

    _testWidgets('does not overflow at large text scale', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        await _wrap(
          prefs,
          initialLocation: AppRoutes.settings,
          textScaler: const TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();

      final exception = tester.takeException();
      expect(exception, isNull);
      expect(find.text('AI assistant'), findsOneWidget);
    });
  });

  group('Settings → Security', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    _testWidgets('enables biometric unlock after a successful prompt', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final prefs = await SharedPreferences.getInstance();
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWith((_) async {
              final db = makeTestDatabase();
              addTearDown(db.close);
              return db;
            }),
            biometricAuthServiceProvider.overrideWithValue(
              _FakeBiometricAuthService(
                availability: BiometricAvailability.available,
              ),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: _router(initialLocation: AppRoutes.settings),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => FTheme(
              data: FTheme.neutral.light.desktop,
              child: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context, listen: false);
                  return child!;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Biometric unlock'));
      await tester.pumpAndSettle();
      final biometricSwitch = find.descendant(
        of: find.ancestor(
          of: find.text('Biometric unlock'),
          matching: find.byType(Row),
        ),
        matching: find.byType(FSwitch),
      );
      await tester.tap(biometricSwitch.first);
      await tester.pumpAndSettle();

      expect(container.read(biometricUnlockEnabledProvider), isTrue);
    });
  });
}

class _FakeBiometricAuthService implements BiometricAuthService {
  _FakeBiometricAuthService({required BiometricAvailability availability})
    : _availability = availability;

  final BiometricAvailability _availability;

  @override
  Future<BiometricAvailability> availability() async => _availability;

  @override
  Future<bool> authenticate({required String reason}) async {
    return true;
  }
}
