import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/runway/data/money_runway_providers.dart';
import 'package:naviwealth/features/finance/runway/data/runway_forecast_repository.dart';
import 'package:naviwealth/features/finance/runway/domain/money_runway.dart';
import 'package:naviwealth/features/finance/runway/ui/money_runway_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../../core/persistence/test_database.dart';

void main() {
  testWidgets('summarizes upcoming flows and keeps one custom stress test', (
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
        for (var index = 1; index <= 6; index++)
          RunwayScheduledFlow(
            id: 'scheduled-$index',
            date: DateTime.utc(2026, 7, 10 + index),
            amount: Decimal.fromInt(-10),
            label: 'Scheduled $index',
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
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const MoneyRunwayPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('8 upcoming items included'), findsOneWidget);
    expect(find.text('Declared after-tax dividend'), findsNothing);
    expect(find.text('Estimated after-tax dividend'), findsNothing);

    final details = find.byKey(const ValueKey('runway-timeline-details'));
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    final position = tester.getTopLeft(details);
    expect(find.text('Scheduled 6'), findsNothing);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.byType(AppSheet), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Scheduled 6'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(AppSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Scheduled 6'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('finance-detail-close')));
    await tester.pumpAndSettle();
    expect(find.text('Scheduled 6'), findsNothing);
    expect(tester.getTopLeft(details), position);

    await tester.ensureVisible(find.text('Custom stress test'));
    await tester.tap(find.text('Custom stress test'));
    await tester.pumpAndSettle();
    expect(find.text('Custom runway scenario'), findsOneWidget);

    await tester.tap(find.text('Run scenario'));
    await tester.pumpAndSettle();
    expect(find.text('Custom minimum balance'), findsOneWidget);
  });
}
