import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/accounts/data/account_balances_provider.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/ui/plan_hub_page.dart';
import 'package:naviwealth/features/finance/ui/wealth/wealth_hub_page.dart';
import 'package:naviwealth/features/fire/data/fire_providers.dart';
import 'package:naviwealth/features/home/data/dashboard_providers.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('Plan hub shows actionable planning groups', (tester) async {
    await _setDesktopSurface(tester);
    await tester.pumpWidget(
      _wrap(
        overrides: [
          fireDashboardViewProvider.overrideWith(
            (_) => const AsyncValue.loading(),
          ),
        ],
        child: const PlanHubPage(),
      ),
    );
    await tester.pump();

    expect(find.text('FIRE'), findsOneWidget);
    expect(find.text('Planning'), findsOneWidget);
    expect(find.text('Strategy tools'), findsOneWidget);
    expect(find.text('Rebalance'), findsOneWidget);
    expect(find.text('DCA simulator'), findsOneWidget);
    expect(find.text('Budget'), findsOneWidget);
    expect(find.text('Scenario analytics'), findsNothing);
    expect(find.text('Scenarios'), findsNothing);
    expect(find.text('Goals'), findsNothing);
  });

  testWidgets('Wealth hub hides placeholder-only entries', (tester) async {
    await _setDesktopSurface(tester);
    await tester.pumpWidget(
      _wrap(
        overrides: [
          accountsStreamProvider.overrideWith((_) => Stream.value(const [])),
          accountBalancesByIdProvider.overrideWith(
            (_) => Stream.value(const {}),
          ),
          dashboardSnapshotProvider.overrideWith(
            (_) async => DashboardSnapshot.empty(
              asOf: DateTime.utc(2026, 6, 1),
              baseCurrency: 'USD',
            ),
          ),
        ],
        child: const WealthHubPage(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Holdings'), findsOneWidget);
    expect(find.text('Income projection'), findsNothing);
  });
}

Widget _wrap({required Widget child, List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

Future<void> _setDesktopSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
