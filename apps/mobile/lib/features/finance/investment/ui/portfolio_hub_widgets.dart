part of 'portfolio_hub_page.dart';

Future<T?> _showPortfolioDetailSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  String? subtitle,
  Widget? footer,
}) => showAppSheet<T>(
  context: context,
  title: title,
  subtitle: subtitle,
  footer: footer,
  actions: [
    Builder(
      builder: (sheetContext) => AppIconButton(
        key: const ValueKey('portfolio-detail-close'),
        icon: FLucideIcons.x,
        tooltip: AppLocalizations.of(sheetContext).commonClose,
        onPress: () => Navigator.of(sheetContext).pop(),
      ),
    ),
  ],
  builder: builder,
);

/// Keeps the worst breach and its recovery action visible in a compact surface.
class _ConcentrationRiskSection extends StatelessWidget {
  const _ConcentrationRiskSection({required this.alerts});

  final List<ConcentrationAlert> alerts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final criticalCount = alerts
        .where((a) => a.severity == RiskSeverity.critical)
        .length;
    final ordered = [...alerts]
      ..sort((a, b) {
        final severity = (b.severity == RiskSeverity.critical ? 1 : 0)
            .compareTo(a.severity == RiskSeverity.critical ? 1 : 0);
        return severity != 0
            ? severity
            : (b.weight - b.threshold).compareTo(a.weight - a.threshold);
      });
    return SoftCard.raised(
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
                  l10n.portfolioHubConcentrationTitle,
                  style: context.labelStyle,
                ),
              ),
              Semantics(
                label: l10n.portfolioHubConcentrationSummary(alerts.length),
                child: AppBadge(
                  label: '${alerts.length}',
                  size: AppBadgeSize.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          _ConcentrationAlertRow(alert: ordered.first),
          const SizedBox(height: AppSpacing.s4),
          Row(
            children: [
              Expanded(
                child: FButton(
                  variant: FButtonVariant.ghost,
                  onPress: () => context.push(FinanceRoutes.planRebalance),
                  child: Flexible(
                    child: Text(l10n.portfolioStudioRebalanceAction),
                  ),
                ),
              ),
              if (alerts.length > 1)
                Expanded(
                  child: FButton(
                    key: const ValueKey('portfolio-risk-details'),
                    variant: FButtonVariant.ghost,
                    onPress: () => _showPortfolioDetailSheet<void>(
                      context: context,
                      title: l10n.portfolioHubConcentrationTitle,
                      subtitle: l10n.portfolioHubConcentrationSummary(
                        alerts.length,
                      ),
                      builder: (_) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (
                            var index = 0;
                            index < ordered.length;
                            index++
                          ) ...[
                            if (index > 0)
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: AppSpacing.s12,
                                ),
                                child: AppGroupedDivider(),
                              ),
                            _ConcentrationAlertRow(alert: ordered[index]),
                          ],
                        ],
                      ),
                    ),
                    child: Flexible(
                      child: Text(l10n.portfolioHubAllRisks(alerts.length)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(alert.label, style: context.labelStyle),
            Text(
              l10n.portfolioHubConcentrationWeightLine(weightPct, thresholdPct),
              style: context.captionLabelStyle,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s2),
        Text('$dimension · $severity', style: context.captionStyle),
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
        AppInteraction.signal(AppInteractionIntent.select);
        onChanged(next);
      },
    );
  }
}

bool _usePortfolioTable(BuildContext context, double width) =>
    width >= 1000 * MediaQuery.textScalerOf(context).scale(1);

/// Shared column geometry keeps the lazy rows aligned with their header.
class _HoldingColumns extends StatelessWidget {
  const _HoldingColumns({
    required this.identity,
    required this.quantity,
    required this.weight,
    required this.value,
    required this.pnl,
  });

  final Widget identity;
  final Widget quantity;
  final Widget weight;
  final Widget value;
  final Widget pnl;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(flex: 4, child: identity),
      const SizedBox(width: AppSpacing.s16),
      Expanded(flex: 2, child: quantity),
      const SizedBox(width: AppSpacing.s16),
      Expanded(child: weight),
      const SizedBox(width: AppSpacing.s16),
      Expanded(flex: 3, child: value),
      const SizedBox(width: AppSpacing.s16),
      Expanded(flex: 3, child: pnl),
    ],
  );
}

class _HoldingTableHeader extends StatelessWidget {
  const _HoldingTableHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget label(String value, {bool leading = false}) => Text(
      value,
      style: context.captionStyle,
      textAlign: leading ? TextAlign.start : TextAlign.end,
    );
    return Padding(
      key: const ValueKey('portfolio-holdings-columns'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        0,
        AppSpacing.s12,
        AppSpacing.s8,
      ),
      child: _HoldingColumns(
        identity: label(l10n.portfolioHubAssetColumn, leading: true),
        quantity: label(l10n.assetDetailCurrentQuantity),
        weight: label(l10n.targetAllocationEditorPercentLabel),
        value: label(l10n.portfolioHubMarketValueLabel),
        pnl: label(l10n.portfolioHubAbsoluteReturnLabel),
      ),
    );
  }
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({super.key, required this.holding, required this.tabular});

  final PortfolioHoldingRow holding;
  final bool tabular;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final pnl = holding.unrealizedPnlInBase;
    final pnlColor = context.appTheme.market.roleForDelta(pnl.toDouble()).fg;
    final subtitle = _holdingSubtitle(l10n, holding);
    final quantity = formatters.number(
      holding.quantity.toDouble(),
      decimalDigits: _quantityDigits(holding.quantity),
    );
    final weight = _formatRatio(context, holding.weight.toDouble());
    final identity = Row(
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
            heroTag: 'asset-${holding.assetId}-name',
          ),
        ),
      ],
    );
    final value = OptionalHero(
      tag: 'asset-${holding.assetId}-value',
      child: AnimatedMoneyText(
        amount: holding.marketValueInBase.toDouble(),
        currencyCode: holding.baseCurrency,
        style: context.labelStyle,
        textAlign: TextAlign.end,
      ),
    );
    final profit = AnimatedMoneyText(
      amount: pnl.toDouble(),
      currencyCode: holding.baseCurrency,
      showSign: true,
      style: context.captionLabelStyle,
      color: pnlColor,
      textAlign: TextAlign.end,
    );
    return Semantics(
      button: true,
      container: true,
      child: AppTappable(
        onPress: () => context.push(FinanceRoutes.wealthAsset(holding.assetId)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: tabular
              ? _HoldingColumns(
                  identity: identity,
                  quantity: Text(
                    quantity,
                    style: context.captionLabelStyle,
                    textAlign: TextAlign.end,
                  ),
                  weight: Text(
                    weight,
                    style: context.captionLabelStyle,
                    textAlign: TextAlign.end,
                  ),
                  value: value,
                  pnl: profit,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked =
                        MediaQuery.textScalerOf(context).scale(1) > 1.3 ||
                        constraints.maxWidth < 300;
                    final amounts = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        value,
                        const SizedBox(height: AppSpacing.s4),
                        profit,
                      ],
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (stacked) ...[
                          identity,
                          const SizedBox(height: AppSpacing.s8),
                          amounts,
                        ] else
                          Row(
                            children: [
                              Expanded(flex: 3, child: identity),
                              const SizedBox(width: AppSpacing.s12),
                              Expanded(flex: 2, child: amounts),
                            ],
                          ),
                        const SizedBox(height: AppSpacing.s8),
                        Wrap(
                          spacing: AppSpacing.s16,
                          runSpacing: AppSpacing.s4,
                          children: [
                            Text(
                              l10n.portfolioHubQuantityInline(quantity),
                              style: context.captionStyle,
                            ),
                            Text(
                              l10n.portfolioHubWeightInline(weight),
                              style: context.captionStyle,
                            ),
                          ],
                        ),
                      ],
                    );
                  },
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

class _TitleSubtitle extends StatelessWidget {
  const _TitleSubtitle({
    required this.title,
    required this.subtitle,
    this.heroTag,
  });

  final String title;
  final String subtitle;

  /// When set, the title flies to the pushed detail header via [OptionalHero].
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.labelStyle,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heroTag == null
            ? titleText
            : OptionalHero(tag: heroTag!, child: titleText),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.chartPie,
      title: message,
      action: FButton(
        variant: FButtonVariant.outline,
        onPress: () => context.push(FinanceRoutes.tradeEntry),
        prefix: const Icon(FLucideIcons.plus, size: AppIconSizes.sm),
        child: Text(l10n.tradeEntryAppBarTitle),
      ),
    );
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
