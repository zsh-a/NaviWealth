// D-2.3b dock UI rendering tests. See `docs/architecture/lifeos-shell.md` §3 +
// `docs/domains/healthos-domain.md` §0.
//
// Two invariants:
//   1. Desktop always has one unified Life/domain/tab sidebar, including
//      Finance-only installs; compact widths avoid redundant shell chrome.
//   2. Health opt-in: mobile exposes a compact current-domain switcher
//      above the bottom nav, and tapping it shows a sheet that routes to
//      the picked domain.
//      Compact widths keep icon rails; the full tab sidebar starts at 1280.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' show FHeader;
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/app/routing/router.dart';
import 'package:naviwealth/app/shell/shell_chrome.dart';
import 'package:naviwealth/core/ai/composition/ai_context.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/shell/desktop_sidebar.dart';
import 'package:naviwealth/core/shell/domain_shell.dart';
import 'package:naviwealth/core/shell/shell_preferences.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_domain_shell.dart';
import 'package:naviwealth/features/finance/home/ui/home_page.dart';
import 'package:naviwealth/features/health/composition/health_domain_shell.dart';
import 'package:naviwealth/features/health/ui/health_today_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/persistence/test_database.dart';
import '../features/finance/data/repositories/_stub_stamper.dart';

const Size _mobileSize = Size(400, 800);
const Size _desktopSize = Size(1440, 900);

Future<ProviderContainer> _pumpAt(
  WidgetTester tester, {
  String initialLocation = '/',
  Size viewportSize = _mobileSize,
  required List<DomainShellSpec> domains,
  bool aiSupported = true,
}) async {
  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'ai_privacy.onboarding_seen.v1': true,
  });
  final prefs = await SharedPreferences.getInstance();
  final db = makeTestDatabase();
  addTearDown(db.close);
  await DomainOptInStore(db)
      .write(DomainOptIns(<DomainScope>{for (final d in domains) d.scope}));
  final container = ProviderContainer(
    overrides: [
      deviceLlmPlatformSupportedProvider.overrideWithValue(aiSupported),
      appDatabaseProvider.overrideWith((_) async => db),
      mutationStamperProvider.overrideWith((_) async => makeStubStamper()),
      currentUserIdProvider.overrideWithValue(() async => 'u-test'),
      activeUserIdProvider.overrideWithValue('u-test'),
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...appShellChromeOverrides(),
      // Register the production pack inventory so the router has routes
      // to mount under the dock shell. Tests still control dock UI by
      // overriding `activeDomainShellsProvider` below.
      domainPackRegistryProvider.overrideWithValue(kAllDomainPacks),
      appRouterProvider.overrideWith(
        (ref) => buildAppRouter(ref, initialLocation: initialLocation),
      ),
      // Bypass the opt-in plumbing: the dock chrome only watches
      // activeDomainShellsProvider, so overriding the list directly is the
      // minimal surface tests need.
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
  // Route performance traces close 750 ms after the last named transition.
  // Advance beyond that bounded window so flutter_test sees no live timer.
  await tester.pump(const Duration(milliseconds: 800));
  return container;
}

String _currentPath(ProviderContainer container) =>
    container.read(appRouterProvider).routeInformationProvider.value.uri.path;

String _currentAiContextPath(ProviderContainer container) =>
    container.read(aiContextProvider).path;

void main() {
  setUp(() {
    final originalHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      originalHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalHandler);
  });

  testWidgets('desktop hides Ask AI when the runtime is unsupported', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    await _pumpAt(
      tester,
      viewportSize: _desktopSize,
      domains: [financeDomainShell(l10n)],
      aiSupported: false,
    );
    expect(find.text(l10n.navAskAi), findsNothing);
    expect(find.byType(DesktopSidebar), findsOneWidget);
  });

  group('Finance-only shell', () {
    testWidgets('compact chrome stays domain-local with one domain', (
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

    testWidgets('desktop keeps one unified sidebar with one domain', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pumpAt(
        tester,
        viewportSize: _desktopSize,
        domains: <DomainShellSpec>[financeDomainShell(l10n)],
      );

      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(find.text(l10n.lifeNavLabel), findsOneWidget);
      expect(find.text(l10n.navToday), findsOneWidget);
    });

    for (final testCase in <({double width, double sidebarWidth})>[
      (width: 1200, sidebarWidth: kSidebarCollapsedWidth),
      (width: 1359, sidebarWidth: kSidebarCollapsedWidth),
      (width: 1360, sidebarWidth: kSidebarExpandedWidth),
      (width: 1440, sidebarWidth: kSidebarExpandedWidth),
    ]) {
      testWidgets(
        'desktop sidebar is ${testCase.sidebarWidth}dp at ${testCase.width}px',
        (tester) async {
          final l10n = lookupAppLocalizations(const Locale('en'));
          await _pumpAt(
            tester,
            viewportSize: Size(testCase.width, 900),
            domains: <DomainShellSpec>[financeDomainShell(l10n)],
          );

          expect(
            tester.getSize(find.byType(DesktopSidebar)).width,
            testCase.sidebarWidth,
          );
        },
      );
    }

    testWidgets('Life workspace does not inherit Finance destinations', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pumpAt(
        tester,
        initialLocation: AppRoutes.life,
        viewportSize: _desktopSize,
        domains: <DomainShellSpec>[financeDomainShell(l10n)],
      );

      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(find.text(l10n.lifeNavLabel), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(DesktopSidebar),
          matching: find.text(l10n.navToday),
        ),
        findsNothing,
      );
    });
  });

  group('Multi-domain dock (Health opt-in)', () {
    // Below shellDesktop (=large, 1200) the header chip is the switcher;
    // at and above it the always-visible dock takes over — exactly one
    // switching affordance per tier, with no dead band (doc 15 §7.2).
    for (final testCase
        in <({double width, bool mobile, bool desktop, bool chip})>[
          (width: 599, mobile: true, desktop: false, chip: true),
          (width: 600, mobile: false, desktop: false, chip: true),
          (width: 1199, mobile: false, desktop: false, chip: true),
          (width: 1200, mobile: false, desktop: true, chip: false),
          (width: 1440, mobile: false, desktop: true, chip: false),
        ]) {
      testWidgets('uses one shell tier at ${testCase.width}px', (tester) async {
        final l10n = lookupAppLocalizations(const Locale('en'));
        await _pumpAt(
          tester,
          initialLocation: AppRoutes.activity,
          viewportSize: Size(testCase.width, 900),
          domains: <DomainShellSpec>[
            financeDomainShell(l10n),
            healthDomainShell(l10n),
          ],
        );

        expect(
          find.byType(FloatingGlassNavBar),
          testCase.mobile ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(DesktopSidebar),
          testCase.desktop ? findsOneWidget : findsNothing,
        );
        final switcher = find.byType(DomainSwitcherChip);
        if (testCase.chip) {
          expect(switcher, findsOneWidget);
          expect(tester.getSize(switcher).width, greaterThan(0));
        } else if (switcher.evaluate().isNotEmpty) {
          expect(tester.getSize(switcher), Size.zero);
        }
      });
    }

    testWidgets('tablet rail does not duplicate the header switcher', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pumpAt(
        tester,
        initialLocation: AppRoutes.activity,
        viewportSize: const Size(600, 900),
        domains: <DomainShellSpec>[
          financeDomainShell(l10n),
          healthDomainShell(l10n),
        ],
      );

      expect(find.byType(DomainSwitcherChip), findsOneWidget);
      expect(find.text(l10n.shellSwitchDomainTitle), findsNothing);
    });

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
      '/health renders HealthTodayPage with task heading (no FHeader)',
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
        expect(_currentAiContextPath(container), AppRoutes.healthToday);
        expect(find.byType(HealthTodayPage), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(HealthTodayPage),
            matching: find.text(l10n.healthOverviewTitle),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(HealthTodayPage),
            matching: find.byType(FHeader),
          ),
          findsNothing,
        );
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
      expect(find.text('Finance'), findsNWidgets(2));
      expect(find.text('Health'), findsOneWidget);

      // Tapping Health closes the sheet first. Route construction must not
      // overlap the reverse sheet animation.
      await tester.tap(find.text('Health'));
      await tester.pump();
      expect(_currentPath(container), AppRoutes.activity);

      await tester.pump(const Duration(milliseconds: 219));
      expect(_currentPath(container), AppRoutes.activity);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_currentPath(container), AppRoutes.healthToday);
      expect(_currentAiContextPath(container), AppRoutes.healthToday);
      expect(find.byType(HealthTodayPage), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 800));
    });
  });
}
