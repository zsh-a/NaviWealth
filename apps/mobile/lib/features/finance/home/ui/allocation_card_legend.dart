part of 'allocation_card.dart';

class _Legend extends StatelessWidget {
  const _Legend({
    required this.assetAllocs,
    required this.liabilityAlloc,
    required this.snapshot,
    required this.onTap,
  });

  final List<CategoryAllocation> assetAllocs;
  final CategoryAllocation? liabilityAlloc;
  final DashboardSnapshot snapshot;
  final void Function(CategoryAllocation) onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = ChartPalette.of(context);
    // Percent denominator: sum of positive category totals only, so
    // negative cash doesn't inflate other categories past 100%.
    final positiveTotal = assetAllocs
        .map((a) => a.totalInBase.amount.toDouble())
        .where((v) => v > 0)
        .fold<double>(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < assetAllocs.length; i++)
          _LegendRow(
            color: palette.accentAt(i),
            label: AssetCategoryVisuals.label(l10n, assetAllocs[i].category),
            icon: AssetCategoryVisuals.icon(assetAllocs[i].category),
            valueInBase: assetAllocs[i].totalInBase.amount.toDouble(),
            currencyCode: snapshot.baseCurrency,
            percent: positiveTotal == 0
                ? 0
                : assetAllocs[i].totalInBase.amount.toDouble() / positiveTotal,
            onTap: () => onTap(assetAllocs[i]),
          ),
        if (liabilityAlloc != null) ...[
          const SizedBox(height: AppSpacing.s8),
          const FDivider(),
          const SizedBox(height: AppSpacing.s8),
          _LegendRow(
            color: context.theme.colors.destructive,
            label: AssetCategoryVisuals.label(l10n, liabilityAlloc!.category),
            icon: AssetCategoryVisuals.icon(liabilityAlloc!.category),
            valueInBase: -liabilityAlloc!.totalInBase.amount.toDouble(),
            currencyCode: snapshot.baseCurrency,
            percent: null,
            onTap: () => onTap(liabilityAlloc!),
          ),
        ],
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.icon,
    required this.valueInBase,
    required this.currencyCode,
    required this.percent,
    required this.onTap,
  });

  final Color color;
  final String label;
  final IconData icon;
  final double valueInBase;
  final String currencyCode;
  final double? percent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pctText = percent == null
        ? null
        : '${(percent! * 100).toStringAsFixed(1)}%';
    return MergeSemantics(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          // Material 48dp touch-target floor — the visual row is shorter
          // than this, so the InkWell pads itself out vertically.
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.s12,
              horizontal: AppSpacing.s8,
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Icon(
                  icon,
                  size: AppIconSizes.sm,
                  color: context.theme.colors.mutedForeground,
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: context.theme.typography.body.sm),
                      if (pctText != null)
                        Text(pctText, style: context.captionStyle),
                    ],
                  ),
                ),
                MoneyText(
                  amount: valueInBase,
                  currencyCode: currencyCode,
                  compact: true,
                  showSign: valueInBase < 0,
                ),
                const SizedBox(width: AppSpacing.s4),
                Icon(
                  FLucideIcons.chevronRight,
                  size: AppIconSizes.sm,
                  color: context.theme.colors.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
