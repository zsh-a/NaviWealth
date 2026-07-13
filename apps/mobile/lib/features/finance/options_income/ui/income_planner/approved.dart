part of 'income_planner_page.dart';

class _ApprovedEmpty extends StatelessWidget {
  const _ApprovedEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.flat(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.incomePlannerNoApprovedTitle, style: context.labelStyle),
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.incomePlannerNoApprovedBody,
              style: context.captionStyle.copyWith(height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovedList extends StatelessWidget {
  const _ApprovedList({required this.items});

  final List<ApprovedUnderlying> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: _ApprovedTile(item: item),
          ),
      ],
    );
  }
}

class _ApprovedTile extends StatelessWidget {
  const _ApprovedTile({required this.item});

  final ApprovedUnderlying item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.flat(
      onPress: () => showApprovedUnderlyingSheet(context, existing: item),
      borderRadius: AppRadius.lg,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s12,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.displaySymbol, style: context.labelStyle),
                  const SizedBox(height: AppSpacing.s2),
                  Text(item.market.wire, style: context.captionStyle),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            _StrategyChip(
              label: l10n.incomePlannerProfileAllowPut,
              enabled: item.allowPut,
            ),
            const SizedBox(width: AppSpacing.s6),
            _StrategyChip(
              label: l10n.incomePlannerProfileAllowCall,
              enabled: item.allowCall,
            ),
          ],
        ),
      ),
    );
  }
}

class _StrategyChip extends StatelessWidget {
  const _StrategyChip({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: enabled
            ? colors.primary.withValues(alpha: AppOpacity.light)
            : colors.muted,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s2,
        ),
        child: Text(
          label,
          style: context.captionMediumStyle.copyWith(
            color: enabled ? colors.primary : colors.mutedForeground,
          ),
        ),
      ),
    );
  }
}
