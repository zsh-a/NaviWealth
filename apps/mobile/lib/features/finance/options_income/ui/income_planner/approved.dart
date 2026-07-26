part of 'income_planner_page.dart';

class _ApprovedEmpty extends StatelessWidget {
  const _ApprovedEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.listChecks,
      title: l10n.incomePlannerNoApprovedTitle,
      message: l10n.incomePlannerNoApprovedBody,
      compact: true,
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

class _ApprovedTile extends ConsumerWidget {
  const _ApprovedTile({required this.item});

  final ApprovedUnderlying item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.flat(
      onPress: () {
        final plan = ref
            .read(incomeStrategyPlansProvider)
            .value
            ?.where((plan) => plan.assetId == item.id)
            .firstOrNull;
        showIncomeStrategyPlanSheet(context, existing: plan);
      },
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
                  Text(
                    _approvedIntentSummary(l10n, item),
                    style: context.captionStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            AppBadge(
              label: l10n.incomePlannerProfileAllowPut,
              tone: item.allowPut ? AppBadgeTone.accent : AppBadgeTone.neutral,
              size: AppBadgeSize.compact,
            ),
            const SizedBox(width: AppSpacing.s6),
            AppBadge(
              label: l10n.incomePlannerProfileAllowCall,
              tone: item.allowCall ? AppBadgeTone.accent : AppBadgeTone.neutral,
              size: AppBadgeSize.compact,
            ),
            const SizedBox(width: AppSpacing.s6),
            const Icon(FLucideIcons.chevronRight, size: AppIconSizes.sm),
          ],
        ),
      ),
    );
  }
}

String _approvedIntentSummary(AppLocalizations l10n, ApprovedUnderlying item) {
  final intents = <String>[
    if (item.allowPut)
      item.maxBuyPrice == null
          ? l10n.incomePlannerApprovedPutNoLimit
          : l10n.incomePlannerApprovedPutLimit(item.maxBuyPrice!.toString()),
    if (item.allowCall)
      item.minSellPrice == null
          ? l10n.incomePlannerApprovedCallNoLimit
          : l10n.incomePlannerApprovedCallLimit(item.minSellPrice!.toString()),
  ];
  return intents.join(' · ');
}
