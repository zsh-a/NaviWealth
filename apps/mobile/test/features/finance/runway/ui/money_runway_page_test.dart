import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/runway/data/money_runway_providers.dart';
import 'package:naviwealth/features/finance/runway/data/runway_forecast_repository.dart';
import 'package:naviwealth/features/finance/runway/domain/money_runway.dart';
import 'package:naviwealth/features/finance/runway/ui/money_runway_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../../core/persistence/test_database.dart';

void main() {
  testWidgets('labels declared and estimated dividend cash separately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = makeTestDatabase();
    addTearDown(db.close);
    final snapshot = buildMoneyRunway(
      asOf: DateTime.utc(2026, 7, 1),
      currency: 'USD',
      startingBalance: Decimal.fromInt(1000),
      reserveTarget: Decimal.zero,
      averageMonthlyExpense: Decimal.zero,
      estimatedDailyVariableOutflow: Decimal.zero,
      scheduledFlows: [
        RunwayScheduledFlow(
          id: 'declared',
          date: DateTime.utc(2026, 7, 10),
          amount: Decimal.fromInt(80),
          label: 'Dividend',
          kind: RunwayFlowKind.dividend,
        ),
        RunwayScheduledFlow(
          id: 'estimated',
          date: DateTime.utc(2026, 8, 10),
          amount: Decimal.fromInt(60),
          label: 'Dividend',
          certainty: RunwayFlowCertainty.estimated,
          kind: RunwayFlowKind.dividend,
        ),
      ],
      confidence: MoneyRunwayConfidence.medium,
      dataCompleteness: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          moneyRunwayProvider.overrideWithValue(AsyncValue.data(snapshot)),
          runwayForecastRepositoryProvider.overrideWith(
            (_) async =>
                RunwayForecastRepository(db: db, ownerUserId: 'widget-test'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en', 'US'),
          home: const MoneyRunwayPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Declared after-tax dividend'), findsOneWidget);
    expect(find.text('Estimated after-tax dividend'), findsOneWidget);
    expect(find.textContaining('estimate'), findsOneWidget);

    await tester.ensureVisible(
      find.text('Quick stress tests · minimum balance'),
    );
    await tester.tap(find.text('Quick stress tests · minimum balance'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Custom stress test'));
    await tester.tap(find.text('Custom stress test'));
    await tester.pumpAndSettle();
    expect(find.text('Custom runway scenario'), findsOneWidget);

    await tester.tap(find.text('Run scenario'));
    await tester.pumpAndSettle();
    expect(find.text('Custom minimum balance'), findsOneWidget);
  });
}
