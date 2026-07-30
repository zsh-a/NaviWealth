import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/analytics/data/providers.dart';
import 'package:naviwealth/features/finance/analytics/domain/concentration_risk.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_providers.dart';
import 'package:naviwealth/features/finance/investment/data/portfolio_trend_providers.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/allocation/portfolio_allocation_tree.dart';
import 'package:naviwealth/features/finance/investment/domain/fx_pnl/fx_pnl_breakdown.dart';
import 'package:naviwealth/features/finance/investment/domain/models/investment_portfolio.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/portfolio_capital_assignment.dart';
import 'package:naviwealth/features/finance/investment/domain/portfolio_trend.dart';
import 'package:naviwealth/features/finance/investment/domain/reporting/holding_report.dart';
import 'package:naviwealth/features/finance/investment/domain/returns/portfolio_return.dart';
import 'package:naviwealth/features/finance/investment/domain/returns/xirr_engine.dart';
import 'package:naviwealth/features/finance/investment/ui/portfolio_hub_page.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
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
  testWidgets('portfolio studio presents one four-section workspace', (
    tester,
  ) async {
    final portfolio = InvestmentPortfolio(
      id: 'portfolio',
      name: 'Long term',
      baseCurrency: 'USD',
      goalId: null,
      color: null,
      createdAt: DateTime.utc(2026, 7, 30),
      archived: false,
      sync: _meta(),
    );
    const root = AllocationNode(
      id: 'plan',
      parentId: null,
      type: AllocationNodeType.plan,
      name: 'Investment plan',
      targetWeightBps: 10000,
      driftBandBps: 0,
      transferPolicy: GroupTransferPolicy.bidirectional,
    );
    const portfolioNode = AllocationNode(
      id: 'portfolio:portfolio',
      parentId: 'plan',
      type: AllocationNodeType.portfolio,
      name: 'Long term',
      targetWeightBps: 10000,
      driftBandBps: 500,
      transferPolicy: GroupTransferPolicy.bidirectional,
      referenceId: 'portfolio',
    );
    const sleeveNode = AllocationNode(
      id: 'sleeve:core',
      parentId: 'portfolio:portfolio',
      type: AllocationNodeType.sleeve,
      name: 'Index core',
      targetWeightBps: 10000,
      driftBandBps: 500,
      transferPolicy: GroupTransferPolicy.bidirectional,
      referenceId: 'core',
    );
    const tree = PortfolioAllocationTree(
      root: root,
      nodes: [root, portfolioNode, sleeveNode],
      attachments: [],
      inclusions: [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          investmentPortfoliosProvider.overrideWith(
            (ref) => Stream.value([portfolio]),
          ),
          portfolioAllocationTreeProvider.overrideWithValue(
            const AsyncData(tree),
          ),
          portfolioTrendProvider(
            const PortfolioTrendRequest(
              portfolioId: 'portfolio',
              range: PortfolioTrendRange.month,
            ),
          ).overrideWith((ref) async => null),
        ],
        child: FTheme(
          data: FThemes.slate.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const PortfolioStudioPage(portfolioId: 'portfolio'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Long term'), findsWidgets);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Structure'), findsOneWidget);
    expect(find.text('Assets'), findsOneWidget);
    expect(find.text('Rules'), findsWidgets);
    expect(find.text('Capital path'), findsOneWidget);
    expect(find.text('Index core'), findsOneWidget);
    expect(find.text('Check rebalance'), findsOneWidget);
  });

  testWidgets('portfolio studio switches between value and performance trend', (
    tester,
  ) async {
    final portfolio = InvestmentPortfolio(
      id: 'portfolio',
      name: 'Long term',
      baseCurrency: 'USD',
      goalId: null,
      color: null,
      createdAt: DateTime.utc(2026, 6, 1),
      archived: false,
      sync: _meta(),
    );
    const root = AllocationNode(
      id: 'plan',
      parentId: null,
      type: AllocationNodeType.plan,
      name: 'Investment plan',
      targetWeightBps: 10000,
      driftBandBps: 0,
      transferPolicy: GroupTransferPolicy.bidirectional,
    );
    const portfolioNode = AllocationNode(
      id: 'portfolio:portfolio',
      parentId: 'plan',
      type: AllocationNodeType.portfolio,
      name: 'Long term',
      targetWeightBps: 10000,
      driftBandBps: 500,
      transferPolicy: GroupTransferPolicy.bidirectional,
      referenceId: 'portfolio',
    );
    const sleeveNode = AllocationNode(
      id: 'sleeve:core',
      parentId: 'portfolio:portfolio',
      type: AllocationNodeType.sleeve,
      name: 'Index core',
      targetWeightBps: 10000,
      driftBandBps: 500,
      transferPolicy: GroupTransferPolicy.bidirectional,
      referenceId: 'core',
    );
    const tree = PortfolioAllocationTree(
      root: root,
      nodes: [root, portfolioNode, sleeveNode],
      attachments: [],
      inclusions: [],
    );
    final trend = PortfolioTrendSeries(
      portfolioId: 'portfolio',
      baseCurrency: 'USD',
      range: PortfolioTrendRange.month,
      points: [
        PortfolioTrendPoint(
          asOf: DateTime.utc(2026, 7, 1),
          marketValueInBase: _d('1000'),
          costBasisInBase: _d('900'),
          cashValueInBase: Decimal.zero,
          netFlowInBase: Decimal.zero,
          performanceRatio: 0,
          quality: PortfolioTrendQuality.complete,
        ),
        PortfolioTrendPoint(
          asOf: DateTime.utc(2026, 7, 30),
          marketValueInBase: _d('1100'),
          costBasisInBase: _d('900'),
          cashValueInBase: Decimal.zero,
          netFlowInBase: Decimal.zero,
          performanceRatio: 0.1,
          quality: PortfolioTrendQuality.complete,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          investmentPortfoliosProvider.overrideWith(
            (ref) => Stream.value([portfolio]),
          ),
          portfolioAllocationTreeProvider.overrideWithValue(
            const AsyncData(tree),
          ),
          portfolioTrendProvider(
            const PortfolioTrendRequest(
              portfolioId: 'portfolio',
              range: PortfolioTrendRange.month,
            ),
          ).overrideWith((ref) async => trend),
        ],
        child: FTheme(
          data: FThemes.slate.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const PortfolioStudioPage(portfolioId: 'portfolio'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Portfolio trend'), findsOneWidget);
    expect(find.text('Current value'), findsOneWidget);
    expect(find.text('Period return'), findsOneWidget);
    expect(find.text('Net capital flow'), findsOneWidget);
    expect(
      tester
          .widget<NwLineChart>(
            find.descendant(
              of: find.byKey(const ValueKey('portfolio-trend-chart')),
              matching: find.byType(NwLineChart),
            ),
          )
          .yAxis
          .format,
      ValueAxisFormat.currency,
    );

    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<NwLineChart>(
            find.descendant(
              of: find.byKey(const ValueKey('portfolio-trend-chart')),
              matching: find.byType(NwLineChart),
            ),
          )
          .yAxis
          .format,
      ValueAxisFormat.percent,
    );
  });

  testWidgets('portfolio studio resolves target and included asset details', (
    tester,
  ) async {
    final portfolio = InvestmentPortfolio(
      id: 'portfolio',
      name: 'Long term',
      baseCurrency: 'USD',
      goalId: null,
      color: null,
      createdAt: DateTime.utc(2026, 7, 30),
      archived: false,
      sync: _meta(),
    );
    const root = AllocationNode(
      id: 'plan',
      parentId: null,
      type: AllocationNodeType.plan,
      name: 'Investment plan',
      targetWeightBps: 10000,
      driftBandBps: 0,
      transferPolicy: GroupTransferPolicy.bidirectional,
    );
    const portfolioNode = AllocationNode(
      id: 'portfolio:portfolio',
      parentId: 'plan',
      type: AllocationNodeType.portfolio,
      name: 'Long term',
      targetWeightBps: 10000,
      driftBandBps: 500,
      transferPolicy: GroupTransferPolicy.bidirectional,
      referenceId: 'portfolio',
    );
    const sleeveNode = AllocationNode(
      id: 'sleeve:core',
      parentId: 'portfolio:portfolio',
      type: AllocationNodeType.sleeve,
      name: 'Index core',
      targetWeightBps: 10000,
      driftBandBps: 500,
      transferPolicy: GroupTransferPolicy.bidirectional,
      referenceId: 'core',
    );
    const assetTarget = AllocationNode(
      id: 'sleeve:core:asset:us:AAPL',
      parentId: 'sleeve:core',
      type: AllocationNodeType.asset,
      name: 'Apple target',
      targetWeightBps: 6000,
      driftBandBps: 500,
      transferPolicy: GroupTransferPolicy.isolated,
      referenceId: 'us:AAPL',
      assetKind: AllocationAssetKind.security,
      assetCategory: AssetCategory.stock,
    );
    final assignment = PortfolioCapitalAssignment(
      id: 'assignment',
      portfolioId: 'portfolio',
      rebalanceGroupId: 'core',
      sourceKind: PortfolioCapitalSourceKind.lot,
      sourceId: 'lot-aapl',
      quantity: null,
      amount: null,
      currency: null,
      assignedAt: DateTime.utc(2026, 7, 30),
      sync: _meta(),
    );
    final tree = PortfolioAllocationTree(
      root: root,
      nodes: const [root, portfolioNode, sleeveNode, assetTarget],
      attachments: const [],
      inclusions: [
        CapitalInclusion(
          id: assignment.id,
          sleeveId: sleeveNode.id,
          assignment: assignment,
        ),
      ],
    );
    final lot = _lot(
      id: 'lot-aapl',
      accountId: 'broker-a',
      assetId: 'us:AAPL',
      quantity: '10',
      costPerUnit: '100',
    );
    final asset = Asset(
      id: 'us:AAPL',
      type: AssetType.stock,
      symbol: 'AAPL',
      currency: 'USD',
      name: 'Apple Inc.',
      sync: _meta(),
    );
    final account = Account(
      id: 'broker-a',
      type: AccountCategory.broker,
      name: 'Broker A',
      currency: 'USD',
      sync: _meta(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          investmentPortfoliosProvider.overrideWith(
            (ref) => Stream.value([portfolio]),
          ),
          portfolioAllocationTreeProvider.overrideWithValue(AsyncData(tree)),
          allInvestmentLotsProvider.overrideWith((ref) async => [lot]),
          allAssetsStreamProvider.overrideWith((ref) => Stream.value([asset])),
          accountsStreamProvider.overrideWith((ref) => Stream.value([account])),
          portfolioTrendProvider(
            const PortfolioTrendRequest(
              portfolioId: 'portfolio',
              range: PortfolioTrendRange.month,
            ),
          ).overrideWith((ref) async => null),
        ],
        child: FTheme(
          data: FThemes.slate.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const PortfolioStudioPage(
              portfolioId: 'portfolio',
              initialSection: 'assets',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Asset targets'), findsOneWidget);
    expect(find.text('Apple target'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
    expect(
      find.text('Apple Inc. · Index core · Quantity 10 · Broker A'),
      findsOneWidget,
    );
    expect(find.text(r'$1,000.00'), findsOneWidget);
    expect(find.text('Cost basis'), findsOneWidget);
    expect(find.text('Position lot'), findsNothing);
  });

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
    expect(find.byType(AppAdaptiveSelectionMenu<String>), findsOneWidget);
    expect(find.byType(FSelect<String>), findsNothing);
    expect(find.bySemanticsLabel('Portfolio: All holdings'), findsOneWidget);
    expect(find.text('All holdings'), findsOneWidget);
    // Positions use a virtualized DecoratedSliver group surface.
    expect(find.byType(DecoratedSliver), findsOneWidget);
    expect(find.text('Broker A'), findsNothing);
    expect(find.text('us:AAPL'), findsWidgets);
    expect(find.text('Cost basis'), findsOneWidget);

    await tester.tap(find.text('Allocation'));
    await tester.pumpAndSettle();
    expect(find.text('Broker A'), findsOneWidget);
    // No concentration breaches → review surface stays hidden.
    expect(find.text('Concentration risk'), findsNothing);

    await tester.tap(find.text('Class'));
    await tester.pumpAndSettle();
    expect(find.byIcon(FLucideIcons.chevronRight), findsOneWidget);

    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('portfolio-group-detail')),
      findsOneWidget,
    );
    expect(find.text('Market value'), findsWidgets);
    expect(find.text('Unrealized P&L'), findsOneWidget);
  });

  testWidgets('allocation tab shows concentration breaches from provider', (
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
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioHubProvider.overrideWith(
            () => _StaticPortfolioHubNotifier(state),
          ),
          concentrationAlertsProvider.overrideWith(
            (ref) async => [
              ConcentrationAlert(
                dimension: RiskDimension.asset,
                severity: RiskSeverity.critical,
                label: 'AAPL',
                weight: 0.42,
                threshold: 0.20,
                valueInBase: _d('42'),
                assetIds: const ['us:AAPL'],
              ),
            ],
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

    await tester.tap(find.text('Allocation'));
    await tester.pumpAndSettle();

    expect(find.text('Concentration risk'), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.textContaining('42.0%'), findsOneWidget);
    expect(find.text('Review rebalance plan'), findsOneWidget);
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
    );

    final accountGroups = state.groupsFor(PortfolioHubView.account, l10n);
    expect(accountGroups.map((group) => group.title), ['Broker B', 'Broker A']);
    expect(accountGroups.first.marketValueInBase, _d('350.000000000000'));
    expect(accountGroups.first.holdingsCount, 2);
    expect(accountGroups.first.holdings.first.assetId, 'hk:2800');
    expect(accountGroups.first.holdings.first.marketValueInBase, _d('300'));
    expect(accountGroups.first.holdings.last.assetId, 'us:AAPL');
    expect(
      accountGroups.first.holdings.last.marketValueInBase,
      _d('50.000000000000'),
    );
    expect(accountGroups.first.holdings.last.quantity, _d('5'));
    expect(accountGroups.last.holdings.single.weight, Decimal.one);

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
