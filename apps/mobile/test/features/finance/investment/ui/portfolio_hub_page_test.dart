import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/analytics/data/providers.dart';
import 'package:naviwealth/features/finance/analytics/domain/concentration_risk.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_providers.dart';
import 'package:naviwealth/features/finance/investment/data/investment_portfolio_repository.dart';
import 'package:naviwealth/features/finance/investment/data/portfolio_trend_providers.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/allocation/portfolio_allocation_tree.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/features/finance/investment/domain/fx_pnl/fx_pnl_breakdown.dart';
import 'package:naviwealth/features/finance/investment/domain/models/investment_portfolio.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/portfolio_capital_assignment.dart';
import 'package:naviwealth/features/finance/investment/domain/portfolio_trend.dart';
import 'package:naviwealth/features/finance/investment/domain/reporting/holding_report.dart';
import 'package:naviwealth/features/finance/investment/domain/returns/portfolio_return.dart';
import 'package:naviwealth/features/finance/investment/domain/returns/xirr_engine.dart';
import 'package:naviwealth/features/finance/investment/ui/portfolio_hub_page.dart';
import 'package:naviwealth/features/finance/rebalance/data/rebalance_providers.dart';
import 'package:naviwealth/features/finance/rebalance/domain/capital_allocation_engine.dart';
import 'package:naviwealth/features/finance/rebalance/domain/hierarchical_rebalance_engine.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_universe.dart';
import 'package:naviwealth/features/finance/rebalance/domain/universe_rebalance_engine.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:naviwealth/l10n/gen/app_localizations_en.dart';

Decimal _d(String value) => Decimal.parse(value);

class _PlanRepository extends Fake implements InvestmentPortfolioRepository {
  List<PortfolioAllocationTarget>? saved;
  VoidCallback? onSaved;

  @override
  Future<List<PortfolioAllocationTarget>> updatePortfolioPlan({
    required String universeId,
    required List<PortfolioAllocationTarget> targets,
  }) async {
    expect(universeId, 'plan');
    saved = targets;
    onSaved?.call();
    return targets;
  }
}

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
  testWidgets(
    'selected portfolio has a direct management route and explains unavailable XIRR',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final portfolio = InvestmentPortfolio(
        id: 'long-term',
        name: 'Long term',
        baseCurrency: 'USD',
        goalId: null,
        color: null,
        createdAt: DateTime.utc(2026),
        archived: false,
        sync: _meta(),
      );
      final incomePortfolio = InvestmentPortfolio(
        id: 'income',
        name: 'Income',
        baseCurrency: 'USD',
        goalId: null,
        color: null,
        createdAt: DateTime.utc(2026),
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
        id: 'portfolio:long-term',
        parentId: 'plan',
        type: AllocationNodeType.portfolio,
        name: 'Long term',
        referenceId: 'long-term',
        targetWeightBps: 6000,
        driftBandBps: 500,
        transferPolicy: GroupTransferPolicy.bidirectional,
      );
      const incomeNode = AllocationNode(
        id: 'portfolio:income',
        parentId: 'plan',
        type: AllocationNodeType.portfolio,
        name: 'Income',
        referenceId: 'income',
        targetWeightBps: 4000,
        driftBandBps: 500,
        transferPolicy: GroupTransferPolicy.bidirectional,
      );
      AsyncValue<RebalanceUniverse?> valuationState = const AsyncData(null);
      UniverseRebalancePlan? valuationPlan;
      final state = PortfolioHubState(
        holdings: const [],
        lots: const [],
        accountById: const {},
        baseCurrency: 'USD',
        marketValueInBase: Decimal.zero,
        costBasisInBase: Decimal.zero,
        unrealizedPnlInBase: Decimal.zero,
        portfolioScoped: true,
        ytdReturn: PortfolioReturnResult(
          from: DateTime.utc(2026),
          to: DateTime.utc(2026, 5, 17),
          baseCurrency: 'USD',
          cashFlows: const [],
          solution: const XirrConverged(rate: 0.12, iterations: 3),
        ),
      );
      final router = GoRouter(
        initialLocation: FinanceRoutes.wealthPortfolio,
        routes: [
          GoRoute(
            path: FinanceRoutes.wealthPortfolio,
            builder: (_, _) => const PortfolioHubPage(),
          ),
          GoRoute(
            path: FinanceRoutes.wealthPortfolioStudioFor(portfolio.id),
            builder: (_, _) =>
                const Scaffold(body: Text('Selected portfolio studio')),
          ),
        ],
      );
      addTearDown(router.dispose);
      final repository = _PlanRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            investmentPortfolioRepositoryProvider.overrideWith(
              (_) async => repository,
            ),
            portfolioHubProvider.overrideWith(
              () => _StaticPortfolioHubNotifier(state),
            ),
            investmentPortfoliosProvider.overrideWith(
              (_) => Stream.value([portfolio, incomePortfolio]),
            ),
            activeRebalanceUniverseProvider.overrideWith((_) => valuationState),
            universeRebalancePlanProvider.overrideWith((_) => valuationPlan),
            portfolioRebalanceGroupsProvider.overrideWith(
              (_) => Stream.value([]),
            ),
            allPortfolioGroupSnapshotsProvider.overrideWith((_) async => {}),
            activeUniversePortfolioTargetsProvider.overrideWithValue(
              AsyncData([
                for (final node in [portfolioNode, incomeNode])
                  PortfolioAllocationTarget(
                    id: node.id,
                    universeId: 'plan',
                    portfolioId: node.referenceId!,
                    targetWeightBps: node.targetWeightBps,
                    driftBandBps: node.driftBandBps,
                    transferPolicy: node.transferPolicy,
                    sync: _meta(),
                  ),
              ]),
            ),
            portfolioHubInsightsProvider.overrideWith(
              _EmptyPortfolioInsightsNotifier.new,
            ),
            portfolioAllocationTreeProvider.overrideWith(
              (_) => AsyncData(
                PortfolioAllocationTree(
                  root: root,
                  nodes: [
                    root,
                    for (final node in [portfolioNode, incomeNode])
                      AllocationNode(
                        id: node.id,
                        parentId: node.parentId,
                        type: node.type,
                        name: node.name,
                        referenceId: node.referenceId,
                        targetWeightBps:
                            repository.saved
                                ?.firstWhere((target) => target.id == node.id)
                                .targetWeightBps ??
                            node.targetWeightBps,
                        driftBandBps: node.driftBandBps,
                        transferPolicy: node.transferPolicy,
                      ),
                  ],
                  attachments: [],
                  inclusions: [],
                ),
              ),
            ),
            portfolioMonthlyTrendSummariesProvider.overrideWith(
              (_) async => {},
            ),
            selectedInvestmentPortfolioIdProvider.overrideWith(
              (_) => portfolio.id,
            ),
            selectedPortfolioConcentrationAlertsProvider.overrideWith(
              (_) async => [],
            ),
          ],
          child: FTheme(
            data: FTheme.neutral.light.touch,
            child: MaterialApp.router(
              theme: AppTheme.light(),
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Manage portfolio'), findsOneWidget);
      expect(
        find.text(AppLocalizationsEn().portfolioHubScopedXirrUnavailable),
        findsOneWidget,
      );
      expect(find.textContaining('12.0%'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PortfolioHubPage)),
      );
      repository.onSaved = () =>
          container.invalidate(portfolioAllocationTreeProvider);
      for (final id in [null, kUnassignedInvestmentPortfolioId]) {
        container.read(selectedInvestmentPortfolioIdProvider.notifier).state =
            id;
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('portfolio-manage')), findsNothing);
      }
      container.read(selectedInvestmentPortfolioIdProvider.notifier).state =
          portfolio.id;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('portfolio-manage')));
      await tester.pumpAndSettle();
      expect(find.text('Selected portfolio studio'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      container.read(selectedInvestmentPortfolioIdProvider.notifier).state =
          null;
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .bySemanticsLabel(AppLocalizationsEn().shellMoreActions)
            .hitTestable()
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(AppLocalizationsEn().portfolioStudioPlanTitle),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppSheet), findsOneWidget);
      expect(
        find.text(AppLocalizationsEn().portfolioStudioPlanTitle),
        findsOneWidget,
      );
      expect(find.text('Actual allocation'), findsNWidgets(2));
      expect(find.text('Target allocation'), findsNWidgets(2));
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Long term')).dy,
        lessThan(tester.getTopLeft(find.text('Income')).dy),
      );
      expect(
        find.descendant(
          of: find.byType(AppSheet),
          matching: find.byType(NwLineChart),
        ),
        findsNothing,
      );
      expect(
        find.text(AppLocalizationsEn().portfolioPlanActualUnavailable),
        findsOneWidget,
      );
      valuationState = const AsyncLoading();
      container.invalidate(activeRebalanceUniverseProvider);
      await tester.pumpAndSettle();
      expect(
        find.text(AppLocalizationsEn().portfolioPlanActualLoading),
        findsOneWidget,
      );
      valuationState = AsyncError(
        StateError('unavailable'),
        StackTrace.current,
      );
      container.invalidate(activeRebalanceUniverseProvider);
      await tester.pumpAndSettle();
      expect(
        find.text(AppLocalizationsEn().portfolioPlanActualFailed),
        findsOneWidget,
      );
      expect(find.text('60%'), findsOneWidget);
      valuationState = const AsyncData(null);
      await tester.tap(find.text(AppLocalizationsEn().commonRetry));
      await tester.pumpAndSettle();
      expect(
        find.text(AppLocalizationsEn().portfolioPlanActualUnavailable),
        findsOneWidget,
      );

      final targets = container
          .read(activeUniversePortfolioTargetsProvider)
          .requireValue;
      final capitalPlan = const CapitalAllocationEngine().compute(
        baseCurrency: 'USD',
        nodes: [
          for (final (index, node) in [portfolioNode, incomeNode].indexed)
            CapitalAllocationNode(
              id: node.referenceId!,
              name: node.name,
              targetWeightBps: node.targetWeightBps,
              driftBandBps: node.driftBandBps,
              transferPolicy: node.transferPolicy,
              actualAmount: Decimal.fromInt(index == 0 ? 70 : 30),
            ),
        ],
      );
      valuationPlan = UniverseRebalancePlan(
        universe: RebalanceUniverse(
          id: 'plan',
          name: 'Plan',
          baseCurrency: 'USD',
          createdAt: DateTime.utc(2026),
          archived: false,
          sync: _meta(),
        ),
        capitalPlan: capitalPlan,
        portfolios: [
          for (final (index, item) in [portfolio, incomePortfolio].indexed)
            PortfolioCapitalPlan(
              portfolio: item,
              target: targets[index],
              capitalDecision: capitalPlan.decisions[item.id]!,
              strategyPlan: PortfolioRebalancePlan(
                totalAssets: Money.fromInt(index == 0 ? 70 : 30, 'USD'),
                groups: [],
                transfers: [],
              ),
            ),
        ],
      );
      container.invalidate(universeRebalancePlanProvider);
      await tester.pumpAndSettle();
      expect(
        find.text(AppLocalizationsEn().portfolioPlanAboveTarget('10')),
        findsOneWidget,
      );
      expect(
        find.text(AppLocalizationsEn().portfolioPlanBelowTarget('10')),
        findsOneWidget,
      );
      expect(
        find.text(AppLocalizationsEn().portfolioPlanActualUnavailable),
        findsNothing,
      );

      final originalScope = container.read(
        selectedInvestmentPortfolioIdProvider,
      );
      for (final action in [
        'portfolio-plan-create',
        'portfolio-plan-allocation',
      ]) {
        await tester.tap(find.byKey(ValueKey(action)));
        await tester.pumpAndSettle();
        expect(
          find.byType(AppSheet),
          action.endsWith('create') ? findsOneWidget : findsNothing,
          reason: 'Editing replaces the overview sheet.',
        );
        expect(
          find.byKey(const ValueKey('portfolio-plan-row-long-term')),
          findsNothing,
        );
        expect(
          find.text(
            action.endsWith('create')
                ? AppLocalizationsEn().portfolioCreateTitle
                : AppLocalizationsEn().portfolioAllocationEditTitle,
          ),
          findsOneWidget,
        );
        if (action.endsWith('create')) {
          await tester.tap(find.text(AppLocalizationsEn().commonCancel));
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(find.byType(AppSheet), findsOneWidget);
        expect(
          find.byKey(const ValueKey('portfolio-plan-row-long-term')),
          findsOneWidget,
          reason: 'The plan resumes automatically after cancelling.',
        );
      }
      await tester.tap(find.byKey(const ValueKey('portfolio-plan-allocation')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, '65');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppLocalizationsEn().unsavedChangesDiscard));
      await tester.pumpAndSettle();
      expect(repository.saved, isNull);
      expect(find.byType(AppSheet), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('portfolio-plan-allocation')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, '65');
      await tester.tap(find.text(AppLocalizationsEn().commonSave));
      await tester.pumpAndSettle();
      expect(repository.saved!.map((target) => target.targetWeightBps), [
        6500,
        3500,
      ]);
      expect(find.byType(AppFormPageScaffold), findsNothing);
      expect(find.byType(AppSheet), findsOneWidget);
      expect(find.text('65%'), findsOneWidget);
      expect(find.text('35%'), findsOneWidget);
      expect(
        container.read(selectedInvestmentPortfolioIdProvider),
        originalScope,
      );
      await tester.tap(find.text('Long term'));
      await tester.pumpAndSettle();
      expect(find.text('Selected portfolio studio'), findsOneWidget);
      expect(find.byType(AppSheet), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'portfolio studio keeps setup sections visible as explicit navigation',
    (tester) async {
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
      final tree = PortfolioAllocationTree(
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
            portfolioAllocationTreeProvider.overrideWithValue(AsyncData(tree)),
            portfolioTrendProvider(
              const PortfolioTrendRequest(
                portfolioId: 'portfolio',
                range: PortfolioTrendRange.month,
              ),
            ).overrideWith((ref) async => null),
          ],
          child: FTheme(
            data: FTheme.neutral.light.desktop,
            child: MaterialApp(
              theme: AppTheme.light(),
              builder: (context, child) => AppMessenger.init(child: child!),
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
      expect(find.text('Capital path'), findsOneWidget);
      expect(find.text('Index core'), findsOneWidget);
      expect(find.text('Check rebalance'), findsNothing);
      expect(find.text('Structure'), findsOneWidget);
      expect(find.text('Assets'), findsOneWidget);
      expect(find.text('Overview'), findsOneWidget);

      await tester.tap(find.text('Structure'));
      await tester.pumpAndSettle();
      expect(find.text('Strategy sleeves'), findsOneWidget);
      expect(
        find.text(AppLocalizationsEn().portfolioStudioConfiguredStatus),
        findsNothing,
      );
      expect(find.text('Index core'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('app.back')));
      await tester.pumpAndSettle();
      expect(find.text('Capital path'), findsOneWidget);
      expect(find.byType(PortfolioStudioPage), findsOneWidget);

      await tester.tap(find.text('Structure'));
      await tester.pumpAndSettle();
      expect(find.text('Strategy sleeves'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Capital path'), findsOneWidget);
      expect(find.byType(PortfolioStudioPage), findsOneWidget);
    },
  );

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
    final tree = PortfolioAllocationTree(
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
          portfolioAllocationTreeProvider.overrideWithValue(AsyncData(tree)),
          portfolioTrendProvider(
            const PortfolioTrendRequest(
              portfolioId: 'portfolio',
              range: PortfolioTrendRange.month,
            ),
          ).overrideWith((ref) async => trend),
        ],
        child: FTheme(
          data: FTheme.neutral.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => AppMessenger.init(child: child!),
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
          data: FTheme.neutral.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => AppMessenger.init(child: child!),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const PortfolioStudioPage(
              portfolioId: 'portfolio',
              initialSection: PortfolioStudioSection.assets,
              transferIntent: CapitalTransferIntent(
                fromPortfolioId: 'portfolio',
                toPortfolioId: 'portfolio',
                amount: '250',
                currency: 'USD',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Asset targets'), findsOneWidget);
    expect(find.text('Current transfer task'), findsOneWidget);
    expect(find.textContaining(r'$250.00'), findsOneWidget);
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
          data: FTheme.neutral.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => AppMessenger.init(child: child!),
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

  testWidgets(
    'portfolio hub keeps state, portfolios, and holdings in one flow',
    (tester) async {
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
          for (var index = 1; index < 8; index++)
            _holding(
              assetId: 'us:ASSET$index',
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
            portfolioHubInsightsProvider.overrideWith(
              _EmptyPortfolioInsightsNotifier.new,
            ),
          ],
          child: FTheme(
            data: FTheme.neutral.light.desktop,
            child: MaterialApp(
              theme: AppTheme.light(),
              builder: (context, child) => AppMessenger.init(child: child!),
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
      expect(find.byType(AdaptiveSummaryGrid), findsOneWidget);
      expect(find.byType(AppAdaptiveSelectionMenu<String>), findsOneWidget);
      expect(find.byType(FSelect<String>), findsNothing);
      expect(find.bySemanticsLabel('Portfolio: All holdings'), findsOneWidget);
      expect(find.text('All holdings'), findsOneWidget);
      // Positions use a virtualized DecoratedSliver group surface.
      expect(find.byType(DecoratedSliver), findsOneWidget);
      expect(find.text('us:AAPL'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('us:ASSET7'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('us:ASSET7'), findsOneWidget);
      expect(find.text('Cost basis'), findsOneWidget);
      // No concentration breaches → review surface stays hidden.
      expect(find.text('Concentration risk'), findsNothing);
      expect(find.text('Returns & events'), findsOneWidget);
      expect(find.byType(AppDisclosureHeader), findsNothing);
      expect(find.byType(AppRevealControl), findsNothing);
      expect(find.text('Allocation'), findsNothing);
    },
  );

  testWidgets('portfolio flow shows concentration breaches contextually', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
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
          portfolioHubInsightsProvider.overrideWith(
            _EmptyPortfolioInsightsNotifier.new,
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
              ConcentrationAlert(
                dimension: RiskDimension.currency,
                severity: RiskSeverity.warning,
                label: 'EUR',
                weight: 0.25,
                threshold: 0.20,
                valueInBase: _d('25'),
                assetIds: const [],
              ),
            ],
          ),
        ],
        child: FTheme(
          data: FTheme.neutral.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => AppMessenger.init(child: child!),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const PortfolioHubPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Concentration risk'), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.textContaining('42.0%'), findsOneWidget);
    expect(find.text('Check rebalance'), findsOneWidget);
    expect(find.text('EUR'), findsNothing);
    expect(tester.getTopLeft(find.text('us:AAPL').first).dy, lessThan(760));
    final holdingPosition = tester.getTopLeft(find.text('us:AAPL').first);
    await tester.tap(find.byKey(const ValueKey('portfolio-risk-details')));
    await tester.pumpAndSettle();
    expect(find.byType(AppSheet), findsOneWidget);
    expect(find.text('EUR'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('portfolio-detail-close')));
    await tester.pumpAndSettle();
    expect(find.text('EUR'), findsNothing);
    expect(tester.getTopLeft(find.text('us:AAPL').first), holdingPosition);
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

class _EmptyPortfolioInsightsNotifier extends PortfolioHubInsightsNotifier {
  @override
  Future<PortfolioHubInsightsState> fetch() async => PortfolioHubInsightsState(
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
