part of 'dividend_center_page.dart';

class _RankingSection extends ConsumerWidget {
  const _RankingSection({required this.snapshot});

  final DividendCenterSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final rows = snapshot.ranking.take(8).toList();
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(
            title: l10n.dividendCenterHoldingRanking,
            trailing: l10n.dividendForecastStrategyTtm,
          ),
          const SizedBox(height: AppSpacing.s12),
          LayoutBuilder(
            builder: (context, constraints) {
              // Five numeric columns need room; below ~520dp fall back to
              // a two-line row instead of crushing every column.
              final compact = constraints.maxWidth < 520;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final row in rows) ...[
                    _RankRow(
                      compact: compact,
                      name: row.assetLabel,
                      amount: formatters.currency(
                        row.ttmNetInBase,
                        code: snapshot.baseCurrency,
                      ),
                      share: formatters.percent(row.portfolioShare),
                      yieldOnCost: row.netYieldOnCost == null
                          ? l10n.commonNotAvailable
                          : formatters.percent(row.netYieldOnCost!),
                      withholding: formatters.currency(
                        row.withholdingInBase,
                        code: snapshot.baseCurrency,
                      ),
                      shareLabel: l10n.dividendCenterRankingShare,
                      yieldLabel: l10n.dividendCenterRankingNetYieldOnCost,
                      withholdingLabel: l10n.dividendCenterRankingWithholding,
                      onPress: row.assetId == 'unattributed'
                          ? null
                          : () => context.push(
                              FinanceRoutes.wealthAsset(row.assetId),
                            ),
                    ),
                    if (row != rows.last)
                      const SizedBox(height: AppSpacing.s16),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.compact,
    required this.name,
    required this.amount,
    required this.share,
    required this.yieldOnCost,
    required this.withholding,
    required this.shareLabel,
    required this.yieldLabel,
    required this.withholdingLabel,
    required this.onPress,
  });

  final bool compact;
  final String name;
  final String amount;
  final String share;
  final String yieldOnCost;
  final String withholding;
  final String shareLabel;
  final String yieldLabel;
  final String withholdingLabel;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final muted = context.theme.colors.mutedForeground;
    if (compact) {
      final detail =
          '$shareLabel $share · $yieldLabel $yieldOnCost · '
          '$withholdingLabel $withholding';
      final content = Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: context.theme.typography.body.sm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Text(amount, style: TypographyTokens.numericBodyStrong),
              ],
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              detail,
              style: context.captionStyle.copyWith(color: muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
      return onPress == null
          ? content
          : FTappable(onPress: onPress, child: content);
    }
    Widget cell(String text, int flex, {Color? color}) => Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: color == null
            ? null
            : context.theme.typography.body.sm.copyWith(color: color),
      ),
    );
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              name,
              style: context.theme.typography.body.sm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          cell(amount, 3),
          cell(share, 2),
          cell(yieldOnCost, 2),
          cell(withholding, 3, color: muted),
          if (onPress != null) ...[
            const SizedBox(width: AppSpacing.s6),
            Icon(
              FLucideIcons.chevronRight,
              size: AppIconSizes.sm,
              color: muted,
            ),
          ],
        ],
      ),
    );
    return onPress == null
        ? content
        : FTappable(onPress: onPress, child: content);
  }
}
