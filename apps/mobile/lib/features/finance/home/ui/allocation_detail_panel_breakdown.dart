part of 'allocation_detail_panel.dart';

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.group,
    required this.total,
    required this.baseCurrency,
    required this.selected,
    required this.onTap,
  });

  final _AllocationGroup group;
  final double total;
  final String baseCurrency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = total <= 0 ? 0 : (group.value / total) * 100;
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: FTappable(
        onPress: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: AppOpacity.faint)
                : colors.foreground.withValues(alpha: AppOpacity.whisper),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected
                  ? colors.primary.withValues(alpha: AppOpacity.muted)
                  : colors.foreground.withValues(alpha: AppOpacity.faint),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s10,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: group.color.withValues(alpha: AppOpacity.medium),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    group.icon,
                    size: AppIconSizes.h18,
                    color: group.color,
                  ),
                ),
                const SizedBox(width: AppSpacing.s10),
                Expanded(
                  child: Text(
                    group.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.labelStyle,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(
                      amount: group.value,
                      currencyCode: baseCurrency,
                      compact: true,
                      style: context.labelStyle,
                    ),
                    Text(
                      '${pct.toStringAsFixed(pct >= 10 ? 0 : 1)}%',
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DrillDownList extends StatelessWidget {
  const _DrillDownList({required this.group, required this.baseCurrency});

  final _AllocationGroup group;
  final String baseCurrency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.dashboardDrillDownItemCount(group.items.length),
          style: context.captionLabelStyle.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        for (final item in group.items)
          FTile(
            prefix: Icon(group.icon, color: group.color),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: _subtitle(l10n, item) == null
                ? null
                : Text(
                    _subtitle(l10n, item)!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            suffix: MoneyText(
              amount: item.valueInBase.amount.toDouble(),
              currencyCode: baseCurrency,
              compact: true,
            ),
            onPress: item.routeHint == null
                ? null
                : () => context.push(item.routeHint!),
          ),
      ],
    );
  }

  String? _subtitle(AppLocalizations l10n, CategoryItem item) {
    if (item.liabilityType != null) {
      return liabilityTypeLabel(l10n, item.liabilityType!);
    }
    return item.subtitle;
  }
}
