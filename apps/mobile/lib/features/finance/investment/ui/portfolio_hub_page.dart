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
import '../../rebalance/domain/rebalance_universe.dart';
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

part 'portfolio_hub_engine_cards.dart';
part 'portfolio_hub_group_detail.dart';
part 'portfolio_hub_state.dart';
part 'portfolio_hub_widgets.dart';
part 'portfolio_studio_overview.dart';
part 'portfolio_studio_page.dart';

class PortfolioHubPage extends ConsumerStatefulWidget {
  const PortfolioHubPage({super.key});

  @override
  ConsumerState<PortfolioHubPage> createState() => _PortfolioHubPageState();
}

class _PortfolioHubPageState extends ConsumerState<PortfolioHubPage> {
  PortfolioHubView _view = PortfolioHubView.account;
  _PortfolioSection _section = _PortfolioSection.positions;

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

    return AppPageScaffold(
      title: l10n.portfolioHubTitle,
      actions: [
        AppHeaderAction(
          semanticsLabel: l10n.portfolioStudioRebalanceAction,
          icon: const Icon(FLucideIcons.scale),
          onPress: () => context.push(FinanceRoutes.planRebalance),
        ),
        AppHeaderAction(
          semanticsLabel: l10n.tradeEntryAppBarTitle,
          icon: const Icon(FLucideIcons.plus),
          onPress: () => context.push(FinanceRoutes.tradeEntry),
        ),
        AppAdaptiveActionMenu(
          title: l10n.shellMoreActions,
          actions: [
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
          view: _view,
          section: _section,
          portfolios: portfolios,
          allocationTree: allocationTree,
          actualPortfolioWeights: actualPortfolioWeights,
          selectedPortfolioId: selectedPortfolioId,
          onPortfolioChanged: (id) {
            ref.read(selectedInvestmentPortfolioIdProvider.notifier).state = id;
          },
          onViewChanged: (next) => setState(() => _view = next),
          onSectionChanged: (next) => setState(() => _section = next),
        ),
      ),
    );
  }
}

class _PortfolioHubBody extends StatefulWidget {
  const _PortfolioHubBody({
    required this.data,
    required this.view,
    required this.section,
    required this.onViewChanged,
    required this.onSectionChanged,
    required this.portfolios,
    required this.allocationTree,
    required this.actualPortfolioWeights,
    required this.selectedPortfolioId,
    required this.onPortfolioChanged,
  });

  final PortfolioHubState data;
  final PortfolioHubView view;
  final _PortfolioSection section;
  final ValueChanged<PortfolioHubView> onViewChanged;
  final ValueChanged<_PortfolioSection> onSectionChanged;
  final List<InvestmentPortfolio> portfolios;
  final PortfolioAllocationTree? allocationTree;
  final Map<String, double> actualPortfolioWeights;
  final String? selectedPortfolioId;
  final ValueChanged<String?> onPortfolioChanged;

  @override
  State<_PortfolioHubBody> createState() => _PortfolioHubBodyState();
}

class _PortfolioHubBodyState extends State<_PortfolioHubBody> {
  bool _showAllPositions = false;

  // First-frame entrance stagger (doc 11 §5) — first-paint rows cascade in;
  // later builds (reveal-more, data ticks) appear instantly.
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
    final groups = data.groupsFor(widget.view, l10n);
    const previewCount = 6;
    final holdings = data.holdings;
    final previewHoldings = holdings.take(previewCount).toList(growable: false);
    final overflowHoldings = holdings.length > previewCount
        ? holdings.skip(previewCount).toList(growable: false)
        : const <PortfolioHoldingRow>[];

    final visibleHoldings = _showAllPositions ? holdings : previewHoldings;
    final showReveal = overflowHoldings.isNotEmpty;

    return AdaptiveContentFrame(
      maxWidth: AdaptiveMaxWidth.page,
      expandSinglePrimary: true,
      padding: shellTabContentPadding(
        context,
        left: AppSpacing.s16,
        top: AppSpacing.s0,
        right: AppSpacing.s16,
        bottom: AppSpacing.s16,
      ),
      primary: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.allocationTree case final tree?) ...[
                  _PortfolioPlanStrip(
                    portfolios: widget.portfolios,
                    tree: tree,
                    actualWeights: widget.actualPortfolioWeights,
                  ),
                  const SizedBox(height: AppSpacing.s16),
                ],
                _PortfolioSelector(
                  portfolios: widget.portfolios,
                  value: widget.selectedPortfolioId,
                  holdingCount: data.holdings.length,
                  onChanged: widget.onPortfolioChanged,
                ),
                const SizedBox(height: AppSpacing.s12),
                _PortfolioSummary(data: data),
                const SizedBox(height: AppSpacing.s16),
                _PortfolioSectionSegment(
                  value: widget.section,
                  onChanged: widget.onSectionChanged,
                ),
                const SizedBox(height: AppSpacing.s16),
              ],
            ),
          ),
          ...switch (widget.section) {
            _PortfolioSection.positions => [
              _positionsSliver(
                l10n: l10n,
                holdings: visibleHoldings,
                empty: holdings.isEmpty,
                showReveal: showReveal,
                overflowCount: overflowHoldings.length,
              ),
            ],
            _PortfolioSection.allocation => [
              _allocationSliver(l10n: l10n, groups: groups),
            ],
            _PortfolioSection.insights => [
              SliverToBoxAdapter(
                child: _EngineExposureSection(baseCurrency: data.baseCurrency),
              ),
            ],
          },
        ],
      ),
    );
  }

  Widget _positionsSliver({
    required AppLocalizations l10n,
    required List<PortfolioHoldingRow> holdings,
    required bool empty,
    required bool showReveal,
    required int overflowCount,
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

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _PortfolioSectionTitle(title: l10n.portfolioHubPositionsTitle),
        ),
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
              final row = _HoldingRow(holding: holdings[index]);
              if (_entranceStagger && index < _kStaggerRowCap) {
                return FadeSlideIn(
                  delay: Duration(milliseconds: 30 * index),
                  child: row,
                );
              }
              return row;
            },
          ),
        ),
        if (showReveal)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s8),
              child: AppRevealControl(
                expanded: _showAllPositions,
                collapsedLabel: l10n.commonRevealMore(overflowCount),
                expandedLabel: l10n.commonRevealLess,
                onToggle: () =>
                    setState(() => _showAllPositions = !_showAllPositions),
              ),
            ),
          ),
      ],
    );
  }

  Widget _allocationSliver({
    required AppLocalizations l10n,
    required List<PortfolioGroupRow> groups,
  }) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ConcentrationRiskSection(),
          PortfolioHubViewSegment(
            value: widget.view,
            onChanged: widget.onViewChanged,
          ),
          const SizedBox(height: AppSpacing.s12),
          if (groups.isEmpty)
            _EmptyState(message: l10n.portfolioHubEmpty)
          else
            AppGroupedSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < groups.length; i++) ...[
                    _GroupRow(
                      group: groups[i],
                      onPressed: () => _showPortfolioGroupDetail(
                        context: context,
                        group: groups[i],
                      ),
                    ),
                    if (i != groups.length - 1)
                      const AppGroupedDivider(
                        indent: AppSpacing.s12,
                        endIndent: AppSpacing.s12,
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
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
        triggerBuilder: (context, openMenu, focusNode) {
          final colors = context.theme.colors;
          return Focus(
            focusNode: focusNode,
            child: Semantics(
              button: true,
              label: '${l10n.portfolioHubTitle}: $selectedLabel',
              child: AppTappable(
                onPress: openMenu,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppSpacing.s48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4,
                      vertical: AppSpacing.s4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.titleLabelStyle.copyWith(
                                  color: colors.foreground,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s2),
                              Text(
                                holdingSummary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.captionStyle,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Icon(
                          FLucideIcons.chevronsUpDown,
                          size: AppIconSizes.sm,
                          color: colors.mutedForeground,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _PortfolioSection { positions, allocation, insights }

class _PortfolioSectionSegment extends StatelessWidget {
  const _PortfolioSectionSegment({
    required this.value,
    required this.onChanged,
  });

  final _PortfolioSection value;
  final ValueChanged<_PortfolioSection> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SegmentedRow<_PortfolioSection>(
      options: _PortfolioSection.values,
      value: value,
      labelOf: (section) => switch (section) {
        _PortfolioSection.positions => l10n.portfolioHubSectionPositions,
        _PortfolioSection.allocation => l10n.portfolioHubSectionAllocation,
        _PortfolioSection.insights => l10n.portfolioHubSectionInsights,
      },
      onChanged: (next) {
        AppInteraction.signal(AppInteractionIntent.select);
        onChanged(next);
      },
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
      padding: AppPageRhythm.heroPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.portfolioHubMarketValueLabel,
            style: context.mutedLabelStyle,
          ),
          const SizedBox(height: AppSpacing.s8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AnimatedMoneyText(
                  amount: slice.marketValueInBase.toDouble(),
                  currencyCode: slice.baseCurrency,
                  style: TypographyTokens.displaySmall,
                  color: context.theme.colors.foreground,
                ),
              ),
              DeltaChip(value: pnlPercent, fractionDigits: 2),
            ],
          ),
          const SizedBox(height: AppSpacing.s14),
          _PortfolioSummaryMetrics(slice: slice, xirr: xirr),
        ],
      ),
    );
  }
}

class _PortfolioSummaryMetrics extends StatelessWidget {
  const _PortfolioSummaryMetrics({required this.slice, required this.xirr});

  final PortfolioHubSummarySlice slice;
  final double? xirr;

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
      _SummaryMetric(
        label: l10n.portfolioHubYtdXirrLabel,
        value: xirr == null ? '—' : _formatRatio(context, xirr!),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (Breakpoints.isMobile(constraints.maxWidth)) {
          final itemWidth = (constraints.maxWidth - AppSpacing.s12) / 2;
          return Wrap(
            spacing: AppSpacing.s12,
            runSpacing: AppSpacing.s14,
            children: [
              for (final metric in metrics)
                SizedBox(width: itemWidth, child: metric),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: metrics[0]),
            const SizedBox(width: AppSpacing.s12),
            Expanded(child: metrics[1]),
            const SizedBox(width: AppSpacing.s12),
            Expanded(child: metrics[2]),
          ],
        );
      },
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value})
    : amount = null,
      currency = null,
      showSign = false;

  const _SummaryMetric.money({
    required this.label,
    required double this.amount,
    required String this.currency,
    this.showSign = false,
  }) : value = null;

  final String label;
  final String? value;
  final double? amount;
  final String? currency;
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
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.captionStyle,
            ),
            const SizedBox(height: AppSpacing.s4),
            if (amount == null)
              Text(value ?? '—', style: context.theme.typography.body.lg)
            else
              AnimatedMoneyText(
                amount: amount,
                currencyCode: currency!,
                showSign: showSign,
                style: context.strongTitleStyle,
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
