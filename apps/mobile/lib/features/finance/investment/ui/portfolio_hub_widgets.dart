part of 'portfolio_hub_page.dart';

/// Surfaces user-threshold concentration breaches on the Allocation tab so
/// Financial Inbox deep links to `/wealth/portfolio` land on a real review UI.
class _ConcentrationRiskSection extends ConsumerWidget {
  const _ConcentrationRiskSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(concentrationAlertsProvider);
    return async.when(
      skipLoadingOnReload: true,
      // loading: intentionally empty — this section only exists when there
      // are concentration breaches; a skeleton would promise content that
      // usually never appears and shift the Allocation tab on resolve.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (alerts) {
        if (alerts.isEmpty) return const SizedBox.shrink();
        final criticalCount = alerts
            .where((a) => a.severity == RiskSeverity.critical)
            .length;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PortfolioSectionTitle(
                title: l10n.portfolioHubConcentrationTitle,
              ),
              SoftCard.raised(
                borderless: true,
                padding: const EdgeInsets.all(AppSpacing.s12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          FLucideIcons.chartPie,
                          size: AppIconSizes.h18,
                          color: criticalCount > 0
                              ? context.theme.colors.destructive
                              : context.theme.colors.primary,
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Expanded(
                          child: Text(
                            l10n.portfolioHubConcentrationSummary(
                              alerts.length,
                            ),
                            style: context.labelStyle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s10),
                    for (var i = 0; i < alerts.length; i++) ...[
                      if (i != 0) const SizedBox(height: AppSpacing.s8),
                      _ConcentrationAlertRow(alert: alerts[i]),
                    ],
                    const SizedBox(height: AppSpacing.s12),
                    FButton(
                      variant: FButtonVariant.secondary,
                      onPress: () => context.push(FinanceRoutes.planRebalance),
                      child: Text(l10n.portfolioHubConcentrationRebalanceCta),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConcentrationAlertRow extends StatelessWidget {
  const _ConcentrationAlertRow({required this.alert});

  final ConcentrationAlert alert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final weightPct = (alert.weight * 100).toStringAsFixed(1);
    final thresholdPct = (alert.threshold * 100).toStringAsFixed(0);
    final dimension = switch (alert.dimension) {
      RiskDimension.asset => l10n.portfolioHubConcentrationDimensionAsset,
      RiskDimension.sector => l10n.portfolioHubConcentrationDimensionSector,
      RiskDimension.region => l10n.portfolioHubConcentrationDimensionRegion,
      RiskDimension.currency => l10n.portfolioHubConcentrationDimensionCurrency,
    };
    final severity = alert.severity == RiskSeverity.critical
        ? l10n.portfolioHubConcentrationSeverityCritical
        : l10n.portfolioHubConcentrationSeverityWarning;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(alert.label, style: context.labelStyle),
              const SizedBox(height: AppSpacing.s2),
              Text('$dimension · $severity', style: context.captionStyle),
            ],
          ),
        ),
        Text(
          l10n.portfolioHubConcentrationWeightLine(weightPct, thresholdPct),
          style: context.captionLabelStyle,
          textAlign: TextAlign.end,
        ),
      ],
    );
  }
}

class PortfolioHubViewSegment extends StatelessWidget {
  const PortfolioHubViewSegment({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PortfolioHubView value;
  final ValueChanged<PortfolioHubView> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SegmentedRow<PortfolioHubView>(
      options: PortfolioHubView.values,
      value: value,
      labelOf: (view) => switch (view) {
        PortfolioHubView.account => l10n.portfolioHubViewAccount,
        PortfolioHubView.currency => l10n.portfolioHubViewCurrency,
        PortfolioHubView.assetClass => l10n.portfolioHubViewAssetClass,
      },
      iconOf: (view) => switch (view) {
        PortfolioHubView.account => FLucideIcons.wallet,
        PortfolioHubView.currency => FLucideIcons.banknote,
        PortfolioHubView.assetClass => FLucideIcons.layoutGrid,
      },
      onChanged: (next) {
        Haptics.selection();
        onChanged(next);
      },
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.onPressed});

  final PortfolioGroupRow group;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: group.title,
      child: FTappable(
        onPress: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _TitleSubtitle(
                      title: group.title,
                      subtitle:
                          '${group.subtitle} · ${l10n.portfolioHubHoldingCount(group.holdingsCount)}',
                    ),
                  ),
                  AnimatedMoneyText(
                    amount: group.marketValueInBase.toDouble(),
                    currencyCode: group.baseCurrency,
                    style: context.labelStyle,
                  ),
                  const SizedBox(width: AppSpacing.s6),
                  Icon(
                    FLucideIcons.chevronRight,
                    size: AppIconSizes.h18,
                    color: context.theme.colors.mutedForeground,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s10),
              _WeightBar(weight: group.weight.toDouble()),
              const SizedBox(height: AppSpacing.s8),
              Row(
                children: [
                  Text(
                    _formatRatio(context, group.weight.toDouble()),
                    style: context.captionStyle,
                  ),
                  const Spacer(),
                  AnimatedMoneyText(
                    amount: group.unrealizedPnlInBase.toDouble(),
                    currencyCode: group.baseCurrency,
                    showSign: true,
                    style: context.captionStyle,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({required this.holding, this.onPressed});

  final PortfolioHoldingRow holding;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final pnl = holding.unrealizedPnlInBase;
    final pnlColor = context.appTheme.market.roleForDelta(pnl.toDouble()).fg;
    final subtitle = _holdingSubtitle(l10n, holding);
    return Semantics(
      button: true,
      container: true,
      child: FTappable(
        onPress:
            onPressed ??
            () => context.push(FinanceRoutes.wealthAsset(holding.assetId)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AppIconTile(
                    icon: _holdingIcon(holding.assetType),
                    color: context.theme.colors.primary,
                    size: AppSpacing.s32,
                  ),
                  const SizedBox(width: AppSpacing.s10),
                  Expanded(
                    child: _TitleSubtitle(
                      title: holding.title,
                      subtitle: subtitle,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AnimatedMoneyText(
                        amount: holding.marketValueInBase.toDouble(),
                        currencyCode: holding.baseCurrency,
                        style: context.labelStyle,
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      AnimatedMoneyText(
                        amount: pnl.toDouble(),
                        currencyCode: holding.baseCurrency,
                        showSign: true,
                        style: context.captionLabelStyle.copyWith(
                          color: pnlColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s10),
              Row(
                children: [
                  _HoldingMetric(
                    label: l10n.assetDetailCurrentQuantity,
                    value: formatters.number(
                      holding.quantity.toDouble(),
                      decimalDigits: _quantityDigits(holding.quantity),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  _HoldingMetric(
                    label: l10n.targetAllocationEditorPercentLabel,
                    value: _formatRatio(context, holding.weight.toDouble()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _holdingIcon(AssetType type) => switch (type) {
  AssetType.stock => FLucideIcons.chartCandlestick,
  AssetType.etf || AssetType.mutualFund => FLucideIcons.chartPie,
  AssetType.bond => FLucideIcons.landmark,
  AssetType.crypto => FLucideIcons.bitcoin,
  _ => FLucideIcons.walletCards,
};

class _HoldingMetric extends StatelessWidget {
  const _HoldingMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.captionLabelStyle.copyWith(color: colors.foreground),
          ),
        ],
      ),
    );
  }
}

class _TitleSubtitle extends StatelessWidget {
  const _TitleSubtitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.labelStyle,
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.captionStyle,
        ),
      ],
    );
  }
}

class _WeightBar extends StatelessWidget {
  const _WeightBar({required this.weight});

  final double weight;

  @override
  Widget build(BuildContext context) {
    final clamped = weight.clamp(0, 1).toDouble();
    return FDeterminateProgress(
      value: clamped,
      style: FDeterminateProgressStyle(
        constraints: const BoxConstraints.tightFor(height: 5),
        trackDecoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: context.theme.style.borderRadius.pill,
          ),
          color: context.theme.colors.secondary,
        ),
        fillDecoration: ShapeDecoration(
          shape: RoundedSuperellipseBorder(
            borderRadius: context.theme.style.borderRadius.pill,
          ),
          color: context.theme.colors.primary,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(icon: FLucideIcons.chartPie, title: message);
  }
}

class _PortfolioHubSkeleton extends StatelessWidget {
  const _PortfolioHubSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      children: const [
        SkeletonBox(width: 120, height: 12, radius: 4),
        SizedBox(height: AppSpacing.s8),
        SkeletonBox(width: 220, height: 34, radius: 8),
        SizedBox(height: AppSpacing.s24),
        SkeletonBox(height: 42, radius: 999),
        SizedBox(height: AppSpacing.s20),
        SkeletonBox(height: 82, radius: 8),
        SizedBox(height: AppSpacing.s10),
        SkeletonBox(height: 82, radius: 8),
        SizedBox(height: AppSpacing.s10),
        SkeletonBox(height: 82, radius: 8),
      ],
    );
  }
}
