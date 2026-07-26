import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/income_strategy/data/providers.dart';
import 'package:naviwealth/features/finance/income_strategy/domain/income_strategy.dart';
import 'package:naviwealth/features/finance/income_strategy/ui/income_strategy_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

const _asset = IncomeStrategyAsset(
  assetId: 'us_stock:AAPL',
  symbol: 'AAPL',
  market: 'us_stock',
  currency: 'USD',
  label: 'Apple',
);

IncomeStrategySleeveSnapshot _sleeve(
  IncomeStrategySleeveKind kind,
  String result,
) => IncomeStrategySleeveSnapshot(
  kind: kind,
  status: 'active',
  realizedResult: Decimal.parse(result),
  projectedCash: Decimal.zero,
  capitalAtRisk: Decimal.fromInt(1000),
  marketValue: null,
  deltaEquivalentShares: null,
  cashFlows: const [],
  risks: const [],
);

PortfolioIncomeStrategySnapshot _snapshot() => PortfolioIncomeStrategySnapshot(
  baseCurrency: 'USD',
  underlyings: [
    UnderlyingIncomeStrategySnapshot(
      asset: _asset,
      enabledSleeves: IncomeStrategySleeveKind.values.toSet(),
      sleeves: {
        IncomeStrategySleeveKind.dividends: _sleeve(
          IncomeStrategySleeveKind.dividends,
          '300',
        ),
        IncomeStrategySleeveKind.wheel: _sleeve(
          IncomeStrategySleeveKind.wheel,
          '200',
        ),
        IncomeStrategySleeveKind.leapsCall: _sleeve(
          IncomeStrategySleeveKind.leapsCall,
          '100',
        ),
      },
      risks: const [
        IncomeStrategyRisk(
          code: IncomeStrategyRiskCode.stackedDownside,
          severity: IncomeStrategyRiskSeverity.warning,
          assetId: 'us_stock:AAPL',
          sleeves: {
            IncomeStrategySleeveKind.wheel,
            IncomeStrategySleeveKind.leapsCall,
          },
        ),
      ],
    ),
  ],
  unassignedCashFlows: const [],
);

void main() {
  testWidgets('renders composable strategy tracks on a compact phone', (
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
    await tester.tap(find.text('Underlyings'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('Dividends'), findsOneWidget);
    expect(find.text('Wheel'), findsOneWidget);
    expect(find.text('LEAPS call'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
