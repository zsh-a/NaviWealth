import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:naviwealth/core/async/async_notifier_convention.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/analytics/data/providers.dart';
import 'package:naviwealth/features/finance/analytics/domain/concentration_risk.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_center_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_forecast_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/home/ui/asset_category_visuals.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../rebalance/data/rebalance_providers.dart';
import '../../rebalance/domain/portfolio_rebalance_group.dart';
import '../data/investment_portfolio_providers.dart';
import '../data/portfolio_trend_providers.dart';
import '../data/providers.dart';
import '../domain/allocation/portfolio_allocation_tree.dart';
import '../domain/dividend_forecast.dart';
import '../domain/models/corporate_actions.dart';
import '../domain/models/holding_snapshot.dart';
import '../domain/models/investment_portfolio.dart';
import '../domain/models/lot.dart';
import '../domain/models/portfolio_capital_assignment.dart';
import '../domain/models/realized_pnl.dart';
import '../domain/portfolio_trend.dart';
import '../domain/returns/portfolio_return.dart';
import '../domain/strategy/portfolio_strategy_template.dart';
import 'investment_portfolio_sheets.dart';
import 'portfolio_allocation_sheets.dart';
import 'portfolio_group_sheets.dart';
import 'portfolio_strategy_visuals.dart';
import 'portfolio_studio_projection.dart';

export 'investment_portfolio_sheets.dart'
    show PortfolioCashAssignmentPage, PortfolioLotAssignmentPage;

part 'portfolio_hub_engine_cards.dart';
part 'portfolio_hub_state.dart';
part 'portfolio_hub_widgets.dart';
part 'portfolio_studio_assets.dart';
part 'portfolio_studio_overview.dart';
part 'portfolio_studio_page.dart';
part 'portfolio_studio_plan.dart';
part 'portfolio_studio_strategy.dart';

class PortfolioHubPage extends ConsumerStatefulWidget {
  const PortfolioHubPage({super.key});

  @override
  ConsumerState<PortfolioHubPage> createState() => _PortfolioHubPageState();
}

class _PortfolioHubPageState extends ConsumerState<PortfolioHubPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(portfolioHubCoreProvider);
    final portfolios =
        ref.watch(investmentPortfoliosProvider).value ?? const [];
    final allocationTree = ref.watch(portfolioAllocationTreeProvider).value;
    final universePlan = ref.watch(universeRebalancePlanProvider);
    final actualPortfolioWeights = universePlan == null
        ? const <String, double>{}
        : <String, double>{
            for (final item in universePlan.portfolios)
              item.portfolio.id: item.capitalDecision.actualWeight,
          };
    final selectedPortfolioId = ref.watch(
      effectiveSelectedInvestmentPortfolioIdProvider,
    );
    final needsRebalance =
        allocationTree != null &&
        allocationTree.childrenOf(allocationTree.root.id).any((node) {
          final actual = actualPortfolioWeights[node.referenceId];
          if (actual == null) return false;
          return (actual - node.targetWeight).abs() > node.driftBandBps / 10000;
        });

    return AppPageScaffold(
      title: l10n.portfolioHubTitle,
      actions: [
        AppHeaderAction(
          semanticsLabel: l10n.tradeEntryAppBarTitle,
          icon: const Icon(FLucideIcons.plus),
          onPress: () => context.push(FinanceRoutes.tradeEntry),
        ),
        AppAdaptiveActionMenu(
          title: l10n.shellMoreActions,
          actions: [
            if (needsRebalance)
              AppAdaptiveAction(
                icon: FLucideIcons.triangleAlert,
                title: l10n.portfolioStudioRebalanceAction,
                onPress: () => context.push(FinanceRoutes.planRebalance),
              ),
            AppAdaptiveAction(
              icon: FLucideIcons.plus,
              title: l10n.portfolioCreateTitle,
              onPress: () => showInvestmentPortfolioFormSheet(context),
            ),
            AppAdaptiveAction(
              icon: FLucideIcons.bellRing,
              title: l10n.wealthWatchlistSectionTitle,
              onPress: () => context.push(FinanceRoutes.wealthWatchlist),
            ),
            AppAdaptiveAction(
              icon: FLucideIcons.refreshCw,
              title: l10n.commonRefresh,
              onPress: () {
                ref.read(portfolioHubCoreProvider.notifier).refresh();
                ref.read(portfolioHubInsightsProvider.notifier).refresh();
              },
            ),
          ],
          triggerBuilder: (context, openMenu, focusNode) => AppHeaderAction(
            semanticsLabel: l10n.shellMoreActions,
            icon: const Icon(FLucideIcons.ellipsis),
            focusNode: focusNode,
            onPress: openMenu,
          ),
        ),
      ],
      childPad: false,
      child: state.when(
        skipLoadingOnReload: true,
        loading: () => const _PortfolioHubSkeleton(),
        error: (error, stackTrace) => kDefaultError(
          context,
          error,
          stackTrace,
          onRetry: () {
            ref.read(portfolioHubCoreProvider.notifier).refresh();
            ref.read(portfolioHubInsightsProvider.notifier).refresh();
          },
        ),
        data: (data) => _PortfolioHubBody(
          data: data,
          portfolios: portfolios,
          allocationTree: allocationTree,
          needsRebalance: needsRebalance,
          selectedPortfolioId: selectedPortfolioId,
          onPortfolioChanged: (id) {
            ref.read(selectedInvestmentPortfolioIdProvider.notifier).state = id;
          },
          onOpenPlan: () => context.push(FinanceRoutes.wealthPortfolioPlan),
        ),
      ),
    );
  }
}

class _PortfolioHubBody extends StatefulWidget {
  const _PortfolioHubBody({
    required this.data,
    required this.portfolios,
    required this.allocationTree,
    required this.needsRebalance,
    required this.selectedPortfolioId,
    required this.onPortfolioChanged,
    required this.onOpenPlan,
  });

  final PortfolioHubState data;
  final List<InvestmentPortfolio> portfolios;
  final PortfolioAllocationTree? allocationTree;
  final bool needsRebalance;
  final String? selectedPortfolioId;
  final ValueChanged<String?> onPortfolioChanged;
  final VoidCallback onOpenPlan;

  @override
  State<_PortfolioHubBody> createState() => _PortfolioHubBodyState();
}

class _PortfolioHubBodyState extends State<_PortfolioHubBody> {
  // First-frame entrance stagger (doc 11 §5) — first-paint rows cascade in;
  // later builds (data ticks) appear instantly.
  bool _entranceStagger = true;
  static const int _kStaggerRowCap = 8;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entranceStagger = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = widget.data;
    final holdings = data.holdings;

    final padding = shellTabContentPadding(
      context,
      left: AppSpacing.s16,
      top: AppSpacing.s0,
      right: AppSpacing.s16,
      bottom: AppSpacing.s16,
    );

    return AdaptiveContentFrame(
      maxWidth: AdaptiveMaxWidth.dashboard,
      expandSinglePrimary: true,
      padding: padding,
      primary: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: _PortfolioScopeBar(
                portfolios: widget.portfolios,
                value: widget.selectedPortfolioId,
                holdingCount: data.holdings.length,
                onOpenPlan: widget.allocationTree == null
                    ? null
                    : widget.onOpenPlan,
                needsRebalance: widget.needsRebalance,
                onChanged: widget.onPortfolioChanged,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s16),
              child: _PortfolioOverview(data: data),
            ),
          ),
          _positionsSliver(
            l10n: l10n,
            holdings: holdings,
            empty: holdings.isEmpty,
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: AppSpacing.s16),
              child: _PortfolioInsightsSection(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _positionsSliver({
    required AppLocalizations l10n,
    required List<PortfolioHoldingRow> holdings,
    required bool empty,
  }) {
    if (empty) {
      return SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PortfolioSectionTitle(title: l10n.portfolioHubPositionsTitle),
            _EmptyState(message: l10n.portfolioHubEmpty),
          ],
        ),
      );
    }

    // Visual chrome matches [AppGroupedSurface] via DecoratedSliver so rows
    // stay virtualized inside one continuous group surface.
    final surfaceColor = appGroupedSurfaceFill(context);

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final tabular = _usePortfolioTable(
          context,
          constraints.crossAxisExtent,
        );
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: _PortfolioSectionTitle(
                title: l10n.portfolioHubPositionsTitle,
              ),
            ),
            if (tabular) const SliverToBoxAdapter(child: _HoldingTableHeader()),
            DecoratedSliver(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              sliver: SliverList.separated(
                itemCount: holdings.length,
                separatorBuilder: (_, _) => const AppGroupedDivider(
                  indent: AppSpacing.s12,
                  endIndent: AppSpacing.s12,
                ),
                itemBuilder: (context, index) {
                  final row = _HoldingRow(
                    key: ValueKey(holdings[index].assetId),
                    holding: holdings[index],
                    tabular: tabular,
                  );
                  if (_entranceStagger && index < _kStaggerRowCap) {
                    return FadeSlideIn(
                      delay: Motion.staggerDelayFor(index, _kStaggerRowCap),
                      child: row,
                    );
                  }
                  return row;
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PortfolioScopeBar extends StatelessWidget {
  const _PortfolioScopeBar({
    required this.portfolios,
    required this.value,
    required this.holdingCount,
    required this.onChanged,
    required this.onOpenPlan,
    required this.needsRebalance,
  });

  final List<InvestmentPortfolio> portfolios;
  final String? value;
  final int holdingCount;
  final ValueChanged<String?> onChanged;
  final VoidCallback? onOpenPlan;
  final bool needsRebalance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selector = _PortfolioSelector(
      portfolios: portfolios,
      value: value,
      holdingCount: holdingCount,
      onChanged: onChanged,
    );
    final actions = [
      if (onOpenPlan != null)
        FButton(
          key: const ValueKey('portfolio-plan-action'),
          mainAxisSize: MainAxisSize.min,
          variant: FButtonVariant.ghost,
          onPress: onOpenPlan,
          prefix: Icon(
            needsRebalance ? FLucideIcons.triangleAlert : FLucideIcons.layers3,
            size: AppIconSizes.sm,
          ),
          child: Flexible(child: Text(l10n.portfolioStudioPlanTitle)),
        ),
      if (portfolios.any((portfolio) => portfolio.id == value))
        AppIconButton(
          key: const ValueKey('portfolio-manage'),
          icon: FLucideIcons.settings2,
          tooltip: l10n.portfolioHubManageAction,
          onPress: () =>
              context.push(FinanceRoutes.wealthPortfolioStudioFor(value!)),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              selector,
              Wrap(spacing: AppSpacing.s8, children: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: selector),
            const SizedBox(width: AppSpacing.s8),
            ...actions,
          ],
        );
      },
    );
  }
}

class _PortfolioOverview extends ConsumerWidget {
  const _PortfolioOverview({required this.data});

  final PortfolioHubState data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final risk = ref.watch(selectedPortfolioConcentrationAlertsProvider);
    // Do not retain another portfolio's alerts while this scope is loading.
    final alerts = risk.isLoading ? null : risk.value;
    final hasRisk = alerts != null && alerts.isNotEmpty;
    return AdaptiveSummaryGrid(
      gap: AppSpacing.s12,
      items: [
        AdaptiveSummaryTile(
          role: hasRisk
              ? AdaptiveSummaryTileRole.featured
              : AdaptiveSummaryTileRole.continuous,
          child: _PortfolioSummary(data: data),
        ),
        if (hasRisk)
          AdaptiveSummaryTile(
            role: AdaptiveSummaryTileRole.supporting,
            child: _ConcentrationRiskSection(alerts: alerts),
          ),
      ],
    );
  }
}

class _PortfolioSelector extends StatelessWidget {
  const _PortfolioSelector({
    required this.portfolios,
    required this.value,
    required this.holdingCount,
    required this.onChanged,
  });

  final List<InvestmentPortfolio> portfolios;
  final String? value;
  final int holdingCount;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = {
      for (final portfolio in portfolios) portfolio.id: portfolio.name,
      kUnassignedInvestmentPortfolioId: l10n.portfolioUnassigned,
    };
    final selectedValue = value ?? '';
    final selectedLabel = selectedValue.isEmpty
        ? l10n.portfolioAllHoldings
        : labels[selectedValue] ?? l10n.portfolioAllHoldings;
    final holdingSummary = l10n.portfolioHubHoldingCount(holdingCount);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: AppAdaptiveSelectionMenu<String>(
        title: l10n.portfolioHubTitle,
        subtitle: holdingSummary,
        value: selectedValue,
        onChanged: (id) {
          AppInteraction.signal(AppInteractionIntent.select);
          onChanged(id.isEmpty ? null : id);
        },
        options: [
          AppAdaptiveSelection<String>(
            value: '',
            title: l10n.portfolioAllHoldings,
            icon: FLucideIcons.layers,
          ),
          for (final portfolio in portfolios)
            AppAdaptiveSelection<String>(
              value: portfolio.id,
              title: portfolio.name,
              icon: FLucideIcons.briefcaseBusiness,
            ),
          AppAdaptiveSelection<String>(
            value: kUnassignedInvestmentPortfolioId,
            title: l10n.portfolioUnassigned,
            icon: FLucideIcons.circle,
          ),
        ],
        triggerBuilder: (context, openMenu, focusNode) => Focus(
          focusNode: focusNode,
          child: AppTappable(
            onPress: openMenu,
            semanticsLabel:
                '${l10n.portfolioHubTitle}: $selectedLabel · $holdingSummary',
            excludeSemantics: true,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSpacing.s48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        selectedLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.labelStyle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Icon(
                      FLucideIcons.chevronDown,
                      size: AppIconSizes.sm,
                      color: context.theme.colors.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PortfolioSectionTitle extends StatelessWidget {
  const _PortfolioSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s2,
        AppSpacing.s4,
        AppSpacing.s2,
        AppSpacing.s10,
      ),
      child: Text(title, style: context.bodyCaptionStrongStyle),
    );
  }
}

class _PortfolioSummary extends StatelessWidget {
  const _PortfolioSummary({required this.data});

  final PortfolioHubState data;

  @override
  Widget build(BuildContext context) {
    return _PortfolioSummaryCard(
      slice: PortfolioHubSummarySlice.fromState(data),
    );
  }
}

class _PortfolioSummaryCard extends StatelessWidget {
  const _PortfolioSummaryCard({required this.slice});

  final PortfolioHubSummarySlice slice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final xirr = slice.xirrRatio;
    final pnlPercent = slice.costBasisInBase.sign <= 0
        ? null
        : (slice.unrealizedPnlInBase / slice.costBasisInBase).toDouble() * 100;
    return SoftCard.hero(
      padding: AppPageRhythm.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.s16,
            runSpacing: AppSpacing.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.portfolioHubMarketValueLabel,
                style: context.mutedLabelStyle,
              ),
              if (!slice.portfolioScoped)
                Text(
                  '${l10n.portfolioHubYtdXirrLabel} ${xirr == null ? '—' : _formatRatio(context, xirr)}',
                  style: context.captionStyle,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          LayoutBuilder(
            builder: (context, constraints) {
              final amount = AnimatedMoneyText(
                amount: slice.marketValueInBase.toDouble(),
                currencyCode: slice.baseCurrency,
                style: TypographyTokens.displaySmall,
                color: context.theme.colors.foreground,
              );
              final change = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.portfolioHubHoldingReturnLabel,
                    style: context.captionStyle,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  DeltaChip(value: pnlPercent, fractionDigits: 2),
                ],
              );
              if (constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    amount,
                    const SizedBox(height: AppSpacing.s8),
                    change,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: amount),
                  const SizedBox(width: AppSpacing.s12),
                  change,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.s14),
          _PortfolioSummaryMetrics(slice: slice),
          if (slice.portfolioScoped) ...[
            const SizedBox(height: AppSpacing.s10),
            Text(
              l10n.portfolioHubScopedXirrUnavailable,
              style: context.captionStyle,
            ),
          ],
        ],
      ),
    );
  }
}

class _PortfolioSummaryMetrics extends StatelessWidget {
  const _PortfolioSummaryMetrics({required this.slice});

  final PortfolioHubSummarySlice slice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final metrics = <Widget>[
      _SummaryMetric.money(
        label: l10n.portfolioHubCostBasisLabel,
        amount: slice.costBasisInBase.toDouble(),
        currency: slice.baseCurrency,
      ),
      _SummaryMetric.money(
        label: l10n.portfolioHubAbsoluteReturnLabel,
        amount: slice.unrealizedPnlInBase.toDouble(),
        currency: slice.baseCurrency,
        showSign: true,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (Breakpoints.isMobile(constraints.maxWidth)) {
          final columns = MediaQuery.textScalerOf(context).scale(1) > 1.5
              ? 1
              : 2;
          final itemWidth =
              (constraints.maxWidth - AppSpacing.s8 * (columns - 1)) / columns;
          return Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s14,
            children: [
              for (final metric in metrics)
                SizedBox(width: itemWidth, child: metric),
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < metrics.length; index++) ...[
              if (index > 0) const SizedBox(width: AppSpacing.s12),
              Expanded(child: metrics[index]),
            ],
          ],
        );
      },
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric.money({
    required this.label,
    required this.amount,
    required this.currency,
    this.showSign = false,
  });

  final String label;
  final double amount;
  final String currency;
  final bool showSign;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.theme.colors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.s10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.captionStyle),
            const SizedBox(height: AppSpacing.s4),
            AnimatedMoneyText(
              amount: amount,
              currencyCode: currency,
              showSign: showSign,
              style: context.labelStyle,
            ),
          ],
        ),
      ),
    );
  }
}

String _formatRatio(BuildContext context, double value) {
  if (value.isNaN || value.isInfinite) return '—';
  final locale = Localizations.localeOf(context).toLanguageTag();
  final digits = math.max(1, value.abs() < 0.1 ? 2 : 1);
  final format = NumberFormat.percentPattern(locale)
    ..minimumFractionDigits = digits
    ..maximumFractionDigits = digits;
  return format.format(value);
}

String _holdingSubtitle(AppLocalizations l10n, PortfolioHoldingRow holding) {
  return [
    holding.assetTypeLabel(l10n),
    if (holding.subtitle.isNotEmpty) holding.subtitle,
    holding.assetCurrency,
  ].join(' · ');
}

int _quantityDigits(Decimal quantity) {
  if (quantity == quantity.round()) return 0;
  final abs = quantity.abs().toDouble();
  if (abs == 0) return 0;
  if (abs < 1) return 4;
  if (abs < 100) return 2;
  return 1;
}

String _assetCode(String assetId) {
  final colon = assetId.indexOf(':');
  return colon < 0 ? assetId : assetId.substring(colon + 1);
}

String _formatHoldingPeriod(BuildContext context, Duration duration) {
  final l10n = AppLocalizations.of(context);
  final days = duration.inDays.abs();
  if (days >= 365) {
    final years = (days / 365).floor();
    return l10n.portfolioHubHoldingYears(years);
  }
  if (days >= 30) {
    final months = (days / 30).floor();
    return l10n.portfolioHubHoldingMonths(months);
  }
  return l10n.portfolioHubHoldingDays(days);
}

String _strategyLabel(AppLocalizations l10n, String strategy) {
  return switch (strategy) {
    'declared' => l10n.dividendForecastStrategyDeclared,
    'dps' => l10n.dividendForecastStrategyDps,
    'ttm' => l10n.dividendForecastStrategyTtm,
    'composite' => l10n.dividendForecastStrategyComposite,
    _ => l10n.dividendForecastStrategyUnknown,
  };
}

String _confidenceLabel(
  AppLocalizations l10n,
  DividendForecastConfidence confidence,
) {
  return switch (confidence) {
    DividendForecastConfidence.high => l10n.portfolioHubForecastConfidenceHigh,
    DividendForecastConfidence.medium =>
      l10n.portfolioHubForecastConfidenceMedium,
    DividendForecastConfidence.low => l10n.portfolioHubForecastConfidenceLow,
  };
}

String _corporateActionLabel(AppLocalizations l10n, CorporateAction action) {
  return switch (action) {
    CashDividendAction() => l10n.corpActionTypeCashDividend,
    StockDividendAction() => l10n.corpActionTypeStockDividend,
    SplitAction() => l10n.corpActionTypeSplit,
    RightsIssueAction() => l10n.corpActionTypeRightsIssue,
    DripAction() => l10n.corpActionTypeDrip,
  };
}

String _corporateActionDetail(
  AppFormatters formatters,
  CorporateAction action,
) {
  return switch (action) {
    CashDividendAction a => formatters.currency(
      a.amountPerShare,
      code: a.currency,
    ),
    StockDividendAction a => formatters.signedPercent(a.bonusRatio.toDouble()),
    SplitAction a => 'x${a.ratio}',
    RightsIssueAction a => formatters.signedMoney(
      a.subscribedQuantity,
      unit: a.assetId,
    ),
    DripAction a => formatters.currency(a.amountPerShare, code: a.currency),
  };
}
