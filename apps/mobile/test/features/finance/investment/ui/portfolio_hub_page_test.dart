import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/features/finance/investment/domain/fx_pnl/fx_pnl_breakdown.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/reporting/holding_report.dart';
import 'package:naviwealth/features/finance/investment/domain/returns/portfolio_return.dart';
import 'package:naviwealth/features/finance/investment/domain/returns/xirr_engine.dart';
import 'package:naviwealth/features/finance/investment/ui/portfolio_hub_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:naviwealth/l10n/gen/app_localizations_en.dart';

Decimal _d(String value) => Decimal.parse(value);

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 5, 17),
  updatedByDevice: 'test',
  hlc: Hlc.zero('test'),
);

PortfolioHoldingRow _holding({
  required String assetId,
  required AssetType type,
  required String currency,
  required String marketValue,
  required String costBasis,
}) {
  final value = _d(marketValue);
  final cost = _d(costBasis);
  return PortfolioHoldingRow(
    assetId: assetId,
    title: assetId,
    subtitle: assetId,
    assetType: type,
    assetCurrency: currency,
    quantity: _d('10'),
    marketValueInBase: value,
    costBasisInBase: cost,
    unrealizedPnlInBase: value - cost,
    weight: Decimal.zero,
    baseCurrency: 'USD',
  );
}

Lot _lot({
  required String id,
  required String accountId,
  required String assetId,
  required String quantity,
  required String costPerUnit,
}) {
  return Lot(
    id: id,
    openingTransactionId: 'tx-$id',
    accountId: accountId,
    assetId: assetId,
    currency: 'USD',
    originalQuantity: _d(quantity),
    remainingQuantity: _d(quantity),
    costPerUnit: _d(costPerUnit),
    openedAt: DateTime.utc(2025, 1, 1),
  );
}

void main() {
  testWidgets('portfolio hub renders retryable error state', (tester) async {
    final notifier = _FailingPortfolioHubNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [portfolioHubProvider.overrideWith(() => notifier)],
        child: FTheme(
          data: FThemes.slate.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const PortfolioHubPage(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text("We couldn't complete that. Please try again."), findsOne);
    expect(find.textContaining('Bad state: boom'), findsNothing);
    expect(find.text('Retry'), findsOne);
    expect(find.byType(AppActionButton), findsOneWidget);
    expect(find.text('No investment holdings yet.'), findsNothing);
    expect(notifier.fetchCount, 1);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(notifier.fetchCount, 2);
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('portfolio rows share grouped surfaces inside adaptive frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = PortfolioHubState(
      holdings: [
        _holding(
          assetId: 'us:AAPL',
          type: AssetType.stock,
          currency: 'USD',
          marketValue: '100',
          costBasis: '80',
        ),
      ],
      lots: [
        _lot(
          id: 'aapl-1',
          accountId: 'broker-a',
          assetId: 'us:AAPL',
          quantity: '10',
          costPerUnit: '8',
        ),
      ],
      accountById: {
        'broker-a': Account(
          id: 'broker-a',
          type: AccountCategory.broker,
          name: 'Broker A',
          currency: 'USD',
          sync: _meta(),
        ),
      },
      baseCurrency: 'USD',
      marketValueInBase: _d('100'),
      costBasisInBase: _d('80'),
      unrealizedPnlInBase: _d('20'),
      ytdReturn: PortfolioReturnResult(
        from: DateTime.utc(2026),
        to: DateTime.utc(2026, 5, 17),
        baseCurrency: 'USD',
        cashFlows: const [],
        solution: const XirrConverged(rate: 0.12, iterations: 3),
      ),
      realizedPnl: const [],
      dividendForecast: ProjectedDividend.empty(
        assetId: 'portfolio',
        currency: 'USD',
        strategy: 'composite',
        confidence: DividendForecastConfidence.low,
      ),
      dividendEvents: const [],
      corporateActions: const [],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioHubProvider.overrideWith(
            () => _StaticPortfolioHubNotifier(state),
          ),
        ],
        child: FTheme(
          data: FThemes.slate.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const PortfolioHubPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdaptiveContentFrame), findsOneWidget);
    expect(find.byType(AppGroupedSurface), findsNWidgets(2));
    expect(find.text('Broker A'), findsOneWidget);
    expect(find.text('us:AAPL'), findsWidgets);
  });

  test('aggregates holdings by account, currency, and asset class', () {
    final l10n = AppLocalizationsEn();
    final state = PortfolioHubState(
      holdings: [
        _holding(
          assetId: 'us:AAPL',
          type: AssetType.stock,
          currency: 'USD',
          marketValue: '100',
          costBasis: '80',
        ),
        _holding(
          assetId: 'hk:2800',
          type: AssetType.etf,
          currency: 'HKD',
          marketValue: '300',
          costBasis: '240',
        ),
      ],
      lots: [
        _lot(
          id: 'aapl-1',
          accountId: 'broker-a',
          assetId: 'us:AAPL',
          quantity: '5',
          costPerUnit: '8',
        ),
        _lot(
          id: 'aapl-2',
          accountId: 'broker-b',
          assetId: 'us:AAPL',
          quantity: '5',
          costPerUnit: '8',
        ),
        _lot(
          id: '2800-1',
          accountId: 'broker-b',
          assetId: 'hk:2800',
          quantity: '10',
          costPerUnit: '24',
        ),
      ],
      accountById: {
        'broker-a': Account(
          id: 'broker-a',
          type: AccountCategory.broker,
          name: 'Broker A',
          currency: 'USD',
          sync: _meta(),
        ),
        'broker-b': Account(
          id: 'broker-b',
          type: AccountCategory.broker,
          name: 'Broker B',
          currency: 'USD',
          sync: _meta(),
        ),
      },
      baseCurrency: 'USD',
      marketValueInBase: _d('400'),
      costBasisInBase: _d('320'),
      unrealizedPnlInBase: _d('80'),
      ytdReturn: PortfolioReturnResult(
        from: DateTime.utc(2026),
        to: DateTime.utc(2026, 5, 17),
        baseCurrency: 'USD',
        cashFlows: const [],
        solution: const XirrConverged(rate: 0.12, iterations: 3),
      ),
      realizedPnl: const [],
      dividendForecast: ProjectedDividend.empty(
        assetId: 'portfolio',
        currency: 'USD',
        strategy: 'composite',
        confidence: DividendForecastConfidence.low,
      ),
      dividendEvents: const [],
      corporateActions: const [],
    );

    final accountGroups = state.groupsFor(PortfolioHubView.account, l10n);
    expect(accountGroups.map((group) => group.title), ['Broker B', 'Broker A']);
    expect(accountGroups.first.marketValueInBase, _d('350.000000000000'));
    expect(accountGroups.first.holdingsCount, 2);

    final currencyGroups = state.groupsFor(PortfolioHubView.currency, l10n);
    expect(currencyGroups.map((group) => group.title), ['HKD', 'USD']);
    expect(currencyGroups.first.marketValueInBase, _d('300'));

    final assetClassGroups = state.groupsFor(PortfolioHubView.assetClass, l10n);
    expect(assetClassGroups.map((group) => group.title), ['ETF', 'Stock']);
    expect(assetClassGroups.first.unrealizedPnlInBase, _d('60'));
  });

  test('portfolio FX PnL provider exposes total report breakdown', () async {
    final report = PortfolioHoldingReport(
      assets: const {},
      totalCostBasisAtOpenFxInBase: _d('100'),
      totalMarketValueInBase: _d('130'),
      totalPnlBreakdown: FxPnLBreakdown(
        marketPnLInBase: _d('20'),
        fxPnLInBase: _d('10'),
        baseCurrency: 'USD',
      ),
      baseCurrency: 'USD',
      asOf: DateTime.utc(2026, 5, 17),
    );
    final container = ProviderContainer(
      overrides: [
        portfolioHoldingReportProvider.overrideWith((_) async => report),
      ],
    );
    addTearDown(container.dispose);

    await container.read(portfolioHoldingReportProvider.future);

    expect(container.read(portfolioFxPnlProvider).marketPnLInBase, _d('20'));
    expect(container.read(portfolioFxPnlProvider).fxPnLInBase, _d('10'));
  });
}

class _FailingPortfolioHubNotifier extends PortfolioHubNotifier {
  int fetchCount = 0;

  @override
  Future<PortfolioHubState> fetch() async {
    fetchCount += 1;
    throw StateError('boom');
  }
}

class _StaticPortfolioHubNotifier extends PortfolioHubNotifier {
  _StaticPortfolioHubNotifier(this.value);

  final PortfolioHubState value;

  @override
  Future<PortfolioHubState> fetch() async => value;
}
