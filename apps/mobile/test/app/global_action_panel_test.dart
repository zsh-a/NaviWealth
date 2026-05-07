import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/global_action_panel.dart';
import 'package:naviwealth/app/route_paths.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

GoRouter _router({required bool assetPanel}) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => _PanelHost(assetPanel: assetPanel),
      ),
      for (final path in const [
        AppRoutes.expenseNew,
        AppRoutes.tradeEntry,
        AppRoutes.accountTransfer,
        AppRoutes.liabilityNew,
        AppRoutes.portfolioNewCash,
        AppRoutes.portfolioNewDeposit,
        AppRoutes.portfolioNewWealth,
      ])
        GoRoute(path: path, builder: (_, _) => _Marker(path)),
    ],
  );
}

Widget _wrap(GoRouter router) {
  return MaterialApp.router(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
  );
}

class _PanelHost extends StatelessWidget {
  const _PanelHost({required this.assetPanel});

  final bool assetPanel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            if (assetPanel) {
              showAssetActionPanel(context);
            } else {
              showGlobalActionPanel(context);
            }
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker(this.path);

  final String path;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(path));
}

Future<void> _openPanel(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(_wrap(router));
  await tester.pumpAndSettle();

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _enlarge(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('global action panel lists the primary create actions', (
    tester,
  ) async {
    await _enlarge(tester);
    final router = _router(assetPanel: false);
    addTearDown(router.dispose);

    await _openPanel(tester, router);

    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Trade'), findsOneWidget);
    expect(find.text('Asset'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
    expect(find.text('Liability'), findsOneWidget);
  });

  for (final target in const [
    ('Expense', AppRoutes.expenseNew),
    ('Trade', AppRoutes.tradeEntry),
    ('Transfer', AppRoutes.accountTransfer),
    ('Liability', AppRoutes.liabilityNew),
  ]) {
    testWidgets('${target.$1} action pushes ${target.$2}', (tester) async {
      await _enlarge(tester);
      final router = _router(assetPanel: false);
      addTearDown(router.dispose);

      await _openPanel(tester, router);
      await tester.tap(find.text(target.$1));
      await tester.pumpAndSettle();

      expect(find.text(target.$2), findsOneWidget);
    });
  }

  testWidgets('asset action opens the asset-specific panel', (tester) async {
    await _enlarge(tester);
    final router = _router(assetPanel: false);
    addTearDown(router.dispose);

    await _openPanel(tester, router);
    await tester.tap(find.text('Asset'));
    await tester.pumpAndSettle();

    expect(find.text('Cash / multi-currency balance'), findsOneWidget);
    expect(find.text('Deposit (term / demand)'), findsOneWidget);
    expect(find.text('Wealth product'), findsOneWidget);
    expect(find.text('Add real estate'), findsOneWidget);
    expect(find.text('Add vehicle'), findsOneWidget);
  });

  for (final target in const [
    ('Cash / multi-currency balance', AppRoutes.portfolioNewCash),
    ('Deposit (term / demand)', AppRoutes.portfolioNewDeposit),
    ('Wealth product', AppRoutes.portfolioNewWealth),
  ]) {
    testWidgets('${target.$1} asset action pushes ${target.$2}', (
      tester,
    ) async {
      await _enlarge(tester);
      final router = _router(assetPanel: true);
      addTearDown(router.dispose);

      await _openPanel(tester, router);
      await tester.tap(find.text(target.$1));
      await tester.pumpAndSettle();

      expect(find.text(target.$2), findsOneWidget);
    });
  }
}
