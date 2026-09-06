import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/income_strategy/data/providers.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/income_strategy/ui/income_strategy_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../../support/test_app_theme.dart';

void main() {
  testWidgets('renders registered strategy modules on a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioIncomeStrategyProvider.overrideWith(
            (ref) async => _snapshot(),
          ),
          incomeStrategyPlansProvider.overrideWith((ref) async* {
            yield const [];
          }),
        ],
        child: MaterialApp(
          builder: buildTestAppTheme,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en', 'US'),
          home: const IncomeStrategyPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Income strategy'), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('Dividends'), findsOneWidget);
    expect(find.text('Wheel'), findsOneWidget);
    expect(find.text('LEAPS call'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

PortfolioIncomeStrategySnapshot _snapshot() {
  final asOf = DateTime.utc(2026, 7, 26);
  final sleeves = <IncomeStrategySleeveKind, IncomeStrategySleeveSnapshot>{
    for (final kind in [
      IncomeStrategySleeveKind.dividends,
      IncomeStrategySleeveKind.wheel,
      IncomeStrategySleeveKind.leapsCall,
    ])
      kind: IncomeStrategySleeveSnapshot(
        kind: kind,
        status: 'open',
        periodStart: DateTime.utc(2026),
        asOf: asOf,
        realizedIncome: IncomeStrategyMoneyMetric.zero('USD'),
        realizedResult: IncomeStrategyMoneyMetric(
          value: Money(Decimal.fromInt(100), 'USD'),
        ),
        projectedCash: IncomeStrategyMoneyMetric.zero('USD'),
        exposure: IncomeStrategyExposure(
          capitalAtRisk: IncomeStrategyMoneyMetric.zero('USD'),
        ),
        cashFlows: const [],
        risks: const [],
      ),
  };
  return PortfolioIncomeStrategySnapshot(
    baseCurrency: 'USD',
    periodStart: DateTime.utc(2026),
    asOf: asOf,
    unassignedCashFlows: const [],
    underlyings: [
      UnderlyingIncomeStrategySnapshot(
        asset: const IncomeStrategyAsset(
          assetId: 'nasdaq:AAPL',
          symbol: 'AAPL',
          market: 'nasdaq',
          currency: 'USD',
          label: 'Apple',
        ),
        baseCurrency: 'USD',
        periodStart: DateTime.utc(2026),
        asOf: asOf,
        enabledSleeves: sleeves.keys.toSet(),
        sleeves: sleeves,
        risks: const [],
      ),
    ],
  );
}
