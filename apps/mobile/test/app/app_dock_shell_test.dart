// D-2.3b dock UI rendering tests. See `docs/lifeos-shell.md` §3 +
// `docs/healthos-domain.md` §0.
//
// Two invariants:
//   1. Finance-only (default): the dock chrome is *not* rendered;
//      the layout is identical to the pre-D-2.3b single-shell baseline.
//   2. Health opt-in: the dock chrome is rendered with both domain
//      icons; tapping the HealthOS chip lands on the Health placeholder.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/app.dart';
import 'package:naviwealth/app/route_paths.dart';
import 'package:naviwealth/app/router.dart';
import 'package:naviwealth/core/shell/domain_shell.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance_domain_shell.dart';
import 'package:naviwealth/features/health/composition/health_domain_shell.dart';
import 'package:naviwealth/features/health/ui/health_today_page.dart';
import 'package:naviwealth/features/home/home_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
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
  return container;
}

String _currentPath(ProviderContainer container) => container
    .read(appRouterProvider)
    .routeInformationProvider
    .value
    .uri
    .path;

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
    testWidgets('mobile renders both domain chips when ≥ 2 specs active', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await _pumpAt(
        tester,
        domains: <DomainShellSpec>[
          financeDomainShell(l10n),
          healthDomainShell(l10n),
        ],
      );
      expect(find.text('FinanceOS'), findsOneWidget);
      expect(find.text('HealthOS'), findsOneWidget);
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

    testWidgets('/health renders HealthTodayPage inside the dock shell',
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
      // Dock chrome is still visible.
      expect(find.text('HealthOS'), findsOneWidget);
      expect(find.text('FinanceOS'), findsOneWidget);
    });

    testWidgets('tapping HealthOS chip routes to /health', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final container = await _pumpAt(
        tester,
        domains: <DomainShellSpec>[
          financeDomainShell(l10n),
          healthDomainShell(l10n),
        ],
      );
      expect(_currentPath(container), AppRoutes.home);
      await tester.tap(find.text('HealthOS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_currentPath(container), AppRoutes.healthToday);
      expect(find.byType(HealthTodayPage), findsOneWidget);
    });
  });
}
