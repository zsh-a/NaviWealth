import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_center_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_forecast_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_forecast_repository.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_event.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_kind.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/cashflow/ui/dividend_center_page.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('empty state CTA routes to corporate action entry page', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: AppRoutes.cashflowDividends,
      routes: [
        GoRoute(
          path: AppRoutes.cashflowDividends,
          builder: (_, _) => const DividendCenterPage(),
        ),
        GoRoute(
          path: AppRoutes.wealthCorporateAction,
          builder: (_, _) => const Scaffold(
            body: Center(child: Text('Corporate action target')),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dividendCenterSnapshotProvider.overrideWith(
            (_) async => _emptySnapshot(),
          ),
          dividendForecast12mProvider.overrideWith(
            (_) async => ProjectedDividend.empty(
              assetId: 'portfolio',
              currency: 'USD',
              strategy: 'composite',
              confidence: DividendForecastConfidence.low,
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No dividend records yet'), findsOneWidget);
    expect(find.text('Next 12 months'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dividend-center-record-cta')));
    await tester.pumpAndSettle();

    expect(find.text('Corporate action target'), findsOneWidget);
  });

  testWidgets('shows after-tax KPI, income watch and resilience review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final amount = Decimal.fromInt(100);
    final priorEvent = DividendCenterEvent(
      event: CashFlowEvent(
        journalEntryId: 'prior',
        date: DateTime.utc(2024, 9, 1),
        kind: CashFlowKind.dividend,
        signedAmount: amount,
        originalAmount: amount,
        currency: 'USD',
        accountId: 'cash',
        counterAccountSide: AccountSide.income,
      ),
      assetId: 'us:AAPL',
      assetLabel: 'AAPL',
      withholdingInBase: Decimal.fromInt(10),
      withholdingOriginal: Decimal.fromInt(10),
      withholdingCurrency: 'USD',
    );
    final snapshot = DividendCenterSnapshot(
      baseCurrency: 'USD',
      yearToDateGross: Decimal.fromInt(90),
      ttmGross: Decimal.fromInt(100),
      priorYearToDateGross: Decimal.fromInt(100),
      ttmWithholding: Decimal.fromInt(10),
      events: [priorEvent],
      ranking: [
        DividendHoldingRank(
          assetId: 'us:AAPL',
          assetLabel: 'AAPL',
          ttmGrossInBase: Decimal.fromInt(100),
          withholdingInBase: Decimal.fromInt(10),
          portfolioShare: 1,
          yieldOnCost: 0.05,
          netYieldOnCost: 0.045,
        ),
      ],
      months: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dividendCenterSnapshotProvider.overrideWith((_) async => snapshot),
          dividendCenterNowProvider.overrideWithValue(DateTime.utc(2026, 7, 1)),
          holdingsSnapshotProvider.overrideWith(
            (_) async => {
              'us:AAPL': HoldingSnapshot(
                assetId: 'us:AAPL',
                quantity: Decimal.one,
                costBasisInAssetCurrency: Decimal.fromInt(2000),
                marketValueInAssetCurrency: Decimal.fromInt(2000),
                assetCurrency: 'USD',
                costBasisInBase: Decimal.fromInt(2000),
                marketValueInBase: Decimal.fromInt(2000),
                unrealizedPnlInBase: Decimal.zero,
                weight: Decimal.one,
                baseCurrency: 'USD',
                asOf: DateTime.utc(2026, 7, 1),
              ),
            },
          ),
          dividendForecast12mProvider.overrideWith(
            (_) async => ProjectedDividend.empty(
              assetId: 'portfolio',
              currency: 'USD',
              strategy: 'composite',
              confidence: DividendForecastConfidence.low,
            ),
          ),
          dividendForecastQualityProvider.overrideWith(
            (_) async => const DividendForecastQuality(
              evaluatedCount: 3,
              meanRelativeError: 0.2,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en', 'US'),
          home: const DividendCenterPage(focusAssetId: 'us:AAPL'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TTM after tax'), findsOneWidget);
    expect(find.text('Dividend income watch'), findsOneWidget);
    expect(find.text('Historical dividend resilience'), findsOneWidget);
    expect(find.textContaining('confidence'), findsWidgets);
    expect(find.textContaining('not a backtest'), findsOneWidget);
    expect(find.textContaining('90-day historical error'), findsOneWidget);
    expect(find.text('AAPL'), findsWidgets);
    final focusedAttribution = tester.widget<AppTappable>(
      find.byKey(const ValueKey('dividend-attribution-us:AAPL')),
    );
    expect((focusedAttribution.child as Container).decoration, isNotNull);
    // Compact ranking embeds the yield label in a multi-metric detail line.
    expect(find.textContaining('Net yield on cost'), findsOneWidget);
  });
}

DividendCenterSnapshot _emptySnapshot() => DividendCenterSnapshot(
  baseCurrency: 'USD',
  yearToDateGross: Decimal.zero,
  ttmGross: Decimal.zero,
  priorYearToDateGross: Decimal.zero,
  ttmWithholding: Decimal.zero,
  events: const [],
  ranking: const [],
  months: const [],
);
