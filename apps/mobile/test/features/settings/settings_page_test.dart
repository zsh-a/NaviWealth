import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/route_paths.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/data/base_currency_preference.dart';
import 'package:naviwealth/features/settings/settings_page.dart';
import 'package:naviwealth/features/settings/ui/domains_settings_page.dart';
import 'package:naviwealth/features/settings/ui/knowledge_domain_settings_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/test_database.dart';

GoRouter _router({String initialLocation = AppRoutes.settingsDomains}) {
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
            path: 'domains/knowledge',
            name: AppRouteNames.domainsKnowledge,
            builder: (_, _) => const KnowledgeDomainSettingsPage(),
          ),
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

  group('Settings → KnowledgeOS', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('surfaces inbox, library, review, and memory settings', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        await _wrap(prefs, initialLocation: AppRoutes.settingsDomainsKnowledge),
      );
      await tester.pumpAndSettle();

      expect(find.text('KnowledgeOS · Inbox'), findsOneWidget);
      expect(find.text('KnowledgeOS · Library'), findsOneWidget);
      expect(find.text('KnowledgeOS · Review'), findsOneWidget);
      expect(find.text('KnowledgeOS Memory'), findsOneWidget);
    });
  });
}
