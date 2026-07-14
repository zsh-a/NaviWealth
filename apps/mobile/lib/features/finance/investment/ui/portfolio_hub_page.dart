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
import 'package:naviwealth/core/haptics/haptics.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_center_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/dividend_forecast_providers.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/providers.dart';
import '../domain/dividend_forecast.dart';
import '../domain/models/corporate_actions.dart';
import '../domain/models/holding_snapshot.dart';
import '../domain/models/lot.dart';
import '../domain/models/realized_pnl.dart';
import '../domain/returns/portfolio_return.dart';

part 'portfolio_hub_engine_cards.dart';
part 'portfolio_hub_group_detail.dart';
part 'portfolio_hub_state.dart';
part 'portfolio_hub_widgets.dart';

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
    final state = ref.watch(portfolioHubProvider);

    return AppPageScaffold(
      title: l10n.portfolioHubTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          onPress: () => context.push(FinanceRoutes.tradeEntry),
        ),
        AppAdaptiveActionMenu(
          title: l10n.shellMoreActions,
          actions: [
            AppAdaptiveAction(
              icon: FLucideIcons.bellRing,
              title: l10n.wealthWatchlistSectionTitle,
              onPress: () => context.push(FinanceRoutes.wealthWatchlist),
            ),
            AppAdaptiveAction(
              icon: FLucideIcons.refreshCw,
              title: l10n.commonRefresh,
              onPress: () => ref.read(portfolioHubProvider.notifier).refresh(),
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
        error: (error, stackTrace) => AppEmptyState.error(
          title: userSafeErrorMessage(
            context,
            error,
            stackTrace: stackTrace,
            operation: 'load portfolio hub',
          ),
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.read(portfolioHubProvider.notifier).refresh(),
        ),
        data: (data) => _PortfolioHubBody(
          data: data,
          view: _view,
          section: _section,
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
  });

  final PortfolioHubState data;
  final PortfolioHubView view;
  final _PortfolioSection section;
  final ValueChanged<PortfolioHubView> onViewChanged;
  final ValueChanged<_PortfolioSection> onSectionChanged;

  @override
  State<_PortfolioHubBody> createState() => _PortfolioHubBodyState();
}

class _PortfolioHubBodyState extends State<_PortfolioHubBody> {
  bool _showAllPositions = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = widget.data;
    final groups = data.groupsFor(widget.view, l10n);
    final visibleHoldings =
        (_showAllPositions ? data.holdings : data.holdings.take(6)).toList(
          growable: false,
        );

    return AdaptiveContentFrame(
      maxWidth: AdaptiveMaxWidth.page,
      expandSinglePrimary: true,
      primary: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: kTabBarOffset),
        children: [
          _PortfolioSummary(data: data),
          const SizedBox(height: AppSpacing.s16),
          _PortfolioSectionSegment(
            value: widget.section,
            onChanged: widget.onSectionChanged,
          ),
          const SizedBox(height: AppSpacing.s16),
          switch (widget.section) {
            _PortfolioSection.positions => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PortfolioSectionTitle(title: l10n.portfolioHubPositionsTitle),
                if (data.holdings.isEmpty)
                  _EmptyState(message: l10n.portfolioHubEmpty)
                else
                  AppGroupedSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < visibleHoldings.length; i++) ...[
                          _HoldingRow(holding: visibleHoldings[i]),
                          if (i != visibleHoldings.length - 1)
                            const AppGroupedDivider(
                              indent: AppSpacing.s12,
                              endIndent: AppSpacing.s12,
                            ),
                        ],
                      ],
                    ),
                  ),
                if (data.holdings.length > 6) ...[
                  const SizedBox(height: AppSpacing.s8),
                  AppQuietButton(
                    label: _showAllPositions
                        ? l10n.portfolioHubShowFewerPositions
                        : l10n.portfolioHubShowAllPositions,
                    onPress: () =>
                        setState(() => _showAllPositions = !_showAllPositions),
                    expanded: true,
                    prefix: Icon(
                      _showAllPositions
                          ? FLucideIcons.chevronUp
                          : FLucideIcons.chevronDown,
                    ),
                  ),
                ],
              ],
            ),
            _PortfolioSection.allocation => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
            _PortfolioSection.insights => _EngineExposureSection(data: data),
          },
        ],
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
        Haptics.selection();
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
    final l10n = AppLocalizations.of(context);
    final xirr = data.xirrRatio;
    final pnlPercent = data.costBasisInBase.sign <= 0
        ? null
        : (data.unrealizedPnlInBase / data.costBasisInBase).toDouble() * 100;
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
                  amount: data.marketValueInBase.toDouble(),
                  currencyCode: data.baseCurrency,
                  style: TypographyTokens.displaySmall,
                ),
              ),
              DeltaChip(value: pnlPercent, fractionDigits: 2),
            ],
          ),
          const SizedBox(height: AppSpacing.s14),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric.money(
                  label: l10n.portfolioHubCostBasisLabel,
                  amount: data.costBasisInBase.toDouble(),
                  currency: data.baseCurrency,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: _SummaryMetric.money(
                  label: l10n.portfolioHubAbsoluteReturnLabel,
                  amount: data.unrealizedPnlInBase.toDouble(),
                  currency: data.baseCurrency,
                  showSign: true,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: _SummaryMetric(
                  label: l10n.portfolioHubYtdXirrLabel,
                  value: xirr == null ? '—' : _formatRatio(context, xirr),
                ),
              ),
            ],
          ),
        ],
      ),
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
