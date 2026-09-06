import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/ui/wealth/wealth_action_panel.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(GoRouter router) {
  return MaterialApp.router(
    routerConfig: router,
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'CN'),
    builder: (_, child) =>
        FTheme(data: FTheme.neutral.light.desktop, child: child!),
  );
}

void main() {
  testWidgets(
    'compact wealth panel opens asset capture without a second menu',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showWealthActionPanel(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: FinanceRoutes.wealthNewCash,
            builder: (_, _) => const Scaffold(body: Text('cash capture')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_wrap(router));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('添加资产项目'), findsOneWidget);
      final cash = find.text('现金与多币种余额');
      await tester.ensureVisible(cash);
      await tester.tap(cash);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('cash capture'), findsOneWidget);
      expect(find.text('添加资产项目'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
