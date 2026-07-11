import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/security/biometric_auth_service.dart';
import 'package:naviwealth/core/security/biometric_lock_preferences.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/settings/ui/domains_settings_page.dart';
import 'package:naviwealth/features/settings/ui/settings_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/test_database.dart';

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
}) async {
  final db = makeTestDatabase();
  addTearDown(db.close);
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWith((_) async => db),
      domainPackRegistryProvider.overrideWithValue(kAllDomainPacks),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: _router(initialLocation: initialLocation),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  group('Settings → Base currency', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('shows the current base currency in the trailing label', (
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

    testWidgets(
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
              domainPackRegistryProvider.overrideWithValue(kAllDomainPacks),
            ],
            child: MaterialApp.router(
              theme: AppTheme.light(),
              routerConfig: _router(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context, listen: false);
                  return child!;
                },
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

  group('Settings → Domains', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('renders optional domain toggles from the shared spec list', (
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
        find.text('Personal decisions and cognitive memory'),
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
    });
  });

  group('Settings → KnowledgeOS', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('surfaces only operational KnowledgeOS settings', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        await _wrap(prefs, initialLocation: AppRoutes.settingsDomainsKnowledge),
      );
      await tester.pumpAndSettle();

      expect(find.text('KnowledgeOS · Inbox'), findsNothing);
      expect(find.text('KnowledgeOS · Library'), findsNothing);
      expect(find.text('KnowledgeOS · Review'), findsNothing);
      expect(find.text('KnowledgeOS Memory'), findsOneWidget);
      expect(find.text('Agents'), findsOneWidget);
    });
  });

  group('Settings → ExecutionOS', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('surfaces only operational ExecutionOS settings', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        await _wrap(prefs, initialLocation: AppRoutes.settingsDomainsExecution),
      );
      await tester.pumpAndSettle();

      expect(find.text('ExecutionOS · Today'), findsNothing);
      expect(find.text('ExecutionOS · Commitments'), findsNothing);
      expect(find.text('ExecutionOS · Review'), findsNothing);
      expect(find.text('Agents'), findsOneWidget);
    });
  });

  group('Settings → Security', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('enables biometric unlock after a successful prompt', (
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
              data: FThemes.slate.light.desktop,
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
