part of 'income_planner_page.dart';

enum _JournalFilter { all, open, resolved }

class _TradeJournalSection extends ConsumerStatefulWidget {
  const _TradeJournalSection();

  @override
  ConsumerState<_TradeJournalSection> createState() =>
      _TradeJournalSectionState();
}

class _TradeJournalSectionState extends ConsumerState<_TradeJournalSection> {
  _JournalFilter _filter = _JournalFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entriesAsync = ref.watch(tradeJournalEntriesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                onPress: () => showTradeJournalSheet(context),
                child: Text(l10n.incomePlannerJournalAddCta),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        SegmentedRow<_JournalFilter>(
          options: _JournalFilter.values,
          value: _filter,
          labelOf: (filter) => switch (filter) {
            _JournalFilter.all => l10n.incomePlannerJournalFilterAll,
            _JournalFilter.open => l10n.incomePlannerJournalFilterOpen,
            _JournalFilter.resolved => l10n.incomePlannerJournalFilterResolved,
          },
          onChanged: (filter) => setState(() => _filter = filter),
        ),
        const SizedBox(height: AppSpacing.s12),
        entriesAsync.when(
          loading: () => const _LoadingTile(),
          error: (error, _) => AppEmptyState.error(
            title: l10n.incomePlannerRefreshFailedTitle,
            message: userSafeErrorMessage(context, error),
            compact: true,
          ),
          data: (entries) {
            final visible = entries.where(_matchesFilter).toList();
            if (visible.isEmpty) {
              return AppEmptyState(
                icon: FLucideIcons.notebookPen,
                title: entries.isEmpty
                    ? l10n.incomePlannerJournalEmpty
                    : l10n.incomePlannerJournalFilterEmpty,
                compact: true,
                // The journal fills itself from recorded trades; the only
                // recoverable dead end here is an over-narrow filter.
                action: entries.isEmpty
                    ? null
                    : FButton(
                        variant: FButtonVariant.outline,
                        onPress: _resetFilter,
                        child: Text(l10n.incomePlannerOpportunityFilterAll),
                      ),
              );
            }
            return Column(
              children: [
                for (final entry in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                    child: _JournalTile(entry: entry),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _resetFilter() => setState(() => _filter = _JournalFilter.all);

  bool _matchesFilter(TradeJournalEntry entry) => switch (_filter) {
    _JournalFilter.all => true,
    _JournalFilter.open => entry.status == TradeJournalStatus.open,
    _JournalFilter.resolved => entry.status != TradeJournalStatus.open,
  };
}

class _JournalTile extends StatelessWidget {
  const _JournalTile({required this.entry});

  final TradeJournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pnl = entry.trackedNetPnl;
    final subtitle = <String>[
      tradeJournalStatusLabel(l10n, entry.status),
      optionsStrategyKindShortLabel(l10n, entry.strategy),
      if (entry.expirationAt != null)
        l10n.incomePlannerJournalExpiresIn(_daysUntil(entry.expirationAt!)),
    ].join(' · ');
    return SoftCard.flat(
      onPress: () => showTradeJournalSheet(context, existingId: entry.id),
      padding: AppPageRhythm.densePadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.symbol} · ${entry.optionSymbol}',
                  style: context.rowTitleStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(subtitle, style: context.captionStyle),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  l10n.incomePlannerJournalQuantitySummary(
                    entry.contractQuantity,
                    entry.effectiveContractSize,
                  ),
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                pnl == null
                    ? l10n.incomePlannerJournalPremiumLabel
                    : l10n.incomePlannerJournalNetPnlLabel,
                style: context.captionStyle,
              ),
              const SizedBox(height: AppSpacing.s2),
              MoneyText(
                amount: (pnl ?? entry.grossEntryCredit).toDouble(),
                currencyCode: entry.currency,
                showSign: true,
                style: context.labelStyle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
