part of 'portfolio_hub_page.dart';

Future<void> _showPortfolioGroupDetail({
  required BuildContext context,
  required PortfolioGroupRow group,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: group.title,
    subtitle:
        '${group.subtitle} · ${l10n.portfolioHubHoldingCount(group.holdingsCount)}',
    maxHeightFactor: 0.9,
    builder: (sheetContext) => _PortfolioGroupDetail(
      group: group,
      onHoldingPressed: (holding) {
        Navigator.of(sheetContext).pop();
        if (context.mounted) {
          context.push(FinanceRoutes.wealthAsset(holding.assetId));
        }
      },
    ),
  );
}

class _PortfolioGroupDetail extends StatelessWidget {
  const _PortfolioGroupDetail({
    required this.group,
    required this.onHoldingPressed,
  });

  final PortfolioGroupRow group;
  final ValueChanged<PortfolioHoldingRow> onHoldingPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      key: const ValueKey<String>('portfolio-group-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s14),
            child: Row(
              children: [
                Expanded(
                  child: _GroupDetailMetric(
                    label: l10n.portfolioHubMarketValueLabel,
                    child: AnimatedMoneyText(
                      amount: group.marketValueInBase.toDouble(),
                      currencyCode: group.baseCurrency,
                      style: context.labelStyle,
                    ),
                  ),
                ),
                Expanded(
                  child: _GroupDetailMetric(
                    label: l10n.targetAllocationEditorPercentLabel,
                    child: Text(
                      _formatRatio(context, group.weight.toDouble()),
                      style: context.labelStyle,
                    ),
                  ),
                ),
                Expanded(
                  child: _GroupDetailMetric(
                    label: l10n.assetDetailUnrealizedPnL,
                    child: AnimatedMoneyText(
                      amount: group.unrealizedPnlInBase.toDouble(),
                      currencyCode: group.baseCurrency,
                      showSign: true,
                      style: context.labelStyle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        AppSheetSectionLabel(l10n.portfolioHubPositionsTitle),
        AppGroupedSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < group.holdings.length; i++) ...[
                _HoldingRow(
                  holding: group.holdings[i],
                  onPressed: () => onHoldingPressed(group.holdings[i]),
                ),
                if (i != group.holdings.length - 1)
                  const AppGroupedDivider(
                    indent: AppSpacing.s12,
                    endIndent: AppSpacing.s12,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _GroupDetailMetric extends StatelessWidget {
  const _GroupDetailMetric({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.captionStyle,
        ),
        const SizedBox(height: AppSpacing.s4),
        child,
      ],
    );
  }
}
