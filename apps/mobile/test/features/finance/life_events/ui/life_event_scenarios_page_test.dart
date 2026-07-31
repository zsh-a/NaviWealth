import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_projection.dart';
import 'package:naviwealth/features/finance/life_events/data/financial_decision_providers.dart';
import 'package:naviwealth/features/finance/life_events/domain/financial_decision.dart';
import 'package:naviwealth/features/finance/life_events/domain/life_event_scenario.dart';
import 'package:naviwealth/features/finance/life_events/ui/life_event_scenarios_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('shows one selected scenario instead of a three-card wall', (
    tester,
  ) async {
    final baseline = LifeEventBaseline(
      liquidBalance: Decimal.fromInt(120000),
      monthlyIncome: Decimal.fromInt(30000),
      monthlyOutflow: Decimal.fromInt(18000),
      currency: 'CNY',
      fireMonthsToTarget: 72,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lifeEventBaselineProvider.overrideWithValue(baseline),
          financialDecisionsProvider.overrideWith(
            (_) => Stream.value(const <FinancialDecision>[]),
          ),
          fireDashboardViewProvider.overrideWith(
            (_) => const AsyncValue<FireDashboardView>.loading(),
          ),
        ],
        child: FTheme(
          data: FThemes.slate.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const LifeEventScenariosPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Large purchase'), findsNWidgets(2));
    expect(find.text('Career break'), findsNothing);
    expect(find.text('Home purchase'), findsNothing);

    await tester.tap(
      find.bySemanticsLabel('Life-event scenarios: Large purchase'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Career break'), findsOneWidget);
    expect(find.text('Home purchase'), findsOneWidget);

    await tester.tap(find.text('Career break'));
    await tester.pumpAndSettle();

    expect(find.text('Large purchase'), findsNothing);
    expect(find.text('Career break'), findsNWidgets(2));
    expect(find.text('Home purchase'), findsNothing);
  });
}
