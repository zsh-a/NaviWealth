part of 'portfolio_hub_page.dart';

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
    final labels = {
      PortfolioHubView.account: l10n.portfolioHubViewAccount,
      PortfolioHubView.currency: l10n.portfolioHubViewCurrency,
      PortfolioHubView.assetClass: l10n.portfolioHubViewAssetClass,
    };
    final icons = {
      PortfolioHubView.account: FLucideIcons.wallet,
      PortfolioHubView.currency: FLucideIcons.banknote,
      PortfolioHubView.assetClass: FLucideIcons.layoutGrid,
    };

    return Container(
      decoration: BoxDecoration(
        color: context.theme.colors.secondary.withValues(
          alpha: AppOpacity.disabled,
        ),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      padding: const EdgeInsets.all(AppSpacing.s2),
      child: Row(
        children: [
          for (final view in PortfolioHubView.values)
            Expanded(
              child: _ViewChip(
                label: labels[view]!,
                icon: icons[view]!,
                selected: value == view,
                onTap: () {
                  Haptics.selection();
                  onChanged(view);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewChip extends StatelessWidget {
  const _ViewChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? context.theme.colors.primary
        : context.theme.colors.mutedForeground;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: Motion.medium,
        curve: Motion.emphasizedDecelerate,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.s8,
          horizontal: AppSpacing.s4,
        ),
        decoration: BoxDecoration(
          color: selected
              ? context.theme.colors.background
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIconSizes.h18, color: color),
            const SizedBox(width: AppSpacing.s6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style:
                    (selected
                            ? context.captionStrongStyle
                            : context.captionMediumStyle)
                        .copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupRowCard extends StatelessWidget {
  const _GroupRowCard({required this.group});

  final PortfolioGroupRow group;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
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
    );
  }
}

class _HoldingRowCard extends StatelessWidget {
  const _HoldingRowCard({required this.holding});

  final PortfolioHoldingRow holding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final pnl = holding.unrealizedPnlInBase;
    final pnlColor = MarketColors.of(context).forDelta(pnl.toDouble());
    final subtitle = _holdingSubtitle(l10n, holding);
    return SoftCard(
      borderless: true,
      tinted: false,
      child: FTappable(
        onPress: () => context.push(FinanceRoutes.wealthAsset(holding.assetId)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
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
