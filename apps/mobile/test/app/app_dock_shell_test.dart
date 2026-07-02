// D-2.3b dock UI rendering tests. See `docs/architecture/lifeos-shell.md` §3 +
// `docs/domains/healthos-domain.md` §0.
//
// Two invariants:
//   1. Finance-only (default): no switcher UI surfaces at all;
//      layout is identical to the pre-D-2.3b single-shell baseline.
//   2. Health opt-in: mobile exposes a compact current-domain switcher
//      above the bottom nav, and tapping it shows a sheet that routes to
//      the picked domain.
//      Desktop keeps the always-visible left dock at ≥ 600 px.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/app/route_paths.dart';
import 'package:naviwealth/app/router.dart';
import 'package:naviwealth/app/shell_chrome.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/shell/domain_shell.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_domain_shell.dart';
import 'package:naviwealth/features/health/composition/health_domain_shell.dart';
import 'package:naviwealth/features/health/ui/health_today_page.dart';
import 'package:naviwealth/features/home/home_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/persistence/test_database.dart';

const Size _mobileSize = Size(400, 800);
const Size _desktopSize = Size(1440, 900);

Future<ProviderContainer> _pumpAt(
  WidgetTester tester, {
  String initialLocation = '/',
  Size viewportSize = _mobileSize,
  required List<DomainShellSpec> domains,
}) async {
  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = makeTestDatabase();
  addTearDown(db.close);
  await DomainOptInStore(
    db,
  ).write(DomainOptIns(<DomainScope>{for (final d in domains) d.scope}));
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWith((_) async => db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      // Register the production pack inventory so the router has routes
      // to mount under the dock shell. Tests still control dock UI by
      // overriding `activeDomainShellsProvider` below.
      domainPackRegistryProvider.overrideWithValue(kAllDomainPacks),
      appRouterProvider.overrideWith(
        (ref) => buildAppRouter(ref, initialLocation: initialLocation),
      ),
      // Bypass the opt-in plumbing: the dock chrome only watches
      // activeDomainShellsProvider + domainDockVisibleProvider, so
      // overriding the list directly is the minimal surface tests need.
      activeDomainShellsProvider.overrideWith((_) => domains),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const NaviWealthApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 350));
  return container;
}

String _currentPath(ProviderContainer container) =>
    container.read(appRouterProvider).routeInformationProvider.value.uri.path;

void main() {
  setUp(() {
    final originalHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      originalHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalHandler);
  });

  group('Finance-only baseline (D-2.3b regression guard)', () {
    testWidgets('dock chrome is absent when only one domain is registered', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pumpAt(
        tester,
        domains: <DomainShellSpec>[financeDomainShell(l10n)],
      );

      expect(find.byType(HomePage), findsOneWidget);
      // The HealthOS chip + icon should *not* be present.
      expect(find.text('HealthOS'), findsNothing);
      expect(find.text('FinanceOS'), findsNothing);
    });
  });

  group('Multi-domain dock (Health opt-in)', () {
    testWidgets('mobile exposes current-domain switcher above bottom nav', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pumpAt(
        tester,
        initialLocation: AppRoutes.activity,
        domains: <DomainShellSpec>[
          financeDomainShell(l10n),
          healthDomainShell(l10n),
        ],
      );
      expect(find.byType(DomainSwitcherChip), findsOneWidget);
      expect(find.text('HealthOS'), findsNothing);
    });

    testWidgets('desktop renders left dock icons + Finance tabs', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pumpAt(
        tester,
        viewportSize: _desktopSize,
        domains: <DomainShellSpec>[
          financeDomainShell(l10n),
          healthDomainShell(l10n),
        ],
      );
      // Desktop dock is icon-only with FTooltip; we just assert that the
      // Finance domain tab labels resolve (proving the inner shell is
      // mounted alongside the dock).
      expect(find.text(l10n.navToday), findsOneWidget);
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets(
      '/health renders HealthTodayPage with plain title (no chevron)',
      (tester) async {
        final l10n = lookupAppLocalizations(const Locale('en'));
        final container = await _pumpAt(
          tester,
          initialLocation: AppRoutes.healthToday,
          domains: <DomainShellSpec>[
            financeDomainShell(l10n),
            healthDomainShell(l10n),
          ],
        );
        expect(_currentPath(container), AppRoutes.healthToday);
        expect(find.byType(HealthTodayPage), findsOneWidget);
        expect(find.text(l10n.healthTodayTitle), findsOneWidget);
        expect(find.text('FinanceOS'), findsNothing);
        expect(find.byType(DomainSwitcherChip), findsOneWidget);
      },
    );

    testWidgets('tapping the mobile domain switcher opens the sheet', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final container = await _pumpAt(
        tester,
        initialLocation: AppRoutes.activity,
        domains: <DomainShellSpec>[
          financeDomainShell(l10n),
          healthDomainShell(l10n),
        ],
      );
      await tester.tap(find.byType(DomainSwitcherChip));
      // Drive the sheet animation manually; pumpAndSettle never
      // settles because the home dashboard owns a periodic ticker.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Sheet exposes both domain labels.
      expect(find.text('FinanceOS'), findsOneWidget);
      expect(find.text('HealthOS'), findsOneWidget);

      // Tapping HealthOS in the sheet navigates to /health.
      await tester.tap(find.text('HealthOS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(_currentPath(container), AppRoutes.healthToday);
      expect(find.byType(HealthTodayPage), findsOneWidget);
    });
  });
}
