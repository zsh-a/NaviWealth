import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/route_paths.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/auth/data/auth_controller.dart';
import 'package:naviwealth/features/home/data/dashboard_insights_provider.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/home/domain/insight_models.dart';
import 'package:naviwealth/features/home/ui/home_greeting_header.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

class _FakeAuthController extends AuthController {
  @override
  Future<AuthState> build() async => const AuthLocalOnly();
}

DashboardHeaderMetrics _metrics({double? monthlyPct}) {
  return DashboardHeaderMetrics(
    baseCurrency: 'CNY',
    dailyChange: Money.zero('CNY'),
    monthlyChange: Money.zero('CNY'),
    monthlyChangePct: monthlyPct,
    ytdChange: Money.zero('CNY'),
    ytdChangePct: null,
  );
}

GoRouter _router({Widget child = const HomeGreetingHeader()}) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: child),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const Scaffold(body: Text('settings-route')),
      ),
    ],
  );
}

Widget _wrap({
  AsyncValue<DashboardHeaderMetrics>? metricsAsync,
  List<InsightItem> insights = const [],
}) {
  return ProviderScope(
    overrides: [
      dashboardHeaderMetricsProvider.overrideWith(
        (ref) async => metricsAsync?.value ?? _metrics(),
      ),
      authControllerProvider.overrideWith(_FakeAuthController.new),
    ],
    child: MaterialApp.router(
      routerConfig: _router(
        child: HomeGreetingHeader(insightCount: insights.length),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      builder: (context, child) =>
          FTheme(data: FThemes.slate.light.desktop, child: child!),
    ),
  );
}

void main() {
  testWidgets('renders a time-of-day greeting + shell chrome actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // The greeting hosts the cross-domain shell chrome (the Today tab has
    // no FHeader): global Search + Settings. The domain switcher chip is
    // hidden here because only one domain is registered in this scope.
    expect(find.byIcon(FLucideIcons.search), findsOneWidget);
    expect(find.byIcon(FLucideIcons.settings), findsOneWidget);
    // Some greeting is rendered — the exact text depends on local time.
    expect(find.byType(Text), findsWidgets);
  });

  testWidgets('renders no status row when there is no MTD and no insights', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // No "·" middle-dot separator appears (only used between fragments).
    expect(find.text('·'), findsNothing);
  });

  testWidgets('shows the MTD direction fragment when a monthly pct is set', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(metricsAsync: AsyncData(_metrics(monthlyPct: 0.025))),
    );
    await tester.pumpAndSettle();

    // 2.5% MTD up — the fragment includes the signed percent number.
    expect(find.textContaining('2.5%'), findsOneWidget);
  });

  testWidgets('shows the insight count fragment when insights exist', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(
        metricsAsync: AsyncData(_metrics(monthlyPct: 0.01)),
        insights: const [
          InsightItem(icon: FLucideIcons.calendar, kind: InsightKind.maturity),
          InsightItem(icon: FLucideIcons.calendar, kind: InsightKind.maturity),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Two fragments separated by middle dot.
    expect(find.text('·'), findsOneWidget);
  });

  testWidgets('does not subscribe to source insights during header build', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardHeaderMetricsProvider.overrideWith(
            (ref) async => _metrics(monthlyPct: 0.01),
          ),
          dashboardInsightsProvider.overrideWith((ref) {
            throw StateError('source insights should not be watched');
          }),
          authControllerProvider.overrideWith(_FakeAuthController.new),
        ],
        child: MaterialApp.router(
          routerConfig: _router(
            child: const HomeGreetingHeader(insightCount: 1),
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en', 'US'),
          builder: (context, child) =>
              FTheme(data: FThemes.slate.light.desktop, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('·'), findsOneWidget);
  });
}
