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
part 'portfolio_hub_state.dart';
part 'portfolio_hub_widgets.dart';

class PortfolioHubPage extends ConsumerStatefulWidget {
  const PortfolioHubPage({super.key});

  @override
  ConsumerState<PortfolioHubPage> createState() => _PortfolioHubPageState();
}

class _PortfolioHubPageState extends ConsumerState<PortfolioHubPage> {
  PortfolioHubView _view = PortfolioHubView.account;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(portfolioHubProvider);

    return AppPageScaffold(
      title: l10n.portfolioHubTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.refreshCw),
          onPress: () => ref.read(portfolioHubProvider.notifier).refresh(),
        ),
      ],
      childPad: false,
      child: state.when(
        loading: () => const _PortfolioHubSkeleton(),
        error: (error, _) => AppEmptyState.error(
          title: l10n.portfolioHubLoadError('$error'),
          action: FButton(
            variant: FButtonVariant.ghost,
            onPress: () => ref.read(portfolioHubProvider.notifier).refresh(),
            child: Text(l10n.commonRetry),
          ),
        ),
        data: (data) => _PortfolioHubBody(
          data: data,
          view: _view,
          onViewChanged: (next) => setState(() => _view = next),
        ),
      ),
    );
  }
}

class _PortfolioHubBody extends StatelessWidget {
  const _PortfolioHubBody({
    required this.data,
    required this.view,
    required this.onViewChanged,
  });

  final PortfolioHubState data;
  final PortfolioHubView view;
  final ValueChanged<PortfolioHubView> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final hPad = Breakpoints.isMobile(width) ? AppSpacing.s16 : AppSpacing.s24;
    final groups = data.groupsFor(view, l10n);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        hPad,
        AppSpacing.s8,
        hPad,
        kTabBarOffset + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _PortfolioSummary(data: data),
        const SizedBox(height: AppSpacing.s16),
        PortfolioHubViewSegment(value: view, onChanged: onViewChanged),
        const SizedBox(height: AppSpacing.s12),
        _PortfolioSectionTitle(title: l10n.portfolioHubHoldingsTitle),
        if (groups.isEmpty)
          _EmptyState(message: l10n.portfolioHubEmpty)
        else
          for (final group in groups) ...[
            _GroupRowCard(group: group),
            const SizedBox(height: AppSpacing.s10),
          ],
        const SizedBox(height: AppSpacing.s8),
        _PortfolioSectionTitle(title: l10n.portfolioHubPositionsTitle),
        if (data.holdings.isEmpty)
          _EmptyState(message: l10n.portfolioHubEmpty)
        else
          for (final holding in data.holdings.take(12)) ...[
            _HoldingRowCard(holding: holding),
            const SizedBox(height: AppSpacing.s10),
          ],
        const SizedBox(height: AppSpacing.s8),
        _EngineExposureSection(data: data),
        const SizedBox(height: AppSpacing.s16),
        const _DcaSimulatorEntry(),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.portfolioHubMarketValueLabel.toUpperCase(),
          style: context.microCaptionStyle,
        ),
        const SizedBox(height: AppSpacing.s4),
        AnimatedMoneyText(
          amount: data.marketValueInBase.toDouble(),
          currencyCode: data.baseCurrency,
          style: TypographyTokens.numericTitleStrong,
        ),
        const SizedBox(height: AppSpacing.s14),
        Row(
          children: [
            Expanded(
              child: _SummaryMetric(
                label: l10n.portfolioHubYtdXirrLabel,
                value: xirr == null ? '—' : _formatRatio(context, xirr),
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _SummaryMetric.money(
                label: l10n.portfolioHubAbsoluteReturnLabel,
                amount: data.unrealizedPnlInBase.toDouble(),
                currency: data.baseCurrency,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DcaSimulatorEntry extends StatelessWidget {
  const _DcaSimulatorEntry();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.muted.withValues(alpha: AppOpacity.muted),
        borderRadius: BorderRadius.circular(AppRadius.xlg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
        child: FTile(
          onPress: () => context.push(FinanceRoutes.planDca),
          prefix: Icon(
            FLucideIcons.calendarClock,
            color: context.theme.colors.mutedForeground,
          ),
          title: Text(l10n.dcaSimulatorTitle),
          subtitle: Text(l10n.dcaSimulatorAccountsEntrySubtitle),
          suffix: const Icon(FLucideIcons.chevronRight, size: AppIconSizes.h18),
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value})
    : amount = null,
      currency = null;

  const _SummaryMetric.money({
    required this.label,
    required double this.amount,
    required String this.currency,
  }) : value = null;

  final String label;
  final String? value;
  final double? amount;
  final String? currency;

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
            if (amount == null)
              Text(value ?? '—', style: context.theme.typography.body.lg)
            else
              AnimatedMoneyText(
                amount: amount,
                currencyCode: currency!,
                showSign: true,
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
