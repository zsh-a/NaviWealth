part of 'income_planner_page.dart';

class _TradeJournalSection extends ConsumerWidget {
  const _TradeJournalSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.incomePlannerJournalSectionTitle,
          trailing: Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => context.push(FinanceRoutes.planIncomeStats),
                child: Text(l10n.incomePlannerStatsAction),
              ),
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => showTradeJournalSheet(context),
                child: Text(l10n.incomePlannerJournalAddCta),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        // Keep the planner page light; full history is available from the
        // sheet's "All entries" link.
        Consumer(
          builder: (context, ref, _) {
            final entriesAsync = ref.watch(tradeJournalEntriesProvider);
            return entriesAsync.when(
              loading: () => const _LoadingTile(),
              error: (e, _) => _ErrorCard(
                title: l10n.incomePlannerRefreshFailedTitle,
                message: '$e',
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return _EmptyCard(body: l10n.incomePlannerJournalEmpty);
                }
                return Column(
                  children: [
                    for (final entry in entries.take(3))
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.s4,
                        ),
                        child: SoftCard.flat(
                          onPress: () => showTradeJournalSheet(
                            context,
                            existingId: entry.id,
                          ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${entry.symbol} \u00b7 ${entry.optionSymbol}',
                                        style: context.labelStyle,
                                      ),
                                      const SizedBox(height: AppSpacing.s2),
                                      Text(
                                        tradeJournalStatusLabel(
                                          l10n,
                                          entry.status,
                                        ),
                                        style: context.captionStyle,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '+${entry.entryCredit}',
                                  style: context.labelStyle.copyWith(
                                    color: colors.primary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}
